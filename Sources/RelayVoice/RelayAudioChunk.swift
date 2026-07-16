import Foundation

public struct RelayAudioChunk: Codable, Equatable, Sendable {
    public let data: String
    public let sampleRate: UInt32
    public let numChannels: UInt16
    public let samplesPerChannel: UInt32?

    public init(
        data: String,
        sampleRate: UInt32,
        numChannels: UInt16,
        samplesPerChannel: UInt32? = nil
    ) {
        self.data = data
        self.sampleRate = sampleRate
        self.numChannels = numChannels
        self.samplesPerChannel = samplesPerChannel
    }

    public init(
        pcmData: Data,
        sampleRate: UInt32,
        numChannels: UInt16,
        samplesPerChannel: UInt32? = nil
    ) {
        self.init(
            data: pcmData.base64EncodedString(),
            sampleRate: sampleRate,
            numChannels: numChannels,
            samplesPerChannel: samplesPerChannel
        )
    }
}
