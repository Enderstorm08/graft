import AudioToolbox
import Testing
@testable import GraftAudio

@Suite("Music Scene audio envelope")
struct MusicSceneEnvelopeTests {
    @Test func anAttackAccentsTheLightAndAHeldNoteSettles() {
        let envelope = MusicSceneEnvelope()
        feed(0.006, blocks: 140, to: envelope)
        #expect(envelope.level > 0)
        #expect(envelope.pulse < 0.01)
        feed(0.08, blocks: 2, to: envelope)
        #expect(envelope.pulse > 0.6)
        feed(0.08, blocks: 160, to: envelope)
        #expect(envelope.level > 0.5)
        #expect(envelope.pulse < 0.01)
        envelope.reset()
        #expect(envelope.level == 0)
        #expect(envelope.pulse == 0)
    }

    @Test func noiseBelowTheFloorDoesNotFlash() {
        let envelope = MusicSceneEnvelope()
        feed(0, blocks: 100, to: envelope)
        feed(0.00015, blocks: 3, to: envelope)
        #expect(envelope.level == 0)
        #expect(envelope.pulse == 0)
    }

    private func feed(_ amplitude: Float, blocks: Int, to envelope: MusicSceneEnvelope) {
        var samples = [Float](repeating: amplitude, count: 480)
        samples.withUnsafeMutableBytes { bytes in
            var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress
            ))
            for _ in 0..<blocks { envelope.consume(&buffer, sampleRate: 48_000) }
        }
    }
}
