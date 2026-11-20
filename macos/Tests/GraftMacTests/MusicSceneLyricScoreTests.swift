import Testing
@testable import GraftMac

struct MusicSceneLyricScoreTests {
    @Test func backingVocalsStartTheirOwnMessageOnTheSungWord() throws {
        let score = MusicSceneLyricScore(lines: [
            .init(start: 2, text: "Go now (come back)", words: [
                .init(start: 2, text: "Go "), .init(start: 2.3, text: "now "),
                .init(start: 3.4, text: "(come "), .init(start: 3.9, text: "back)")
            ], end: 4.4)
        ])
        #expect(score.messages.map(\.right) == [false, true])
        #expect(score.activeIndex(at: 1.9) == nil)
        #expect(score.activeIndex(at: 3.39) == 0)
        #expect(score.activeIndex(at: 3.4) == 1)
        let reply = try #require(score.messages.last)
        #expect(reply.visibleWordCount(at: 3.9) == 2)
        #expect(reply.visibleWordCount(at: 3.5) == 1)
        #expect(reply.visibleWordCount(at: 3.39) == 0)
        #expect(score.activeIndex(at: 2) == 0)
    }

    @Test func overlappingVoicesAreSortedByOnset() {
        let score = MusicSceneLyricScore(lines: [
            .init(start: 2, text: "Calling (hello)", words: [
                .init(start: 2, text: "Calling "), .init(start: 4, text: "(hello)")
            ]),
            .init(start: 3, text: "There")
        ])
        #expect(score.messages.map(\.text) == ["Calling", "There", "(hello)"])
        #expect(score.activeIndex(at: 3.5) == 1)
        #expect(score.activeIndex(at: 4.1) == 2)
    }

    @Test func lineTimingKeepsPunctuationAndLeavesLongInstrumentalsEmpty() throws {
        let score = MusicSceneLyricScore(lines: [
            .init(start: 0, text: "Blue,   then green.", end: 2),
            .init(start: 9, text: "東京", end: 11),
            .init(start: 12, text: "Final", end: 15)
        ], duration: 16)
        let line = try #require(score.messages.first)
        #expect(line.words.map(\.text).joined() == line.text)
        #expect(line.visibleWordCount(at: 0) == 1)
        #expect(line.visibleWordCount(at: 1.99) == 3)
        #expect(!score.isInterlude(after: 0, at: 1.99))
        #expect(score.isInterlude(after: 0, at: 3))
        #expect(score.messages[1].words.map(\.text) == ["東", "京"])
        #expect(!score.isInterlude(after: 1, at: 11.1))
    }

    @Test func literalMotifsUseTheKeywordClockAndTitleCueUsesRecordingIdentity() {
        let lines: [MusicSceneLine] = [
            .init(start: 0, text: "Our town", words: [.init(start: 0, text: "Our "), .init(start: 1.4, text: "town")]),
            .init(start: 2, text: "Cash only"),
            .init(start: 4, text: "Ash!"),
            .init(start: 6, text: "Go, go, go!"),
            .init(start: 8, text: "Hello Asheville")
        ]
        let source = MusicSceneLyricScore(lines: lines, title: "Asheville", artist: "glaive", duration: 12)
        #expect(source.messages.map(\.motif) == [.asheville, nil, .ashes, nil, .asheville])
        #expect(source.messages[0].motifStart == 1.4)
        #expect(source.messages[3].repeated)
        let other = MusicSceneLyricScore(lines: lines, title: "Asheville", artist: "Another artist", duration: 12)
        #expect(other.messages[0].motif == nil)
        #expect(other.messages[4].motif == .asheville)
    }

    @Test func holdingTheSameSyllableDiffersFromRestingBeforeTheNextLine() throws {
        func score(end: Double?) -> MusicSceneLyricScore {
            MusicSceneLyricScore(lines: [
                .init(start: 0, text: "Tu vas", words: [.init(start: 0, text: "Tu "), .init(start: 0.2, text: "vas", end: end)]),
                .init(start: 9, text: "Déjà loin")
            ], duration: 12)
        }
        let held = try #require(score(end: 1.5).messages[0].accents[1])
        #expect(held.kind == .bloom)
        #expect(held.duration == 1.3)
        #expect(score(end: 0.3).messages[0].accents[1]?.kind != .bloom)
        #expect(score(end: nil).messages[0].accents[1]?.kind != .bloom)
    }

    @Test func repeatedOnsetsChangeTheMotionAtTheSungWord() throws {
        func accent(spacing: Double) throws -> MusicSceneWordAccent {
            let score = MusicSceneLyricScore(lines: [
                .init(start: 1, text: "来 来", words: [.init(start: 1, text: "来 "), .init(start: 1 + spacing, text: "来")])
            ])
            #expect(score.messages[0].accents[0] == nil)
            return try #require(score.messages[0].accents[1])
        }
        #expect(try accent(spacing: 0.14).kind == .jitter)
        #expect(try accent(spacing: 0.52).kind == .nod)
    }

    @Test func writtenMeaningAndSongStructureAlsoWorkWithLineOnlyTiming() {
        let score = MusicSceneLyricScore(lines: [
            .init(start: 0, text: "A hush"),
            .init(start: 3, text: "Our light"),
            .init(start: 6, text: "The night"),
            .init(start: 9, text: "Our light"),
            .init(start: 12, text: "Encore？"),
            .init(start: 15, text: "Así…")
        ], duration: 18)
        let kinds = score.messages.map { $0.accents.compactMap { $0?.kind } }
        #expect(kinds == [[.small], [.nod], [.ripple], [.big], [.ripple], [.small]])
        #expect(score.messages.allSatisfy { $0.accents.count == $0.words.count })
    }

    @Test func estimatedPhrasesUseTheirAllottedTimeAndRespectShortStanzaBreaks() throws {
        let score = MusicSceneLyricScore(lines: [
            .init(start: 0, text: "One two three", end: 8, estimated: true),
            .init(start: 9, text: "月", end: 12, estimated: true)
        ], duration: 12)
        #expect(score.estimatedTiming)
        let finalWord = try #require(score.messages.first?.words.last)
        #expect(finalWord.start > 3 && finalWord.start < 8)
        #expect(score.isInterlude(after: 0, at: 8.5))
        #expect(score.activeIndex(at: 9.1) == 1)
    }
}
