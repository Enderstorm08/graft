import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GraftMac

struct MusicSceneArtworkLookupTests {
    private func track(_ source: MusicSceneSource = .appleMusic, eligible: Bool = true, url: URL? = nil, local: Data? = nil) -> MusicSceneTrack {
        .init(id: "private-id", source: source, title: "A Song", artist: "Band", album: "Our Album",
              duration: 182.85, position: 3, isPlaying: false, sampledAt: .now, artworkURL: url,
              artworkData: local, allowsCatalogArtwork: eligible)
    }

    private actor Requests {
        var urls: [URL] = []
        func record(_ url: URL) -> Int { urls.append(url); return urls.count }
    }

    private func cover(_ brightness: CGFloat, side: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: brightness, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func onlyEnlargesMatchingLocalArtworkAndCachesPerRelease() async throws {
        let thumb = "https://is1-ssl.mzstatic.com/image/thumb/test/100x100bb.jpg"
        let large = thumb.replacingOccurrences(of: "100x100", with: "2400x2400")
        let search = try JSONSerialization.data(withJSONObject: ["results": [
            ["artistName": "Different artist", "collectionName": "Our Album", "artworkUrl100": thumb + "?wrongArtist"],
            ["artistName": "Band", "collectionName": "Different release", "artworkUrl100": thumb + "?wrongAlbum"],
            ["artistName": "Band", "collectionName": "Our Album", "artworkUrl100": "https://example.com/100x100bb.jpg"],
            ["artistName": "Bánd", "collectionName": "Our Album", "artworkUrl100": thumb]
        ]])
        let thumbnail = try cover(0.23, side: 100)
        let full = try cover(0.23, side: 1300)
        let original = try cover(0.23, side: 600)
        let custom = try cover(0.83, side: 600)
        actor Provider {
            var requests: [URL] = []
            func record(_ url: URL) { requests.append(url) }
        }
        let provider = Provider()
        let service = MusicSceneArtworkLookup { url in
            await provider.record(url)
            switch url.host {
            case "itunes.apple.com":
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                #expect(query?.contains(.init(name: "term", value: "Band Our Album")) == true)
                return search
            default:
                if url.absoluteString == large { return full }
                #expect(url.absoluteString == thumb)
                return thumbnail
            }
        }
        #expect(try await service.image(artist: "Band", album: "Our Album", original: original) == full)
        #expect(try await service.image(artist: "Band", album: "Our Album", original: original) == full)
        #expect(await provider.requests.count == 3)

        // A custom sleeve on another track of the same release must survive a positive cache hit.
        #expect(try await service.image(artist: "Band", album: "Our Album", original: custom) == nil)
        #expect(try await service.image(artist: "Band", album: "Our Album", original: custom) == nil)
        #expect(await provider.requests.count == 5)
        #expect(try await service.image(artist: "Band", album: "Our Album", original: full) == nil)
        #expect(try await service.image(artist: "", album: "Our Album", original: original) == nil)
        #expect(await provider.requests.count == 5)
    }

    @Test func missingCatalogCoverRequiresAnExactRecordingAndDoesNotCacheInvalidLocalBytes() async throws {
        let thumb = "https://is1-ssl.mzstatic.com/image/thumb/test/100x100bb.jpg"
        let large = thumb.replacingOccurrences(of: "100x100", with: "1200x1200")
        let fixture = try cover(0.35, side: 1200)
        let search = try JSONSerialization.data(withJSONObject: ["results": [
            ["artistName": "Band", "collectionName": "Our Album", "trackName": "A Song", "trackTimeMillis": 140_000, "artworkUrl100": thumb + "?edit"],
            ["artistName": "Band", "collectionName": "Reissue", "trackName": "A Song", "trackTimeMillis": 183_000, "artworkUrl100": thumb + "?release"],
            ["artistName": "Band", "collectionName": "Our Album", "trackName": "A Song (Live)", "trackTimeMillis": 183_000, "artworkUrl100": thumb + "?live"],
            ["artistName": "Bánd", "collectionName": "Our Album", "trackName": "A Song", "trackTimeMillis": 182_806, "artworkUrl100": thumb]
        ]])
        let requests = Requests()
        let lookup = MusicSceneArtworkLookup { url in
            _ = await requests.record(url)
            if url.host == "itunes.apple.com" {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                #expect(items?.contains(.init(name: "term", value: "Band A Song")) == true)
                #expect(!url.absoluteString.contains("private-id"))
                return search
            }
            #expect(url.absoluteString == large)
            return fixture
        }
        let selection = track(local: Data("invalid".utf8))
        #expect(try await lookup.cover(for: selection) == fixture)
        #expect(try await lookup.cover(for: track()) == fixture)
        let embedded = try cover(0.95, side: 180)
        #expect(try await lookup.cover(for: track(local: embedded)) == embedded)
        #expect(await requests.urls.count == 2)
    }

    @Test func unavailablePrivateOrAmbiguousCoversNeverPickAnUnrelatedCatalogResult() async throws {
        let requests = Requests()
        let results = try JSONSerialization.data(withJSONObject: ["results": ["one", "two"].map { release in
            ["artistName": "Band", "collectionName": "Our Album", "trackName": "A Song", "trackTimeMillis": 183_000,
             "artworkUrl100": "https://is2.mzstatic.com/\(release)/100x100bb.jpg"] as [String: Any]
        }])
        let lookup = MusicSceneArtworkLookup { url in
            _ = await requests.record(url)
            #expect(url.host == "itunes.apple.com")
            return results
        }
        #expect(try await lookup.cover(for: track(eligible: false)) == nil)
        #expect(try await lookup.cover(for: track(.spotify)) == nil)
        #expect(await requests.urls.isEmpty)
        #expect(try await lookup.cover(for: track()) == nil)
        #expect(await requests.urls.count == 1)
    }

    @Test func spotifyRetriesTransientAndInvalidImagesAndReusesOnlySuccessfulImageURLs() async throws {
        let requests = Requests()
        let url = try #require(URL(string: "https://i.scdn.co/image/cover"))
        let fixture = try cover(0.52, side: 300)
        let lookup = MusicSceneArtworkLookup { requested in
            #expect(requested == url)
            switch await requests.record(requested) {
            case 1: throw URLError(.timedOut)
            case 2: return Data("not an image".utf8)
            default: return fixture
            }
        }
        let spotify = track(.spotify, url: url)
        await #expect(throws: URLError.self) { try await lookup.cover(for: spotify) }
        #expect(try await lookup.cover(for: spotify) == nil)
        #expect(try await lookup.cover(for: spotify) == fixture)
        #expect(try await lookup.cover(for: spotify) == fixture)
        #expect(await requests.urls.count == 3)
    }
}
