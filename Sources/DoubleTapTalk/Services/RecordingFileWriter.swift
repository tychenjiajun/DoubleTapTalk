import Foundation
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
/// patched in on `finish()`. Thread-safe: designed to be fed from the audio tap
/// callback while `finish()` is called from the recording session's end.
final class RecordingFileWriter {
    let fileURL: URL

    private let sampleRate: Int
    private let channels: Int
    private let bitsPerSample: Int
    private let keepRecords: Int

    private var handle: FileHandle?
    private var dataByteCount = 0
    private var closed = false
    private let lock = NSLock()

    /// The directory recordings live in: ~/Library/Application Support/DoubleTapTalk/Recordings
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DoubleTapTalk/Recordings", isDirectory: true)
    }

    /// Creates (but does not yet open) a writer for a brand-new timestamped
    /// file inside `directory`. Returns nil if the directory can't be created.
    init?(directory: URL, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16, keepRecords: Int = 20) {
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
        lock.lock()
        defer { lock.unlock() }
        guard handle == nil else { return }
        try Data().write(to: fileURL)
        let h = try FileHandle(forWritingTo: fileURL)
        try h.write(contentsOf: WAVHeader.make(dataSize: 0, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample))
        handle = h
    }

    /// Appends a Float32 non-interleaved mono buffer, downsampling to Int16.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.format.channelCount == 1,
              let data = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            logger.warning("RecordingFileWriter: skipping unsupported buffer format (expected Float32 mono)")
            return
        }

        lock.lock()
        defer { lock.unlock() }
        guard let handle = handle, !closed else { return }

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

        do {
            try handle.write(contentsOf: pcm)
            dataByteCount += pcm.count
        } catch {
            logger.error("RecordingFileWriter: write failed: \(error)")
        }
    }

    /// Patches the header sizes, closes the file, prunes old recordings and
    /// returns the file URL. Deletes the file (and returns nil) when nothing
    /// was actually recorded.
    func finish() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if closed { return nil }
        closed = true
        guard let handle = handle else { return nil }

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

    /// Deletes the in-progress file (used when recording start aborts).
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        if closed { return }
        closed = true
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Keeps only the most recent `keepRecords` WAV files in the recordings dir.
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

private extension URL {
    var modificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}