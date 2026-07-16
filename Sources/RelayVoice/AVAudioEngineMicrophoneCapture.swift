@preconcurrency import AVFoundation
import Foundation

public struct RelayMicrophoneConfiguration: Equatable, Sendable {
    public let sampleRate: UInt32
    public let numChannels: UInt16
    public let bufferSize: UInt32

    public init(
        sampleRate: UInt32 = 24_000,
        numChannels: UInt16 = 1,
        bufferSize: UInt32 = 1_024
    ) {
        self.sampleRate = sampleRate
        self.numChannels = numChannels
        self.bufferSize = bufferSize
    }
}

enum RelayMicrophoneAuthorization: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

protocol RelayAudioTapProcessing: Sendable {
    func process(_ buffer: AVAudioPCMBuffer)
}

public enum RelayMicrophoneCaptureError:
    Error,
    Equatable,
    Sendable
{
    case alreadyCapturing
    case invalidConfiguration
    case inputUnavailable
    case converterUnavailable
    case permissionDenied
    case permissionRestricted
}

extension RelayMicrophoneCaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            "Relay is already capturing microphone audio."
        case .invalidConfiguration:
            "Relay’s microphone audio configuration is invalid."
        case .inputUnavailable:
            "Relay could not read a valid microphone input format."
        case .converterUnavailable:
            "Relay could not create its PCM16 microphone converter."
        case .permissionDenied:
            "Microphone access is denied. Allow Relay in System Settings → Privacy & Security → Microphone."
        case .permissionRestricted:
            "Microphone access is restricted on this Mac."
        }
    }
}

@MainActor
public final class AVAudioEngineMicrophoneCapture:
    RelayMicrophoneCapturing
{
    private let configuration: RelayMicrophoneConfiguration
    private let authorizationStatusProvider:
        @MainActor () -> RelayMicrophoneAuthorization
    private let engineFactory: @MainActor () -> AVAudioEngine

    private var engine: AVAudioEngine?
    private var continuation:
        AsyncStream<RelayAudioChunk>.Continuation?

    public convenience init(
        configuration: RelayMicrophoneConfiguration = .init()
    ) {
        self.init(
            configuration: configuration,
            authorizationStatusProvider: {
                Self.currentAuthorization()
            },
            engineFactory: { AVAudioEngine() }
        )
    }

    init(
        configuration: RelayMicrophoneConfiguration = .init(),
        authorizationStatusProvider:
            @escaping @MainActor () -> RelayMicrophoneAuthorization,
        engineFactory: @escaping @MainActor () -> AVAudioEngine
    ) {
        self.configuration = configuration
        self.authorizationStatusProvider =
            authorizationStatusProvider
        self.engineFactory = engineFactory
    }

    public func start() throws -> AsyncStream<RelayAudioChunk> {
        guard engine == nil else {
            throw RelayMicrophoneCaptureError.alreadyCapturing
        }
        switch authorizationStatusProvider() {
        case .denied:
            throw RelayMicrophoneCaptureError.permissionDenied
        case .restricted:
            throw RelayMicrophoneCaptureError.permissionRestricted
        case .authorized, .notDetermined:
            break
        }
        guard configuration.sampleRate > 0,
              configuration.numChannels > 0,
              configuration.bufferSize > 0,
              let outputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(configuration.sampleRate),
                  channels: AVAudioChannelCount(
                      configuration.numChannels
                  ),
                  interleaved: true
              ) else {
            throw RelayMicrophoneCaptureError.invalidConfiguration
        }

        // AVAudioEngine is deliberately created only here. Initialization
        // never touches the microphone or triggers a permission prompt.
        let engine = engineFactory()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0 else {
            throw RelayMicrophoneCaptureError.inputUnavailable
        }
        guard let converter = PCM16ChunkConverter(
            inputFormat: inputFormat,
            outputFormat: outputFormat
        ) else {
            throw RelayMicrophoneCaptureError.converterUnavailable
        }

        let pair = AsyncStream<RelayAudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        let continuation = pair.continuation
        let tapProcessor = PCM16AudioTapProcessor(
            converter: converter,
            continuation: continuation
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(configuration.bufferSize),
            format: inputFormat,
            block: Self.makeAudioTapBlock(
                processor: tapProcessor
            )
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.reset()
            continuation.finish()
            throw error
        }

        self.engine = engine
        self.continuation = continuation
        return pair.stream
    }

    nonisolated static func makeAudioTapBlock(
        processor: any RelayAudioTapProcessing
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            processor.process(buffer)
        }
    }

    private static func currentAuthorization()
        -> RelayMicrophoneAuthorization
    {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .notDetermined
        case .granted:
            return .authorized
        case .denied:
            let captureStatus =
                AVCaptureDevice.authorizationStatus(for: .audio)
            return captureStatus == .restricted
                ? .restricted
                : .denied
        @unknown default:
            return .restricted
        }
    }

    public func stop() {
        guard let engine else { return }

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        self.engine = nil
        continuation?.finish()
        continuation = nil
    }

    isolated deinit {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()
        }
        continuation?.finish()
    }
}

private final class PCM16AudioTapProcessor:
    RelayAudioTapProcessing,
    @unchecked Sendable
{
    private let converter: PCM16ChunkConverter
    private let continuation:
        AsyncStream<RelayAudioChunk>.Continuation

    init(
        converter: PCM16ChunkConverter,
        continuation: AsyncStream<RelayAudioChunk>.Continuation
    ) {
        self.converter = converter
        self.continuation = continuation
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let chunk = converter.convert(buffer) else {
            return
        }
        continuation.yield(chunk)
    }
}

private final class PCM16ChunkConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()

    init?(
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat
    ) {
        guard let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else {
            return nil
        }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ inputBuffer: AVAudioPCMBuffer) -> RelayAudioChunk? {
        lock.lock()
        defer { lock.unlock() }

        let sampleRateRatio =
            outputFormat.sampleRate / inputBuffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(
            (
                Double(inputBuffer.frameLength) * sampleRateRatio
            ).rounded(.up) + 32
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }

        let inputProvider = ConverterInputProvider(
            buffer: inputBuffer
        )
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }

        guard status != .error,
              conversionError == nil,
              outputBuffer.frameLength > 0,
              let bytes = outputBuffer.audioBufferList
                  .pointee.mBuffers.mData else {
            return nil
        }

        let bytesPerFrame = Int(
            outputFormat.streamDescription.pointee.mBytesPerFrame
        )
        let byteCount = Int(outputBuffer.frameLength) * bytesPerFrame
        guard byteCount > 0 else { return nil }

        return RelayAudioChunk(
            pcmData: Data(bytes: bytes, count: byteCount),
            sampleRate: UInt32(outputFormat.sampleRate),
            numChannels: UInt16(outputFormat.channelCount),
            samplesPerChannel: UInt32(outputBuffer.frameLength)
        )
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var didProvideBuffer = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !didProvideBuffer else {
            status.pointee = .noDataNow
            return nil
        }
        didProvideBuffer = true
        status.pointee = .haveData
        return buffer
    }
}
