import Foundation
@main struct SpeechTextTests {
    static func main() {
        var chunker = SentenceChunker(firstMinimum: 40, minimum: 120)
        precondition(chunker.feed("Zuerst\n").isEmpty)
        precondition(chunker.feed("17 mal 23\n").isEmpty)
        precondition(chunker.flush() == "Zuerst\n17 mal 23")
        var sentences = SentenceChunker(firstMinimum: 5, minimum: 5)
        precondition(sentences.feed("Das Ergebnis ist: ").isEmpty)
        precondition(sentences.feed("391. Weiter") == ["Das Ergebnis ist: 391."])
        precondition(sentences.flush() == "Weiter")
        precondition(SpeechTextCleaner.clean("**Hallo** [Atlas](https://example.test)") == "Hallo Atlas")
        let segments = LanguageSegments.split("Hallo <en>good morning</en>.")
        precondition(segments.count == 2 && segments[1].locale == "en-GB")
        print("PASS speech text: short lines grouped, colon preserved, complete sentence boundary, remaining text, Markdown cleaning, English segment")
    }
}
