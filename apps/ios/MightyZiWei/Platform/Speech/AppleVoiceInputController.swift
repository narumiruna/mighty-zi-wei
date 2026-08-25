import AVFAudio
import CoreMedia
import Foundation
import Speech

@MainActor
final class AppleVoiceInputController: VoiceInputControlling {
    enum VoiceInputError: LocalizedError {
        case speechPermissionDenied
        case speechPermissionRestricted
        case microphonePermissionDenied
        case unsupportedLocale
        case unavailableAudioFormat
        case microphoneUnavailable
        case assetPreparationFailed

        var errorDescription: String? {
            switch self {
            case .speechPermissionDenied:
                "語音辨識權限已關閉，請到 iPhone「設定」允許存取，或繼續使用鍵盤。"
            case .speechPermissionRestricted:
                "這台 iPhone 目前限制使用語音辨識，仍可繼續使用鍵盤。"
            case .microphonePermissionDenied:
                "麥克風權限已關閉，請到 iPhone「設定」允許存取，或繼續使用鍵盤。"
            case .unsupportedLocale:
                "這台 iPhone 目前不支援正體中文語音辨識，仍可繼續使用鍵盤。"
            case .unavailableAudioFormat:
                "目前無法準備語音辨識格式，請稍後再試。"
            case .microphoneUnavailable:
                "目前找不到可用的麥克風，請檢查音訊裝置後再試。"
            case .assetPreparationFailed:
                "正體中文語音資產無法準備，請確認網路與儲存空間後再試。"
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var eventHandler: (@MainActor @Sendable (VoiceInputEvent) -> Void)?
    private var hasInstalledTap = false

    func start(
        eventHandler: @escaping @MainActor @Sendable (VoiceInputEvent) -> Void
    ) async throws {
        await cancel()
        try Task.checkCancellation()
        self.eventHandler = eventHandler

        try await authorizeSpeechRecognition()
        try Task.checkCancellation()
        try await authorizeMicrophone()
        try Task.checkCancellation()

        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "zh-TW")
        ) else {
            throw VoiceInputError.unsupportedLocale
        }
        try Task.checkCancellation()

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveShortDictation
        )
        do {
            if let installationRequest = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                try await installationRequest.downloadAndInstall()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceInputError.assetPreparationFailed
        }
        try Task.checkCancellation()

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw VoiceInputError.unavailableAudioFormat
        }
        try Task.checkCancellation()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try Task.checkCancellation()

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw VoiceInputError.microphoneUnavailable
        }
        guard let bufferConverter = VoiceAudioBufferConverter(
            inputFormat: hardwareFormat,
            outputFormat: analyzerFormat
        ) else {
            throw VoiceInputError.unavailableAudioFormat
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetoothHFP]
        )
        try audioSession.setActive(true)

        let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: hardwareFormat
        ) { [weak self] buffer, _ in
            do {
                let convertedBuffer = try bufferConverter.convert(buffer)
                continuation.yield(AnalyzerInput(buffer: convertedBuffer))
            } catch {
                continuation.finish()
                Task { @MainActor [weak self] in
                    self?.eventHandler?(
                        .interrupted(message: "麥克風音訊格式無法轉換，已保留目前文字。")
                    )
                }
            }
        }
        hasInstalledTap = true

        self.audioEngine = audioEngine
        self.analyzer = analyzer
        self.inputContinuation = continuation

        resultTask = Task { [weak self] in
            var transcript = VoiceTranscriptAccumulator()
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    let text = transcript.update(
                        text: String(result.text.characters),
                        range: result.range,
                        isFinal: result.isFinal
                    )
                    self?.eventHandler?(
                        .transcription(text: text, isFinal: result.isFinal)
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                self?.eventHandler?(
                    .interrupted(message: "語音辨識已中斷，已保留目前文字。")
                )
            }
        }

        analysisTask = Task { [weak self] in
            do {
                _ = try await analyzer.analyzeSequence(inputSequence)
            } catch is CancellationError {
                return
            } catch {
                self?.eventHandler?(
                    .interrupted(message: "語音辨識已中斷，已保留目前文字。")
                )
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            await cancel()
            throw error
        }
    }

    func finish() async {
        stopCapture()
        _ = await analysisTask?.result
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            eventHandler?(.interrupted(message: "語音辨識未能完整結束，已保留目前文字。"))
        }
        _ = await resultTask?.result
        deactivateAudioSession()
        clearSessionReferences()
    }

    func cancel() async {
        stopCapture()
        await analyzer?.cancelAndFinishNow()
        analysisTask?.cancel()
        resultTask?.cancel()
        _ = await analysisTask?.result
        _ = await resultTask?.result
        deactivateAudioSession()
        clearSessionReferences()
    }

    private func authorizeSpeechRecognition() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .authorized:
            return
        case .denied:
            throw VoiceInputError.speechPermissionDenied
        case .restricted:
            throw VoiceInputError.speechPermissionRestricted
        case .notDetermined:
            throw VoiceInputError.speechPermissionDenied
        @unknown default:
            throw VoiceInputError.speechPermissionRestricted
        }
    }

    private func authorizeMicrophone() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            throw VoiceInputError.microphonePermissionDenied
        }
    }

    private func stopCapture() {
        if hasInstalledTap, let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        audioEngine?.stop()
        inputContinuation?.finish()
        inputContinuation = nil
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    private func clearSessionReferences() {
        analysisTask = nil
        resultTask = nil
        analyzer = nil
        audioEngine = nil
        eventHandler = nil
    }
}

struct VoiceTranscriptAccumulator: Equatable, Sendable {
    private struct Segment: Equatable, Sendable {
        let start: Double
        let end: Double
        let text: String
        let isFinal: Bool
    }

    private var segments: [Segment] = []

    mutating func update(text: String, range: CMTimeRange, isFinal: Bool) -> String {
        let rawStart = range.start.seconds
        let rawDuration = range.duration.seconds
        let start = rawStart.isFinite ? max(0, rawStart) : 0
        let duration = rawDuration.isFinite ? max(0, rawDuration) : 0
        let end = start + duration
        let newSegment = Segment(start: start, end: end, text: text, isFinal: isFinal)
        let conflictsWithFinalSegment = segments.contains { oldSegment in
            oldSegment.isFinal && Self.overlaps(oldSegment, newSegment)
        }
        if !isFinal, conflictsWithFinalSegment {
            return segments.sorted { $0.start < $1.start }.map(\.text).joined()
        }

        segments.removeAll { oldSegment in
            Self.overlaps(oldSegment, newSegment)
        }
        segments.append(newSegment)
        segments.sort { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.isFinal && !rhs.isFinal
            }
            return lhs.start < rhs.start
        }
        return segments.map(\.text).joined()
    }

    private static func overlaps(_ lhs: Segment, _ rhs: Segment) -> Bool {
        let hasSameStart = abs(lhs.start - rhs.start) < 0.001
        let rangesOverlap = lhs.start < rhs.end && rhs.start < lhs.end
        return hasSameStart || rangesOverlap
    }
}

// AVAudioEngine 會依序呼叫同一個 tap，converter 不會被多個執行緒同時使用。
private final class VoiceAudioBufferConverter: @unchecked Sendable {
    enum ConversionError: Error {
        case cannotCreateBuffer
        case conversionFailed
    }

    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(
                from: inputFormat,
                to: outputFormat
            ) else {
                return nil
            }
            self.converter = converter
        }
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter else { return inputBuffer }
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, ceil(Double(inputBuffer.frameLength) * ratio))
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw ConversionError.cannotCreateBuffer
        }

        var conversionError: NSError?
        let inputProvider = VoiceAudioConversionInput(buffer: inputBuffer)
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }
        guard conversionError == nil,
              status != .error,
              outputBuffer.frameLength > 0
        else {
            throw conversionError ?? ConversionError.conversionFailed
        }
        return outputBuffer
    }
}

// AVAudioConverter 在單次同步轉換期間依序要求 input buffer。
private final class VoiceAudioConversionInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var hasSuppliedBuffer = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        guard !hasSuppliedBuffer else {
            status.pointee = .noDataNow
            return nil
        }
        hasSuppliedBuffer = true
        status.pointee = .haveData
        return buffer
    }
}
