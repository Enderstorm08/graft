import Foundation
import Testing
@testable import GraftMac

struct MusicSceneLyricsTests {
    private let track = MusicSceneTrack(id: "recording", source: .spotify, title: "T + K", artist: "Graft",
                                       album: "Demo", duration: 42, position: 0, isPlaying: true,
                                       sampledAt: .now, artworkURL: nil, artworkData: nil)

    @Test func repeatedEnhancedLRCUsesAbsoluteWordTimesAtEachChorus() {
        let parsed = MusicSceneLyrics.parseLRC("""
            [ar:Graft]
            [00:01.20][00:10.20]<00:01.20>Follow <00:02.30>the light
            [00:04.20]
            [offset:+200]
            """)
        #expect(parsed.map(\.start) == [1, 10])
        #expect(parsed.map(\.text) == ["Follow the light", "Follow the light"])
        #expect(parsed.first?.end == 4)
        #expect(parsed.last?.end == nil)
        #expect(parsed.first?.words.map(\.text) == ["Follow ", "the light"])
        #expect(abs((parsed.last?.words.last?.start ?? 0) - 11.1) < 0.001)
        #expect(MusicSceneLyrics.parseLRC("[00:73.12]Invalid\n[00:00,5]Earlier\n[offset:-500]")
            == [.init(start: 1, text: "Earlier")])
    }

    @Test func emptyEnhancedWordMarkerKeepsVocalReleaseAcrossRepeatedLines() throws {
        let lines = MusicSceneLyrics.parseLRC("[00:02][00:12]<00:02>Oh <00:02.8><00:05>go<00:05.4>\n[offset:+300]")
        #expect(lines.count == 2)
        for (index, line) in lines.enumerated() {
            let shift = Double(index) * 10 - 0.3
            #expect(line.text == "Oh go")
            let first = try #require(line.words.first?.end)
            let end = try #require(line.end)
            #expect(abs(first - (2.8 + shift)) < 0.00001)
            #expect(abs(end - (5.4 + shift)) < 0.00001)
        }
    }

    @Test func exactRequestPrefersWordTimesAndCachesTheRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = try JSONSerialization.data(withJSONObject: [
            "instrumental": false, "hasWordSync": true, "syncedLyrics": "[00:01.0]Fallback",
            "lyricsfile": """
                version: "1.0"
                lines:
                  - text: "Find a signal"
                    start_ms: 1240
                    end_ms: 2900
                    words:
                      - {text: "Find ", start_ms: 1240, end_ms: 1520}
                      - {text: "a signal", start_ms: 1740}
                """
        ])
        let service = MusicSceneLyrics(directory: directory, cache: directory.appending(path: "cache")) { request in
            let url = try #require(request.url)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(url.host == "lrclib.net" && url.path == "/api/get")
            #expect(url.absoluteString.contains("%2B"))
            #expect(query.contains(.init(name: "album_name", value: "Demo")))
            #expect(query.contains(.init(name: "duration", value: "42")))
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("github.com/itsasheruwu/graft") == true)
            return (response, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await service.fetch(for: track)
        #expect(result == [.init(start: 1.24, text: "Find a signal", words: [
            .init(start: 1.24, text: "Find ", end: 1.52), .init(start: 1.74, text: "a signal")
        ], end: 2.9)])
        let offline = MusicSceneLyrics(directory: directory, cache: directory.appending(path: "cache")) { _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(try await offline.fetch(for: track) == result)
        let file = directory.appending(path: "new.lrc")
        try "[00:01.00]Local correction".write(to: file, atomically: true, encoding: .utf8)
        let imported = try await service.importFile(file, for: track)
        try "Untimed words".write(to: file, atomically: true, encoding: .utf8)
        await #expect(throws: MusicSceneLyricsError.invalidFile) { try await service.importFile(file, for: track) }
        #expect(try await offline.fetch(for: track) == imported)
        #expect(imported.map(\.text) == ["Local correction"])
    }

    @Test func providerFailuresDistinguishSilenceMissingRecordAndDowntime() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for (status, data, expected) in [
            (200, #"{"instrumental":true}"#, MusicSceneLyricsError.instrumental),
            (200, #"{"instrumental":false,"plainLyrics":""}"#, .unsynced),
            (200, "invalid", .serviceUnavailable),
            (404, "", .noMatch),
            (500, "", .serviceUnavailable)
        ] {
            let service = MusicSceneLyrics(directory: directory, cache: directory) { request in
                (Data(data.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            await #expect(throws: expected) { try await service.fetch(for: track) }
        }
    }

    @Test func observesProviderRetryAfterEvenWithADifferentSong() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        actor Provider {
            var count = 0
            func reject(_ request: URLRequest) -> (Data, URLResponse) {
                count += 1
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 429,
                    httpVersion: nil, headerFields: ["Retry-After": "60"])!)
            }
        }
        let provider = Provider()
        let service = MusicSceneLyrics(directory: directory, cache: directory) { await provider.reject($0) }
        let other = MusicSceneTrack(id: "other", source: .appleMusic, title: "Signal", artist: "Graft", album: "",
                                   duration: 130, position: 0, isPlaying: false, sampledAt: .now, artworkURL: nil, artworkData: nil)
        await #expect(throws: MusicSceneLyricsError.rateLimited) { try await service.fetch(for: track) }
        await #expect(throws: MusicSceneLyricsError.rateLimited) { try await service.fetch(for: other) }
        #expect(await provider.count == 1)
    }

    @Test func alternateAlbumRequiresTheSameRecording() async throws {
        for (returnedTitle, returnedDuration, shouldMatch) in [
            ("T + K", 42.7, true), ("T + K (Live)", 42.7, false), ("T + K", 47.0, false)
        ] {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let service = MusicSceneLyrics(directory: directory, cache: directory.appending(path: "cache")) { request in
                let url = try #require(request.url)
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let original = query.contains { $0.name == "album_name" }
                let data = try JSONSerialization.data(withJSONObject: [
                    "trackName": returnedTitle, "artistName": "Graft", "duration": returnedDuration,
                    "instrumental": false, "syncedLyrics": "[00:01]A signal"
                ])
                let response = HTTPURLResponse(url: url, statusCode: original ? 404 : 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            if shouldMatch {
                #expect(try await service.fetch(for: track).map(\.text) == ["A signal"])
            } else {
                await #expect(throws: MusicSceneLyricsError.noMatch) { try await service.fetch(for: track) }
            }
        }
    }

    @Test func untimedProviderTextYieldsToVerifiedTimingAndKeepsItsOwnStanzasOtherwise() async throws {
        for alternateDuration in [42.1, 122.0] {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = directory.appending(path: "cache")
            let service = MusicSceneLyrics(directory: directory, cache: cache) { request in
                let url = try #require(request.url)
                let original = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "album_name" } == true
                let record: [String: Any] = original
                    ? ["instrumental": false, "plainLyrics": "冬の光\n\n  Encore ?"]
                    : ["instrumental": false, "trackName": "T + K", "artistName": "Graft",
                       "duration": alternateDuration, "syncedLyrics": "[00:05]A timed line"]
                let data = try JSONSerialization.data(withJSONObject: record)
                return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let result = try await service.fetch(for: track)
            if alternateDuration < 43 {
                #expect(result == [.init(start: 5, text: "A timed line")])
            } else {
                #expect(result.map(\.text) == ["冬の光", "  Encore ?"])
                #expect(result.allSatisfy { $0.isEstimated && $0.words.isEmpty })
                #expect(try #require(result.first?.end) < result[1].start)
                #expect(result.last?.end == 42)
            }
            let offline = MusicSceneLyrics(directory: directory, cache: cache) { _ in throw URLError(.notConnectedToInternet) }
            #expect(try await offline.fetch(for: track) == result)
        }
    }

    @Test func plainImportSurvivesRelaunchAndRetainsLiteralText() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let offline: MusicSceneLyrics.Request = { _ in throw URLError(.notConnectedToInternet) }
        let service = MusicSceneLyrics(directory: directory, cache: directory.appending(path: "cache"), request: offline)
        let plain = directory.appending(path: "song.txt")
        try "[00:02] is on the wall\r\n\r\n月".write(to: plain, atomically: true, encoding: .utf16)
        let imported = try await service.importFile(plain, for: track)
        #expect(imported.map(\.text) == ["[00:02] is on the wall", "月"])
        #expect(imported.allSatisfy { $0.isEstimated })
        let reopened = MusicSceneLyrics(directory: directory, cache: directory.appending(path: "cache"), request: offline)
        #expect(try await reopened.fetch(for: track) == imported)
        let lrc = directory.appending(path: "song.lrc")
        try "[00:04]Actual line".write(to: lrc, atomically: true, encoding: .utf8)
        #expect(try await reopened.importFile(lrc, for: track) == [.init(start: 4, text: "Actual line")])
        #expect(try await service.fetch(for: track).first?.isEstimated == false)
    }
}
