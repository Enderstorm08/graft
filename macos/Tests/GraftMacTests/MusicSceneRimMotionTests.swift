import Foundation
import SwiftUI
import Testing
@testable import GraftMac

@MainActor
struct MusicSceneRimMotionTests {
    @Test(arguments: [nil, CGRect(x: 610, y: 0, width: 180, height: 30)] as [CGRect?])
    func desktopRevealSpreadsFromBothSidesOfTheOrigin(_ notch: CGRect?) {
        let size = CGSize(width: 1440, height: 900)
        let midX = notch?.midX ?? size.width / 2
        let y = notch?.maxY ?? 0
        let outline = MusicSceneRim.perimeter(in: size, notch: notch)
        let first = MusicSceneRim.revealedStroke(outline, progress: 0.02).boundingRect
        let second = MusicSceneRim.revealedStroke(outline, progress: 0.03).boundingRect

        #expect(first.minX < midX && first.maxX > midX)
        #expect(abs(first.midX - midX) < 0.5)
        #expect(first.minY == y && first.maxY == y)
        #expect(second.minX < first.minX && second.maxX > first.maxX)
        #expect(MusicSceneRim.revealedStroke(outline, progress: 1) == outline)
    }

    @Test(arguments: [72.0, 120.0, 176.0])
    func steadyTempoAdvancesOneCycleInSixteenBeats(_ tempo: Double) {
        var motion = MusicSceneRimMotion()
        var previous = motion.sample(at: 0, tempo: tempo, moving: true)
        var distance = 0.0
        let cycle = 16 * 60 / tempo
        for frame in 1...480 {
            let next = motion.sample(at: Double(frame) * cycle / 480, tempo: tempo, moving: true)
            let step = next >= previous ? next - previous : 1 + next - previous
            #expect(abs(step - 1 / 480.0) < 0.00001)
            distance += step
            previous = next
        }
        #expect(abs(distance - 1) < 0.00001)
    }

    @Test func tempoChangesAccelerateWithoutReversingOrJumping() {
        var motion = MusicSceneRimMotion()
        _ = motion.sample(at: 0, tempo: 60, moving: true)
        let before = motion.sample(at: 0.1, tempo: 60, moving: true)
        let after = motion.sample(at: 0.2, tempo: 180, moving: true)
        let later = motion.sample(at: 0.3, tempo: 180, moving: true)
        #expect(after - before > 0.1 * 60 / 960)
        #expect(after - before < 0.1 * 120 / 960)
        #expect(later - after > after - before)
        #expect(motion.sample(at: 0.3, tempo: 60, moving: true) == later)
    }

    @Test func missingInvalidAndStaleTempoCannotJumpOrReverseTheRim() {
        var motion = MusicSceneRimMotion()
        var reference = MusicSceneRimMotion()
        let invalid: [Double?] = [nil, .nan, -.infinity, .infinity, -40, 0, 10_000]
        for (i, value) in invalid.enumerated() {
            let t = Double(i) / 30
            #expect(motion.sample(at: t, tempo: value, moving: true) == reference.sample(at: t, tempo: nil, moving: true))
        }
        let last = motion.phase
        #expect(motion.sample(at: 3_000, tempo: 100, moving: true) == last)
        #expect(motion.sample(at: 3_000.1, tempo: 100, moving: false) == last)
        #expect(motion.sample(at: 4_000, tempo: 180, moving: true) == last)
        #expect(motion.sample(at: 4_000.1, tempo: 180, moving: true) > last)
    }

    @Test func backgroundPanelKeepsMovingAtOneFramePerSecond() {
        var motion = MusicSceneRimMotion()
        let start = motion.sample(at: 0, tempo: 120, moving: true)
        let next = motion.sample(at: 1, tempo: 120, moving: true)
        #expect(abs(next - start - 0.125) < 0.000001)
    }

    @Test func animationAloneAdvancesAQuarterCycleInTwoAndAHalfSeconds() {
        var motion = MusicSceneRimMotion()
        let start = motion.sample(at: 0, tempo: nil, moving: true)
        let end = motion.sample(at: 2.5, tempo: nil, moving: true)
        let travel = (1 + end - start).truncatingRemainder(dividingBy: 1)
        #expect(abs(travel - 0.25) < 0.000001)
    }

    @Test func switchingAnimationOffAndOnPreservesPositionWithoutAnOffFrame() {
        var motion = MusicSceneRimMotion()
        _ = motion.sample(at: 30, tempo: 100, moving: true)
        let held = motion.sample(at: 30.1, tempo: 100, moving: true)
        motion.pause()
        #expect(motion.sample(at: 32.4, tempo: 120, moving: true) == held)
        #expect(motion.sample(at: 32.5, tempo: 120, moving: true) > held)
    }

    @Test(arguments: [60.0, 103.4, 176.0])
    func beatSyncAdvancesTheHighlightOnTheAttackWhileKeepingItsAverageTempo(_ bpm: Double) {
        var clock = MusicSceneRimMotion()
        let secondsPerBeat = 60 / bpm
        let tick = secondsPerBeat / 32
        let steadyStep = 1 / (32 * MusicSceneRimMotion.beatsPerCycle)
        var last = clock.sample(at: 0, tempo: bpm, moving: true)
        var total = 0.0
        var peakStep = 0.0
        var smallestStep = 1.0
        for frame in 1...512 {
            let sinceHit = Double((frame - 1) % 32) * tick
            let envelope = exp(-sinceHit / 0.115)
            let next = clock.sample(at: Double(frame) * tick, tempo: bpm, moving: true, beat: envelope)
            let step = (next - last + 1).truncatingRemainder(dividingBy: 1)
            #expect(step > 0)
            peakStep = max(peakStep, step)
            smallestStep = min(smallestStep, step)
            total += step
            last = next
        }
        #expect(peakStep > 1.4 * steadyStep)
        #expect(smallestStep < 0.93 * steadyStep)
        #expect(abs(total - 1) < 0.008)
        #expect(clock.sample(at: 20, tempo: bpm, moving: false, beat: 1) == last)
    }

    @Test(arguments: [CGSize(width: 400, height: 900), CGSize(width: 1500, height: 440)])
    func gradientTravelsRightAcrossTopOfWideAndTallScreens(_ size: CGSize) {
        let length = 2 * (size.width + size.height)
        let topLeft = (1.5 * size.height + size.width) / length
        let topRight = topLeft + size.width / length
        let left = MusicSceneRimMotion.gradientLocation(at: topLeft, in: size)
        let middle = MusicSceneRimMotion.gradientLocation(at: 0.75, in: size)
        let right = MusicSceneRimMotion.gradientLocation(at: topRight, in: size)
        #expect(left < middle && middle < right)
        #expect(abs(middle - 0.75) < 0.000001)
        let stops = (0...100).map { MusicSceneRimMotion.gradientLocation(at: Double($0) / 100, in: size) }
        #expect(zip(stops, stops.dropFirst()).allSatisfy(<))
    }
}
