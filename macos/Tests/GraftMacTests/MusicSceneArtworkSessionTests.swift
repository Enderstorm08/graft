import AppKit
import Testing
@testable import GraftMac

@MainActor
struct MusicSceneArtworkSessionTests {
    private func track(_ id: String, data: Data? = nil, url: URL? = nil, sampledAt: Date = .now) -> MusicSceneTrack {
        MusicSceneTrack(id: id, source: url == nil ? .appleMusic : .spotify, title: id, artist: "Performer", album: "Album",
                       duration: 184, position: 0, isPlaying: false, sampledAt: sampledAt, artworkURL: url, artworkData: data)
    }

    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.65, blue: 0.72, alpha: 1), atX: 24, y: 24)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func sameTrackAcceptsPlayerArtworkThatArrivesAfterItsTitle() throws {
        let session = MusicSceneSession()
        session.apply(track("first"))
        #expect(session.artwork == nil)
        session.apply(track("first", data: try png()))
        let cover = try #require(session.artwork)
        session.apply(track("first"))
        #expect(session.artwork === cover)
        session.apply(track("second"))
        #expect(session.artwork == nil)
    }

    @Test func transientImageFailureRetriesWithinTheSameTrack() async throws {
        actor Provider {
            var requests = 0
            func load(_ image: Data) throws -> Data {
                requests += 1
                if requests == 1 { throw URLError(.timedOut) }
                return image
            }
        }
        let provider = Provider()
        let png = try png()
        let session = MusicSceneSession(artworkLookup: MusicSceneArtworkLookup { _ in try await provider.load(png) })
        let url = try #require(URL(string: "https://i.scdn.co/image/test-release"))
        session.apply(track("single", url: url))
        for _ in 0..<150 {
            if session.artwork != nil { break }
            try await Task.sleep(for: .milliseconds(8))
            session.apply(track("single", url: url, sampledAt: .now.addingTimeInterval(100)))
        }
        #expect(await provider.requests == 2)
        #expect(session.artwork != nil)
    }

    @Test func oldDownloadCannotReplaceTheNextSongsEmbeddedCover() async throws {
        actor Gate {
            var requested = false
            var finished = false
            func hold() async {
                requested = true
                while !finished { await Task.yield() }
            }
            func release() { finished = true }
        }
        let gate = Gate()
        let art = try png()
        let session = MusicSceneSession(artworkLookup: MusicSceneArtworkLookup { _ in
            await gate.hold()
            return art
        })
        let url = try #require(URL(string: "https://i.scdn.co/image/old-release"))
        session.apply(track("old", url: url))
        for _ in 0..<100 {
            if await gate.requested { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let didStart = await gate.requested
        session.apply(track("new", data: art))
        let current = session.artwork
        await gate.release()
        try await Task.sleep(for: .milliseconds(30))
        #expect(didStart)
        #expect(current != nil && current === session.artwork)
    }
}
