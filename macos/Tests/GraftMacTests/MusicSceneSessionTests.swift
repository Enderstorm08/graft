import Foundation
import Testing
@testable import GraftMac

@MainActor
struct MusicSceneSessionTests {
    private func withSession(_ body: (MusicSceneSession, UserDefaults) throws -> Void) throws {
        let suite = "com.graft.tests.music-scene." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(MusicSceneSession(defaults: defaults), defaults)
    }

    @Test func previewClockSeeksPausesAndLoopsWithoutAPlayer() throws {
        try withSession { session, _ in
            session.startPreview()
            let playing = try #require(session.track)
            session.seek(playing.duration - 1)
            let afterSeek = try #require(session.track)
            #expect(session.position(at: afterSeek.sampledAt.addingTimeInterval(2)) == 1)
            session.playPause()
            session.seek(5)
            let paused = try #require(session.track)
            #expect(!paused.isPlaying)
            #expect(session.position(at: paused.sampledAt.addingTimeInterval(3600)) == 5)
            session.seek(.nan)
            #expect(session.track?.position == 5)
            session.seek(-8)
            #expect(session.track?.position == 0)
            session.seek(playing.duration + 4)
            #expect(session.track?.position == playing.duration)
            session.playPause()
            #expect(session.track?.isPlaying == true)
        }
    }

    @Test func previewTransportKeepsTrackAndLyricsTogetherAndClearsOnClose() throws {
        try withSession { session, _ in
            session.startPreview()
            session.setPresentation(active: true, showsContent: true)
            session.playPause()
            let first = try #require(session.track?.id)
            let firstLyrics = session.lyrics
            #expect(!firstLyrics.isEmpty)
            session.next()
            let second = try #require(session.track?.id)
            #expect(second != first)
            #expect(session.lyrics != firstLyrics)
            #expect(session.track?.position == 0)
            #expect(session.track?.isPlaying == false)
            session.seek(6)
            session.previous()
            #expect(session.track?.id == second)
            #expect(session.track?.position == 0)
            session.previous()
            #expect(session.track?.id == first)
            #expect(session.lyrics == firstLyrics)

            session.setPresentation(active: false, showsContent: false)
            #expect(!session.isPreview)
            #expect(session.track == nil)
            #expect(session.lyrics.isEmpty)
            #expect(session.position(at: .now) == 0)
            #expect(session.audioLevel == 0)
        }
    }

    @Test func previewLeavesPlayerAndAppearanceChoicesInTheSelectedSuite() throws {
        try withSession { session, defaults in
            session.preferredSource = .spotify
            session.showLyrics = true
            session.paletteMode = .tide
            session.lightIntensity = 0.4
            session.lightWidth = 9
            session.desktopLightEnabled = true
            session.startPreview()
            session.next()
            session.setPresentation(active: false, showsContent: false)

            let reopened = MusicSceneSession(defaults: defaults)
            #expect(reopened.preferredSource == .spotify)
            #expect(reopened.showLyrics)
            #expect(reopened.paletteMode == .tide)
            #expect(reopened.lightIntensity == 0.4)
            #expect(reopened.lightWidth == 9)
            #expect(reopened.desktopLightEnabled)
            #expect(!reopened.isPreview)
            reopened.preferredSource = nil
            #expect(MusicSceneSession(defaults: defaults).preferredSource == nil)
        }
    }
}
