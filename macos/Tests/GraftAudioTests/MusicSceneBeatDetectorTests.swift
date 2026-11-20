import Foundation
import Testing
@testable import GraftAudio

@Suite("Music Scene beat tracking")
struct MusicSceneBeatDetectorTests {
    private let rate = 44_100.0

    @Test("Locks to percussion across hardware buffer boundaries", arguments: [70.0, 101.0, 128.0, 174.0])
    func percussionGrid(bpm: Double) throws {
        let interval = 60 / bpm
        var detector = MusicSceneBeatDetector()
        let hits = render(&detector, seconds: 0.25 + 9.8 * interval, beat: interval, missing: [7])
        #expect(abs(try #require(detector.tempo) - bpm) < 2)
        #expect(hits.count == 10)
        for (index, hit) in hits.enumerated() {
            #expect(abs(hit.time - (0.25 + Double(index) * interval)) < 0.035)
        }
        #expect(try #require(hits.first(where: { abs($0.time - (0.25 + 7 * interval)) < 0.035 })).strength < 0.7)
    }

    @Test("A rest is silent and a seek releases the old tempo")
    func quietAndSeek() throws {
        var detector = MusicSceneBeatDetector()
        let initial = render(&detector, seconds: 5.15, beat: 0.5)
        #expect(initial.count == 10)
        #expect(abs(try #require(detector.tempo) - 120) < 2)
        let rest = render(&detector, seconds: 2.5, beat: nil)
        #expect(rest.isEmpty)
        #expect(detector.tempo == nil)
        detector.reset()
        #expect(detector.tempo == nil)
        let restarted = render(&detector, seconds: 6.0, beat: 0.75)
        #expect(abs(try #require(restarted.first).time - 0.25) < 0.035)
        #expect(abs(try #require(detector.tempo) - 80) < 2)
    }

    private func render(_ detector: inout MusicSceneBeatDetector, seconds: Double, beat: Double?,
                        missing: Set<Int> = []) -> [(time: Double, strength: Double)] {
        var result: [(Double, Double)] = []
        let total = Int(seconds * rate)
        var frame = 0
        var pcm = [Float](repeating: 0, count: 2 * 769)
        while frame < total {
            let count = min(769, total - frame)
            for index in 0..<count {
                let t = Double(frame + index) / rate
                var sample: Double = 0
                if let beat {
                    sample = 0.003 * sin(2 * .pi * 330 * t)
                    if t >= 0.25 {
                        let tick = Int((t - 0.25) / beat)
                        let age = t - 0.25 - Double(tick) * beat
                        if !missing.contains(tick) {
                            sample += 0.035 * exp(-age / 0.034) * sin(2 * .pi * 74 * age)
                        }
                    }
                }
                // Antiphase stereo exercises the two-lane power measurement.
                pcm[index * 2] = Float(sample)
                pcm[index * 2 + 1] = -Float(sample)
            }
            let hit = pcm.withUnsafeBufferPointer { buffer in
                detector.consume(left: buffer.baseAddress!, leftStride: 2, right: buffer.baseAddress! + 1,
                                 rightStride: 2, frames: count, rate: rate)
            }
            frame += count
            if let hit { result.append((Double(frame) / rate - hit.age, hit.strength)) }
        }
        return result
    }
}
