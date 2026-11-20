import Testing
@testable import GraftMac

struct MusicSceneStickerPlacementTests {
    private func pose(_ time: Double, right: Bool = false, compact: Bool = false, reduced: Bool = false) -> MusicSceneStickerPlacement {
        MusicSceneStickerPlacement.sample(age: time, messageRight: right, compact: compact, reduceMotion: reduced)
    }

    @Test func pickupDragsUpFromTheOpenSideAndHoversAtFullSize() {
        let start = pose(0)
        let dragging = pose(0.20)
        let hovering = pose(0.345)
        #expect(start.dx == 60 && start.dy == 39)
        #expect(start.scaleX > 1 && dragging.scaleX >= 1.22)
        #expect(start.dx > dragging.dx && dragging.dx > hovering.dx)
        #expect(start.dy > dragging.dy && dragging.dy > hovering.dy)
        #expect(hovering.dy < 0 && hovering.pitchDegrees > 5)
        #expect(hovering.scaleX == dragging.scaleX)
        #expect(pose(0.405) == hovering)
        #expect(hovering.shadowRadius > pose(1).shadowRadius)
    }

    @Test func freeEdgeFlattensIntoContactAndPressureSettlesWithoutRebounding() {
        let hover = pose(0.4)
        let releasing = pose(0.47)
        let contact = pose(0.535)
        let settling = pose(0.60)
        let resting = pose(0.75)
        #expect(hover.scaleX > releasing.scaleX && releasing.scaleX > contact.scaleX)
        #expect(releasing.pitchDegrees > 0 && contact.pitchDegrees < releasing.pitchDegrees)
        #expect(contact.scaleX > 1 && contact.scaleY < 1 && contact.dy > 0)
        #expect(contact.shadowRadius < resting.shadowRadius && contact.shadowY < resting.shadowY)
        #expect(contact.shadowOpacity > resting.shadowOpacity && contact.glintAlpha > 0)
        #expect(contact.scaleX > settling.scaleX && settling.scaleX > resting.scaleX)
        #expect(contact.scaleY < settling.scaleY && settling.scaleY < resting.scaleY)
        #expect(settling.dy > 0 && settling.dy < contact.dy)
        #expect(resting.dx == 0 && resting.dy == 0)
        #expect(resting.scaleX == 1 && resting.scaleY == 1)
        #expect(resting.rotationDegrees == 8 && resting.pitchDegrees == 0)
        #expect(resting.glintAlpha == 0 && resting.shadowRadius == 2 && resting.shadowY == 2)
    }

    @Test func directionsMirrorAndCompactTravelStaysInsideItsSmallerEnvelope() {
        #expect(pose(0, compact: true).dx == 38 && pose(0, compact: true).dy == 26)
        for frame in 0...45 {
            let time = Double(frame) / 60
            let left = pose(time, compact: true)
            let right = pose(time, right: true, compact: true)
            #expect(left.dx == -right.dx && left.dy == right.dy)
            #expect(left.rotationDegrees == -right.rotationDegrees && left.pitchDegrees == -right.pitchDegrees)
            #expect(left.scaleX == right.scaleX && left.scaleY == right.scaleY)
            #expect(left.shadowRadius == right.shadowRadius && left.shadowOpacity == right.shadowOpacity)
            #expect(abs(left.dx) <= 38 && abs(left.dy) <= 26)
            #expect(left.shadowRadius > 0 && (0...1).contains(left.shadowOpacity))
        }
    }

    @Test func playbackTimeAloneSelectsThePoseAndReduceMotionIsPinnedAtTheCue() {
        let forward = [0.0, 0.21, 0.40, 0.535, 0.68, 0.75]
        let recorded = forward.map { pose($0, right: true) }
        let rewound = forward.reversed().map { pose($0, right: true) }
        #expect(recorded == Array(rewound.reversed()))
        let resting = pose(0.75, right: true)
        for age in forward + [12, 300] {
            #expect(pose(age, right: true, reduced: true) == resting)
        }
        #expect(pose(12, right: true) == resting && pose(300, right: true) == resting)
        #expect(pose(.nan, right: true) == resting && pose(.infinity, right: true) == resting)
        #expect(pose(-1) == pose(0))
    }
}
