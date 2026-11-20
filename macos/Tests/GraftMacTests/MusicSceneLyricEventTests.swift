import Testing
@testable import GraftMac

struct MusicSceneLyricEventTests {
    private let catalogTitle = "Trees (feat. zootzie & Chanel Rose)"

    private func message(_ tokens: [String], title: String = "Another Song", artist: String = "Someone") throws -> MusicSceneLyricScore.Message {
        let words = tokens.enumerated().map { index, token in
            MusicSceneWord(start: 4 + Double(index) * 0.5, text: token + (index == tokens.count - 1 ? "" : " "))
        }
        let line = MusicSceneLine(start: 4, text: words.map(\.text).joined(), words: words)
        return try #require(MusicSceneLyricScore(lines: [line], title: title, artist: artist, duration: 16).messages.first)
    }

    @Test func catalogTitleAndSeparateArtistCreditIdentifyTrees() {
        #expect(MusicSceneLyricEvent.isTrees(title: catalogTitle, artist: "kurtains"))
        #expect(MusicSceneLyricEvent.isTrees(title: "TREES", artist: "Kurtains / Zootzie / Chanel Rose"))
        #expect(!MusicSceneLyricEvent.isTrees(title: "Trees", artist: "Kurtainside"))
        #expect(!MusicSceneLyricEvent.isTrees(title: "Trees", artist: "Another Artist"))
        #expect(!MusicSceneLyricEvent.isTrees(title: "Between Trees", artist: "kurtains"))
    }

    @Test(arguments: [
        ["SLOWSILVER03!"],
        ["slow", "silver", "zero", "three"],
        ["Double", "S", "oh", "three!"],
        ["S", "S", "0", "3"],
    ])
    func producerTagReactsOnItsLastSungTokenInOtherSongs(_ tokens: [String]) throws {
        let line = try message(["Calling"] + tokens)
        let event = try #require(line.sceneEvents.only)
        let onset = try #require(line.words.last?.start)
        #expect(event.kind == .slowSilver)
        #expect(event.start == onset)
        #expect(line.reaction(at: onset) == event)
        #expect(line.reaction(at: onset + 3) == event)
        #expect(line.reaction(at: onset - 0.01) == nil)
        #expect(line.bubbleEffect(at: onset) == nil)
    }

    @Test func ordinaryPhrasesAndMetadataAloneDoNotSummonTheProducer() throws {
        for phrase in [
            ["slow", "silver", "light"],
            ["cross", "03"],
            ["silver", "03"],
            ["double", "digits", "03"],
            ["slowsilver031"],
        ] {
            let line = try message(phrase, title: "SLOWSILVER03", artist: "SLOWSILVER03")
            #expect(line.sceneEvents.isEmpty)
        }
    }

    @Test func nativeThumbsFollowExplicitEmojiAndShortSungRepliesAcrossSongs() throws {
        let thumbs: [([String], Double, MusicSceneLyricEvent.Kind)] = [
            (["All", "set", "👍🏾"], 5, .thumbUp),
            (["Still", "👎🏻", "here"], 4.5, .thumbDown),
            (["(Yeah)"], 4, .thumbUp),
            (["(no)"], 4, .thumbDown),
            (["Yep,", "yeah"], 4, .thumbUp),
            (["NOPE!"], 4, .thumbDown),
        ]
        for (words, onset, kind) in thumbs {
            let line = try message(words)
            #expect(line.sceneEvents.only?.kind == kind)
            #expect(line.reaction(at: onset - 0.01) == nil)
            #expect(line.reaction(at: onset)?.kind == kind)
            #expect(line.bubbleEffect(at: onset) == nil)
        }
        for phrase in [["No", "more", "rain"], ["Yeah,", "we", "remember"], ["Yes", "and", "no"], ["Ha!", "today"]] {
            #expect(try message(phrase).sceneEvents.isEmpty)
        }
    }

    @Test func onlyClearLaughterAndPhraseEndingPunctuationReceiveTapbacks() throws {
        let laughter = try message(["(ha", "ha", "ha)"])
        #expect(laughter.sceneEvents.only?.start == 4.5)
        #expect(laughter.reaction(at: 4.5)?.kind == .laugh)
        #expect(try message(["Haha!"]).sceneEvents.only?.kind == .laugh)
        let question = try message(["Wait,", "really？”"])
        #expect(question.reaction(at: 4.49) == nil)
        #expect(question.reaction(at: 4.50)?.kind == .question)
        #expect(try message(["Come", "on!!"]).sceneEvents.only?.kind == .emphasize)
        #expect(try message(["Wait?", "now"]).sceneEvents.isEmpty)
        #expect(try message(["Come", "on!"]).sceneEvents.isEmpty)
    }

    @Test func writtenReactionsRespectStickersSongSpecificTapbacksAndLinks() throws {
        let tag = try message(["SS03", "right?"])
        #expect(tag.sceneEvents.map(\.kind) == [.slowSilver, .question])
        #expect(tag.reaction(at: 4.5)?.kind == .slowSilver)
        let both = try message(["Haha", "blah", "blah"], title: catalogTitle, artist: "kurtains")
        #expect(both.sceneEvents.filter { $0.kind == .laugh }.count == 1)
        let sameWord = try message(["Twitter!!"], title: catalogTitle, artist: "kurtains")
        #expect(sameWord.sceneEvents.only?.kind == .emphasize)
        let link = try message(["Talk", "on", "Twitter!!"], title: catalogTitle, artist: "kurtains")
        #expect(link.twitterLinkStart == 5)
        #expect(link.sceneEvents.isEmpty)
    }

    @Test func collectiveTagCanFinishOnTheNextLine() throws {
        let lines = [
            MusicSceneLine(start: 1, text: "Slow silver", end: 1.9),
            MusicSceneLine(start: 2, text: "oh three", words: [
                .init(start: 2, text: "oh "), .init(start: 2.4, text: "three")
            ])
        ]
        let score = MusicSceneLyricScore(lines: lines, duration: 5)
        #expect(score.messages[0].sceneEvents.isEmpty)
        #expect(score.messages[1].reaction(at: 2.39) == nil)
        #expect(score.messages[1].reaction(at: 2.4)?.kind == .slowSilver)
        let gap = MusicSceneLyricScore(lines: [lines[0], .init(start: 8, text: "oh three")], duration: 10)
        #expect(gap.messages[1].sceneEvents.isEmpty)
    }

    @Test func twitterCardUsesTheSungWordAndOnlyChangesTheRequestedDomain() throws {
        let tokens = ["He", "like", "to", "talk", "on", "Twitter"]
        let line = try message(tokens, title: catalogTitle, artist: "kurtains")
        #expect(line.text == "He like to talk on Twitter.com")
        #expect(line.words.map(\.text).joined() == line.text)
        #expect(line.twitterLinkStart == 6.5)
        #expect(line.visibleWordCount(at: 6.49) == 5)
        #expect(line.visibleWordCount(at: 6.50) == 6)
        #expect(line.sceneEvents.isEmpty)

        let another = try message(tokens, title: "Trees", artist: "Someone Else")
        #expect(another.text == tokens.joined(separator: " "))
        #expect(another.twitterLinkStart == nil)
        for unrelated in [["Read", "Twitter"], ["Talk", "on", "Twitter.commerce"], ["Talk", "on", "myTwitter"]] {
            let otherLine = try message(unrelated, title: catalogTitle, artist: "kurtains")
            #expect(otherLine.text == unrelated.joined(separator: " "))
            #expect(otherLine.twitterLinkStart == nil)
        }
    }

    @Test func existingTwitterDomainPreservesEnclosingPunctuationAndFollowingLyrics() throws {
        let line = try message(["he", "like", "to", "talk", "on", "“TWITTER.COM,”", "chatter!"], title: catalogTitle, artist: "kurtains")
        #expect(line.text == "He like to talk on “Twitter.com,” chatter!")
        #expect(line.twitterLinkStart == 6.5)
        #expect(line.words.last?.text == "chatter!")
        #expect(line.words.last?.start == 7.0)
        #expect(line.reaction(at: 7) == nil)
    }

    @Test func enhancedLRCStillRevealsSyllablesOnProviderBoundaries() {
        let words = [
            MusicSceneWord(start: 12, text: "Talk on ", end: 13),
            MusicSceneWord(start: 13, text: "Twit", end: 13.15),
            MusicSceneWord(start: 13.15, text: "ter!", end: 13.6),
        ]
        let line = MusicSceneLine(start: 12, text: "Talk on Twitter!", words: words, end: 14)
        let first = MusicSceneLyricScore(lines: [line], title: catalogTitle, artist: "kurtains", duration: 15).messages.first
        #expect(first?.words.map(\.start) == words.map(\.start))
        #expect(first?.words.map(\.end) == words.map(\.end))
        #expect(first?.words.map(\.text) == ["Talk on ", "Twit", "ter.com!"])
        #expect(first?.twitterLinkStart == 13)
    }

    @Test func songSpecificEffectsFollowEachWordAndReconstructAfterSeeking() throws {
        let words = ["Blah,", "blah,", "blah,", "stop", "dark", "cheese"]
        let line = try message(words, title: catalogTitle, artist: "kurtains")
        #expect(line.sceneEvents.map(\.kind) == [.echo, .laugh, .slam, .invisibleInk, .spotlight])
        #expect(line.reaction(at: 4.49) == nil)
        #expect(line.reaction(at: 4.50)?.kind == .laugh)
        #expect(line.bubbleEffect(at: 6.50)?.kind == .spotlight)
        #expect(line.bubbleEffect(at: 7.71) == nil)
        #expect(line.bubbleEffect(at: 6.0)?.kind == .invisibleInk)
        #expect(line.bubbleEffect(at: 5.5)?.kind == .slam)
        #expect(line.bubbleEffect(at: 4.0)?.kind == .echo)
        #expect(line.bubbleEffect(at: 3.99) == nil)
        #expect(try message(words, title: "Trees", artist: "Someone Else").sceneEvents.isEmpty)
    }

    @Test func stutterEchoAndTapbacksHaveDistinctClocks() throws {
        let line = try message(["Tre", "tre", "tree", "tick", "tick", "Twitter", "why?"], title: "Trees", artist: "kurtains")
        #expect(line.sceneEvents.map(\.kind) == [.stutter, .echo, .emphasize, .question])
        #expect(line.sceneEvents.map(\.start) == [4.0, 5.5, 6.5, 7.0])
        #expect(line.reaction(at: 7.1)?.kind == .question)
        #expect(line.reaction(at: 6.5)?.kind == .emphasize)
        #expect(line.reaction(at: 6.4) == nil)
        #expect(line.bubbleEffect(at: 5.49) == nil)
        #expect(line.bubbleEffect(at: 5.5)?.kind == .echo)
        #expect(try message(["Tre-tre-tree"], title: catalogTitle, artist: "kurtains").sceneEvents.only?.kind == .stutter)
        #expect(try message(["(there?)"], title: catalogTitle, artist: "kurtains").reaction(at: 4)?.kind == .question)
    }

    @Test func stutterRevealsEachSyllableWithoutChangingTheWrittenLyric() throws {
        let line = MusicSceneLine(start: 8, text: "Tre-tre-tree", end: 10)
        let nextLine = MusicSceneLine(start: 10, text: "two-step", end: 12)
        let score = MusicSceneLyricScore(lines: [line, nextLine], title: catalogTitle, artist: "kurtains", duration: 12)
        let stutter = try #require(score.messages.first)
        #expect(stutter.text == line.text)
        #expect(stutter.words.map(\.text).joined() == line.text)
        try #require(stutter.words.count == 3)
        #expect(stutter.words[0].start == 8)
        #expect(stutter.words[1].start > stutter.words[0].start)
        #expect(stutter.words[2].start > stutter.words[1].start)
        #expect(stutter.words[2].start < 8.5)
        #expect(stutter.words.map { stutter.visibleWordCount(at: $0.start) } == [1, 2, 3])
        #expect(stutter.sceneEvents.map(\.kind) == [.stutter])
        #expect(score.messages.last?.words.map(\.text) == ["two-step"])
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
