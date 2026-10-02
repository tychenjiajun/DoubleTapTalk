import Foundation
import Speech
import AVFoundation

private let logger = FileLogger.shared

/// Tracks "no new words" idle silence for one dictation segment (pure, testable).
/// The idle deadline resets ONLY when the recognizer's best text actually
/// changes — repeated identical partial updates (which SFSpeechRecognizer emits
/// constantly while streaming) never extend the segment.
struct RelaySegmentActivity {
    private var lastChange = Date()
    private var _hasHeardText = false
    private var lastObservedText = ""

    /// Call with the recognizer's current best text. Returns true when the text
    /// is new (a new word arrived → idle deadline resets).
    mutating func observe(text: String) -> Bool {
        guard text != lastObservedText else { return false }
        lastObservedText = text
        lastChange = Date()
        _hasHeardText = true
        return true
    }

    var hasHeardText: Bool { _hasHeardText }

    /// True when enough silence has passed since the last new word.
    func shouldRotate(now: Date, threshold: TimeInterval) -> Bool {
        guard _hasHeardText else { return false }
        return now.timeIntervalSince(lastChange) >= threshold
    }
}

/// Converts arbitrary tap buffers to Float32 16 kHz mono — the format
/// SFSpeechRecognizer needs on macOS. Mirrors AppleSpeechBackend's converter.
private struct Mono16kConverter {
    private let converter: AVAudioConverter
    let targetFormat: AVAudioFormat

    init?(from inputFormat: AVAudioFormat) {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target) else { return nil }
        self.converter = converter
        self.targetFormat = target
    }

    /// Returns the input buffer itself when already 16 kHz mono, otherwise a
    /// converted copy (or nil on failure/silence).
    func buffer(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if abs(input.format.sampleRate - 16000) < 0.5 && input.format.channelCount == 1 {
            return input
        }
        let outCapacity = AVAudioFrameCount(Double(input.frameLength) / input.format.sampleRate * targetFormat.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }
        var delivered = false
        let status = converter.convert(to: out, error: nil) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return input
        }
        guard out.frameLength > 0, status == .haveData || status == .inputRanDry else { return nil }
        return out
    }
}

/// Continuous "relay" dictation: one double-tap-Control session keeps the
/// microphone open across many short recognition segments. When Apple produces
/// no new words for `idleThreshold` seconds, the current segment is finalized
/// (its audio file is saved and its transcript delivered via
/// `onSegmentTranscript`) and a fresh segment starts immediately — the
/// engine/tap never stops, so no speech is lost if the user resumes talking
/// right at the boundary. The session ends when the user taps Control once.
///
/// Delivery order is guaranteed: rotated segments are emitted strictly in
/// segment order, each emission completes before the next, and `stop()` waits
/// for all pending emissions before returning — so the caller can enqueue the
/// final segment afterwards and know it lands last. Delivering segment results
/// (cloud ASR + injection) is the caller's job (AppDelegate), without
/// disturbing the ongoing live segment.
final class ContinuousDictationSession {
    struct SegmentTranscript {
        let text: String
        let recordingFileURL: URL?
    }

    var onLiveText: ((String) -> Void)?
    var onFinalText: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?
    /// Delivered in segment order when a rotated segment ends. Each call is
    /// awaited before the next emission and before `stop()` returns, so the
    /// caller can enqueue work without racing later segments.
    var onSegmentTranscript: ((SegmentTranscript) async -> Void)?

    let idleThreshold: TimeInterval

    private let audioEngine = AVAudioEngine()
    private var monoConverter: Mono16kConverter?
    private let lock = NSLock()          // guards currentSegment + emissionChain
    private var currentSegment: Segment?
    /// Serializes rotated-segment delivery; appended under `lock`, awaited
    /// without it (never call back into the session while holding the lock).
    private var emissionChain: Task<Void, Never>?

    private var idleTask: Task<Void, Never>?
    private let idleCheckInterval: TimeInterval = 0.5

    init(idleThreshold: TimeInterval) {
        self.idleThreshold = idleThreshold
    }

    // MARK: - One recognition segment

    private final class Segment {
        let recognizer: SFSpeechRecognizer
        let request: SFSpeechAudioBufferRecognitionRequest
        var task: SFSpeechRecognitionTask?
        let recorder: RecordingFileWriter?
        /// Mutated only on the recognizer's callback queue; read after the task
        /// has finished (same convention as AppleSpeechBackend).
        var transcript = RecognitionTranscript()

        private let activityLock = NSLock()
        private var activity = RelaySegmentActivity()

        init(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest, recorder: RecordingFileWriter?) {
            self.recognizer = recognizer
            self.request = request
            self.recorder = recorder
        }

        func observeBestText(_ text: String) {
            activityLock.lock(); defer { activityLock.unlock() }
            _ = activity.observe(text: text)
        }

        func shouldRotate(now: Date, threshold: TimeInterval) -> Bool {
            activityLock.lock(); defer { activityLock.unlock() }
            return activity.shouldRotate(now: now, threshold: threshold)
        }

        func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, session: ContinuousDictationSession) {
            if let error = error {
                let ns = error as NSError
                logger.warning("Relay recognition error: \(error.localizedDescription) (domain=\(ns.domain) code=\(ns.code))")
                if result == nil {
                    session.onError?(error.localizedDescription)
                }
                return
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            transcript.apply(transcript: text, isFinal: isFinal)
            observeBestText(transcript.currentText)
            if isFinal {
                session.onFinalText?(text)
            } else {
                session.onLiveText?(text)
            }
        }
    }

    // MARK: - Lifecycle

    func start(language code: String?, inputMethodLanguage: String?) throws {
        guard let pair = SpeechRecognizerFactory.make(locale: code, inputMethodLanguage: inputMethodLanguage) else {
            let message = "Speech recognition is not supported for \(SpeechLocaleMapper.locale(for: code, inputMethodLanguage: inputMethodLanguage).identifier). Download the language in System Settings > Keyboard > Dictation."
            throw PipelineError.transcriptionFailed(message)
        }
        segmentLocale = pair.locale

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let mono = Mono16kConverter(from: inputFormat) else {
            throw PipelineError.audioFileError
        }
        self.monoConverter = mono

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.onAudioLevel?(AudioLevel.rms(of: buffer))
            if let mono = self.monoConverter?.buffer(buffer) {
                self.appendToActive(mono)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            logger.error("Relay: failed to start audio engine: \(error)")
            throw error
        }

        guard let first = makeSegment() else {
            // Roll back: never leave the engine running without a segment.
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            let message = "Relay: cannot create a recognition segment for \(segmentLocale?.identifier ?? "unknown")"
            logger.error(message)
            throw PipelineError.transcriptionFailed(message)
        }
        setActiveSegment(first)
        startIdleWatch()
        logger.info("Relay dictation started (idle threshold \(idleThreshold)s)")
    }

    private var segmentLocale: Locale?
    /// Set by `stop()` under `lock`; blocks further rotation so a stop can
    /// never race a segment swap (the stop would otherwise observe nil and
    /// drop the final transcript).
    private var stopped = false

    /// Atomically ends the session state: marks stopped, claims the live
    /// segment and snapshots the emission chain. Sync helper so `stop()` never
    /// touches NSLock from an async context.
    private func claimForStop() -> (segment: Segment?, pendingEmissions: Task<Void, Never>?) {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        let segment = currentSegment
        currentSegment = nil
        return (segment, emissionChain)
    }

    /// Stops the whole dictation session, returning the final segment's result.
    /// All rotated segments are delivered (in order) BEFORE this returns, so
    /// the caller can enqueue the final segment and know it lands last.
    func stop() async -> SegmentTranscript {
        logger.info("Relay: stopping dictation")
        idleTask?.cancel()
        idleTask = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        let claim = claimForStop()

        // Wait for every in-flight rotation to finalize + deliver first —
        // guarantees the caller's final segment is enqueued after them.
        await claim.pendingEmissions?.value

        guard let segment = claim.segment else {
            return SegmentTranscript(text: "", recordingFileURL: nil)
        }
        return await finalizeSegment(segment)
    }

    // MARK: - Segment rotation

    /// Builds a fresh segment (recognizer + request + recorder) WITHOUT
    /// installing it — the caller swaps it in atomically under `lock`.
    private func makeSegment() -> Segment? {
        guard let locale = segmentLocale else { return nil }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            logger.error("Relay: cannot create recognizer for \(locale.identifier)")
            return nil
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        // Record only when cloud transcription is on: the WAV exists purely to
        // be uploaded, so with ASR disabled no audio ever touches disk.
        var recorder: RecordingFileWriter?
        if ASRSettings.current().enabled,
           let writer = RecordingFileWriter(directory: RecordingFileWriter.defaultDirectory()) {
            do {
                try writer.open()
                recorder = writer
            } catch {
                logger.warning("Relay: could not open recording file: \(error)")
            }
        }

        let segment = Segment(recognizer: recognizer, request: request, recorder: recorder)
        segment.task = recognizer.recognitionTask(with: request) { [weak self, weak segment] result, error in
            guard let self, let segment else { return }
            segment.handleRecognition(result: result, error: error, session: self)
        }
        return segment
    }

    private func startIdleWatch() {
        idleTask?.cancel()
        let interval = idleCheckInterval
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await MainActor.run { self.checkIdle() }
            }
        }
    }

    private func checkIdle() {
        guard let segment = activeSegment() else { return }
        if segment.shouldRotate(now: Date(), threshold: idleThreshold) {
            rotate(segment)
        }
    }

    private func rotate(_ old: Segment) {
        // Build the replacement while `old` is still active (no nil window →
        // no dropped audio), then swap + chain the old segment's delivery in
        // ONE lock section so stop() can never interleave and observe nil.
        guard let new = makeSegment() else {
            onError?("Failed to start a new recognition segment")
            // Deliver what we heard, then end the session.
            lock.lock()
            if !stopped, currentSegment === old {
                currentSegment = nil
                chainEmission(of: old)
            }
            lock.unlock()
            Task { [weak self] in _ = await self?.stop() }
            return
        }

        lock.lock()
        guard !stopped, currentSegment === old else {
            // stop() won the race (or another rotation did) — discard `new`.
            lock.unlock()
            new.task?.finish()
            new.request.endAudio()
            new.recorder?.cancel()
            return
        }
        logger.info("Relay: no new words for \(idleThreshold)s — rotating segment")
        currentSegment = new
        chainEmission(of: old)
        lock.unlock()
    }

    /// Appends finalize+deliver of `segment` to the emission chain (strictly
    /// ordered). Caller must hold `lock`.
    private func chainEmission(of segment: Segment) {
        let previous = emissionChain
        emissionChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let transcript = await self.finalizeSegment(segment)
            await self.onSegmentTranscript?(transcript)
        }
    }

    /// Ends one segment's recognition + recording and returns its result.
    /// The engine keeps running — the tap feeds the (already swapped-in) new
    /// segment while Apple finishes the old one.
    private func finalizeSegment(_ segment: Segment) async -> SegmentTranscript {
        segment.task?.finish()
        segment.request.endAudio()
        try? await Task.sleep(nanoseconds: 700_000_000)
        segment.task = nil

        let text = segment.transcript.currentText
        // Skip segments Apple heard no words in: discard the recording so blank
        // audio is never kept or uploaded to cloud ASR.
        let hasWords = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let recordingURL: URL?
        if hasWords {
            recordingURL = segment.recorder?.finish()
        } else {
            segment.recorder?.cancel()
            recordingURL = nil
        }
        logger.info("Relay segment result: '\(text)' (recording: \(recordingURL?.path ?? "skipped — no words"))")
        return SegmentTranscript(text: text, recordingFileURL: recordingURL)
    }

    // MARK: - Tap → active segment

    private func appendToActive(_ buffer: AVAudioPCMBuffer) {
        guard let segment = activeSegment() else { return }
        segment.request.append(buffer)
        segment.recorder?.append(buffer)
    }

    private func activeSegment() -> Segment? {
        lock.lock(); defer { lock.unlock() }
        return currentSegment
    }

    private func setActiveSegment(_ segment: Segment?) {
        lock.lock(); defer { lock.unlock() }
        currentSegment = segment
    }
}