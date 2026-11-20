import Foundation
import Testing
@testable import GraftMac

struct MusicScenePlaybackTests {
    private let date = Date(timeIntervalSince1970: 1_000)

    private func track(_ source: MusicSceneSource, playing: Bool) -> MusicSceneTrack {
        .init(id: "example", source: source, title: "Example", artist: "Graft", album: "Test",
              duration: 60, position: 25, isPlaying: playing, sampledAt: date,
              artworkURL: nil, artworkData: nil)
    }

    @Test func playbackClockStaysStillOnPauseAndStopsAtSongEnd() {
        #expect(track(.appleMusic, playing: false).position(at: date.addingTimeInterval(10)) == 25)
        let playing = track(.appleMusic, playing: true)
        #expect(playing.position(at: date.addingTimeInterval(5)) == 30)
        #expect(playing.position(at: date.addingTimeInterval(90)) == 60)
        #expect(playing.position(at: date.addingTimeInterval(-8)) == 25)
    }

    @Test func activePlaybackWinsOverPausedPlayer() throws {
        let result = try MusicScenePlayback.choose([.appleMusic, .spotify], requestAccess: false) { source, connect in
            #expect(!connect)
            return track(source, playing: source == .spotify)
        }
        #expect(result?.source == .spotify)
    }

    @Test func connectedPlayerRemainsAvailableIfOtherPlayerRequiresPermission() throws {
        let result = try MusicScenePlayback.choose([.appleMusic, .spotify], requestAccess: true) { source, connect in
            #expect(!connect)
            if source == .appleMusic { throw MusicScenePlaybackError.needsAccess(source) }
            return track(source, playing: false)
        }
        #expect(result?.source == .spotify)
    }

    @Test func artworkProbeRecoversLateMetadataWithoutHammeringThePlayer() {
        var probe = MusicSceneArtworkProbe()
        #expect(probe.isDue(for: "a", at: date))
        probe.record(track: "a", at: date, complete: false, refreshURL: false)
        #expect(!probe.isDue(for: "a", at: date.addingTimeInterval(1)))
        #expect(probe.isDue(for: "a", at: date.addingTimeInterval(2)))
        probe.record(track: "a", at: date.addingTimeInterval(2), complete: false, refreshURL: false)
        #expect(!probe.isDue(for: "a", at: date.addingTimeInterval(5)))
        #expect(probe.isDue(for: "a", at: date.addingTimeInterval(6)))
        #expect(probe.isDue(for: "b", at: date.addingTimeInterval(3)))
        probe.record(track: "a", at: date.addingTimeInterval(6), complete: true, refreshURL: false)
        #expect(!probe.isDue(for: "a", at: date.addingTimeInterval(3600)))
        probe.record(track: "b", at: date, complete: true, refreshURL: true)
        #expect(!probe.isDue(for: "b", at: date.addingTimeInterval(59)))
        #expect(probe.isDue(for: "b", at: date.addingTimeInterval(60)))
    }

    @Test func automaticPollingCannotPromptAndExplicitConnectAsksOnlyOnce() throws {
        var prompts: [MusicSceneSource] = []
        func read(_ source: MusicSceneSource, _ connect: Bool) throws -> MusicSceneTrack? {
            guard connect else { throw MusicScenePlaybackError.needsAccess(source) }
            prompts.append(source)
            return track(source, playing: false)
        }
        #expect(throws: MusicScenePlaybackError.needsAccess(.spotify)) {
            _ = try MusicScenePlayback.choose([.spotify, .appleMusic], requestAccess: false, read: read)
        }
        #expect(prompts.isEmpty)
        _ = try MusicScenePlayback.choose([.spotify, .appleMusic], requestAccess: true, read: read)
        #expect(prompts == [.spotify])
    }
}
