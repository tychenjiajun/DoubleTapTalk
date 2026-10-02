import XCTest
import AVFoundation
@testable import DoubleTapTalk

/// Tests for the WAV header builder and the on-disk recording writer.
final class WAVHeaderTests: XCTestCase {

    func testHeaderIsCanonical44Bytes() {
        let header = WAVHeader.make(dataSize: 3200, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        XCTAssertEqual(header.count, 44)

        XCTAssertEqual(String(bytes: header[0..<4], encoding: .utf8), "RIFF")
        XCTAssertEqual(String(bytes: header[8..<12], encoding: .utf8), "WAVE")
        XCTAssertEqual(String(bytes: header[12..<16], encoding: .utf8), "fmt ")
        XCTAssertEqual(String(bytes: header[36..<40], encoding: .utf8), "data")
    }

    func testHeaderSizesAreLittleEndian() {
        let header = WAVHeader.make(dataSize: 3200, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        let bytes = [UInt8](header)

        func u16(_ o: Int) -> UInt16 { UInt16(bytes[o]) | (UInt16(bytes[o + 1]) << 8) }
        func u32(_ o: Int) -> UInt32 {
            UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8) | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
        }

        // RIFF chunk size = 36 + dataSize
        XCTAssertEqual(u32(4), 36 + 3200)

        // fmt: PCM(1), channels(1), sampleRate(16000), byteRate(32000), blockAlign(2), bits(16)
        XCTAssertEqual(u16(20), 1)
        XCTAssertEqual(u16(22), 1)
        XCTAssertEqual(u32(24), 16000)
        XCTAssertEqual(u32(28), 32000)
        XCTAssertEqual(u16(32), 2)
        XCTAssertEqual(u16(34), 16)

        // data chunk size
        XCTAssertEqual(u32(40), 3200)
    }
}

final class RecordingFileWriterTests: XCTestCase {

    private func u32(_ bytes: [UInt8], _ o: Int) -> UInt32 {
        UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8) | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
    }

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFloatBuffer(frames: Int, sampleFunc: (Int) -> Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]
        for i in 0..<frames {
            samples[i] = Float(sampleFunc(i))
        }
        return buffer
    }

    func testWriterProducesValidWAV() throws {
        guard let writer = RecordingFileWriter(directory: tempDir) else {
            return XCTFail("writer init failed")
        }
        try writer.open()

        let frames = 1600
        let sine: (Int) -> Double = { sin(Double($0) / 100.0) * 0.5 }
        let buffer = makeFloatBuffer(frames: frames, sampleFunc: sine)
        writer.append(buffer)

        let url = writer.finish()
        XCTAssertNotNil(url)

        let data = try Data(contentsOf: url!)
        XCTAssertEqual(data.count, 44 + frames * 2)

        // Header sizes must match the appended payload.
        let bytes = [UInt8](data)
        let riffSize = u32(bytes, 4)
        let dataSize = u32(bytes, 40)
        XCTAssertEqual(riffSize, UInt32(36 + frames * 2))
        XCTAssertEqual(dataSize, UInt32(frames * 2))

        // Round-trip: decoded Int16 samples must equal the writer's conversion
        // of the stored Float32 samples exactly.
        let pcm = data.subdata(in: 44..<data.count)
        let source = buffer.floatChannelData![0]
        let maxVal = Double(Int16.max)
        for i in 0..<frames {
            let raw = UInt16(pcm[2 * i]) | (UInt16(pcm[2 * i + 1]) << 8)
            let decoded = Int16(bitPattern: raw)
            let expected = Int16((Double(source[i]) * maxVal).rounded())
            XCTAssertEqual(decoded, expected, "sample \(i) mismatch")
        }

        // AVAudioFile must be able to open it (valid container).
        XCTAssertNoThrow(try AVAudioFile(forReading: url!))
    }

    func testMultipleAppendsConcatenate() throws {
        guard let writer = RecordingFileWriter(directory: tempDir) else {
            return XCTFail("writer init failed")
        }
        try writer.open()
        writer.append(makeFloatBuffer(frames: 100, sampleFunc: { _ in 0.25 }))
        writer.append(makeFloatBuffer(frames: 200, sampleFunc: { _ in -0.25 }))
        let url = writer.finish()
        XCTAssertNotNil(url)
        let data = try Data(contentsOf: url!)
        XCTAssertEqual(data.count, 44 + 300 * 2)
    }

    func testFinishDeletesEmptyRecording() throws {
        guard let writer = RecordingFileWriter(directory: tempDir) else {
            return XCTFail("writer init failed")
        }
        try writer.open()
        let url = writer.finish()
        XCTAssertNil(url, "empty recording must be deleted and yield nil")
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.fileURL.path))
    }

    func testCancelRemovesFile() throws {
        guard let writer = RecordingFileWriter(directory: tempDir) else {
            return XCTFail("writer init failed")
        }
        try writer.open()
        writer.append(makeFloatBuffer(frames: 100, sampleFunc: { _ in 0.1 }))
        writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.fileURL.path))
        XCTAssertNil(writer.finish(), "finish after cancel must return nil")
    }

    func testPruneKeepsMostRecent() throws {
        // Create 3 dated files, keep 2.
        for i in 0..<3 {
            let stamp = String(format: "20250101_00000%d", i) // 0,1,2 lexicographic
            let path = tempDir.appendingPathComponent("Recording_\(stamp).wav")
            try Data(count: 100 + i).write(to: path)
            // make modification dates differ (0 oldest ... 2 newest)
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path.path)
        }

        // The writer's new file is created now (newest), so pruning keeps the
        // two most recent of the 3 planted files.
        guard let writer = RecordingFileWriter(directory: tempDir, keepRecords: 2) else {
            return XCTFail("writer init failed")
        }
        try writer.open()
        writer.append(makeFloatBuffer(frames: 100, sampleFunc: { _ in 0 }))
        _ = writer.finish()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { $0.hasSuffix(".wav") }
        XCTAssertEqual(remaining.count, 2)
        XCTAssertFalse(remaining.contains("Recording_20250101_000000.wav"), "oldest recording must be pruned")
    }

    // MARK: - Settings-panel storage management (RecordingStore)

    func testStoreStatsCountsWavFilesAndBytes() throws {
        try Data(count: 1_000).write(to: tempDir.appendingPathComponent("Recording_a.wav"))
        try Data(count: 500).write(to: tempDir.appendingPathComponent("Recording_b.wav"))
        try Data(count: 42).write(to: tempDir.appendingPathComponent("notes.txt"))  // ignored

        let stats = RecordingStore.stats(in: tempDir)
        XCTAssertEqual(stats.fileCount, 2)
        XCTAssertEqual(stats.totalBytes, 1_500)
        XCTAssertFalse(stats.formattedSize.isEmpty)
    }

    func testStoreStatsOnMissingDirectoryIsEmpty() {
        let missing = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertEqual(RecordingStore.stats(in: missing), .empty)
    }

    func testStoreDeleteAllRemovesOnlyRecordings() throws {
        try Data(count: 10).write(to: tempDir.appendingPathComponent("Recording_a.wav"))
        try Data(count: 10).write(to: tempDir.appendingPathComponent("Recording_b.wav"))
        try Data(count: 10).write(to: tempDir.appendingPathComponent("keep.txt"))

        let removed = RecordingStore.deleteAll(in: tempDir)
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(RecordingStore.stats(in: tempDir), .empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("keep.txt").path))
    }

    func testStoreDeleteAllOnMissingDirectoryIsNoop() {
        let missing = tempDir.appendingPathComponent("nope", isDirectory: true)
        XCTAssertEqual(RecordingStore.deleteAll(in: missing), 0)
    }

    func testStoreFormattedSizeIsHumanReadable() {
        XCTAssertTrue(RecordingStoreStats(fileCount: 0, totalBytes: 0).formattedSize.contains("KB"))
        XCTAssertTrue(RecordingStoreStats(fileCount: 1, totalBytes: 5_000_000).formattedSize.contains("MB"))
    }

    func testWritesAreFlushedBeforeFinish() throws {
        // Appends are async; finish() must still see every byte.
        guard let writer = RecordingFileWriter(directory: tempDir) else {
            return XCTFail("writer init failed")
        }
        try writer.open()
        for _ in 0..<20 {
            writer.append(makeFloatBuffer(frames: 50, sampleFunc: { _ in 0.5 }))
        }
        guard let url = writer.finish() else { return XCTFail("finish returned nil") }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 20 * 50 * 2, "all queued appends must be flushed by finish()")
    }
}