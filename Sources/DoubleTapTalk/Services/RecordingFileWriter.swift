import Foundation
import AppKit
import AVFoundation

private let logger = FileLogger.shared

/// Builds a canonical 44-byte PCM WAV header (RIFF/WAVE + fmt + data).
/// Pure and testable — no file I/O.
enum WAVHeader {
    /// - Parameter dataSize: byte count of the PCM payload that follows the header.
    static func make(dataSize: Int, sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16, to: &data)                     // fmt chunk size
        appendUInt16(1, to: &data)                      // audio format = PCM
        appendUInt16(UInt16(channels), to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(byteRate), to: &data)
        appendUInt16(UInt16(blockAlign), to: &data)
        appendUInt16(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(dataSize), to: &data)
        return data
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }
}

/// Streams Float32 mono PCM buffers (as produced by the recognition pipeline's
/// 16 kHz converter) into a 16-bit PCM WAV file on disk. The header sizes are
/// patched in on `finish()`.
///
/// Disk writes happen on a private serial queue: `append(_:)` only does the
/// (CPU-only) Int16 conversion on the caller — usually the audio tap thread —
/// and hands the bytes to the queue, so the realtime audio callback never
/// blocks on file I/O. All file state is touched on that queue only.
final class RecordingFileWriter {
    let fileURL: URL

    private let sampleRate: Int
    private let channels: Int
    private let bitsPerSample: Int
    /// Maximum number of WAV files kept in the directory (oldest pruned).
    let keepRecords: Int

    private let queue = DispatchQueue(label: "com.doubletaptalk.recording-writer")
    private var handle: FileHandle?
    private var dataByteCount = 0
    private var closed = false
    private var warnedAboutFormat = false

    /// The directory recordings live in: ~/Library/Application Support/DoubleTapTalk/Recordings
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DoubleTapTalk/Recordings", isDirectory: true)
    }

    /// Creates (but does not yet open) a writer for a brand-new timestamped
    /// file inside `directory`. Returns nil if the directory can't be created.
    init?(directory: URL, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16,
          keepRecords: Int = 20) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("RecordingFileWriter: cannot create directory \(directory.path): \(error)")
            return nil
        }

        let stamp = RecordingFileWriter.timestampString()
        var url = directory.appendingPathComponent("Recording_\(stamp).wav")
        var counter = 0
        while fm.fileExists(atPath: url.path) {
            counter += 1
            url = directory.appendingPathComponent("Recording_\(stamp)_\(counter).wav")
        }

        self.fileURL = url
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.keepRecords = keepRecords
    }

    static func timestampString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return fmt.string(from: Date())
    }

    /// Creates the file and writes a placeholder header. Idempotent.
    func open() throws {
        try queue.sync {
            guard handle == nil, !closed else { return }
            try Data().write(to: fileURL)
            let h = try FileHandle(forWritingTo: fileURL)
            try h.write(contentsOf: WAVHeader.make(dataSize: 0, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample))
            handle = h
        }
    }

    /// Encodes a Float32 non-interleaved mono buffer to Int16 and schedules the
    /// write. Safe to call from the audio tap thread — no disk I/O here.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.format.channelCount == 1,
              let data = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            if !warnedAboutFormat {
                warnedAboutFormat = true
                logger.warning("RecordingFileWriter: skipping unsupported buffer format (expected Float32 mono)")
            }
            return
        }

        let frames = Int(buffer.frameLength)
        let samples = data[0]
        let maxVal = Float(Int16.max)
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let clamped = max(-1.0, min(1.0, Double(samples[i])))
            let s = Int16((clamped * Double(maxVal)).rounded())
            pcm.append(UInt8(s & 0xFF))
            pcm.append(UInt8((s >> 8) & 0xFF))
        }

        queue.async { [weak self] in
            self?.write(pcm)
        }
    }

    /// Runs on `queue` only.
    private func write(_ pcm: Data) {
        guard let handle, !closed else { return }
        do {
            try handle.write(contentsOf: pcm)
            dataByteCount += pcm.count
        } catch {
            logger.error("RecordingFileWriter: write failed: \(error)")
        }
    }

    /// Flushes pending writes, patches the header sizes, closes the file,
    /// prunes old recordings and returns the file URL. Deletes the file (and
    /// returns nil) when nothing was actually recorded.
    func finish() -> URL? {
        queue.sync {
            if closed { return nil }
            closed = true
            guard let handle = handle else { return nil }
            self.handle = nil

            if dataByteCount == 0 {
                try? handle.close()
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            do {
                let header = WAVHeader.make(dataSize: dataByteCount, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: header)
                try handle.close()
                prune()
                logger.info("Recording saved: \(fileURL.path) (\(dataByteCount) bytes PCM)")
                return fileURL
            } catch {
                logger.error("RecordingFileWriter: finalize failed: \(error)")
                try? handle.close()
                return fileURL
            }
        }
    }

    /// Deletes the in-progress file (used when recording start aborts or the
    /// segment is discarded). Pending writes are flushed first so the file is
    /// never left half-written.
    func cancel() {
        queue.sync {
            if closed { return }
            closed = true
            try? handle?.close()
            handle = nil
            dataByteCount = 0
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Keeps only the most recent `keepRecords` WAV files in the recordings
    /// directory. Runs on `queue`.
    private func prune() {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let recordings = items
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        if recordings.count > keepRecords {
            for old in recordings.dropFirst(keepRecords) {
                try? fm.removeItem(at: old)
            }
            logger.info("RecordingFileWriter: pruned \(recordings.count - keepRecords) old recordings")
        }
    }
}

/// Read-only view of the recordings folder, used by the settings panel to show
/// disk usage and to offer "open folder" / "delete all". Nothing deletes
/// recordings automatically by age — the user does, from Settings.
struct RecordingStoreStats: Equatable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = RecordingStoreStats(fileCount: 0, totalBytes: 0)

    /// e.g. "12.4 MB" — for display in Settings.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

enum RecordingStore {
    /// Where recordings live (shared with `RecordingFileWriter`).
    static var directory: URL { RecordingFileWriter.defaultDirectory() }

    /// Counts WAV files and their total size. Never throws — a missing or
    /// unreadable folder simply reports zero.
    static func stats(in directory: URL) -> RecordingStoreStats {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }
        let recordings = items.filter { $0.pathExtension.lowercased() == "wav" }
        let bytes = recordings.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        return RecordingStoreStats(fileCount: recordings.count, totalBytes: bytes)
    }

    /// Deletes every WAV in `directory`; returns how many were removed.
    @discardableResult
    static func deleteAll(in directory: URL) -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return 0
        }
        var removed = 0
        for url in items where url.pathExtension.lowercased() == "wav" {
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        if removed > 0 {
            logger.info("RecordingStore: deleted \(removed) recording(s)")
        }
        return removed
    }

    /// Reveals the recordings folder in Finder (creating it if needed).
    static func openInFinder(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

private extension URL {
    var modificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}