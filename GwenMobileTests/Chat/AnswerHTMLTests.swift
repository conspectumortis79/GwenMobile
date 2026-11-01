@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class AnswerHTMLTests: GwenTestCase {
    func testInlineMarkdownBecomesRealFormatting() {
        XCTAssertEqual(AnswerHTML.inline("Die **BRD** wurde *1949* gegründet und `Art 1` gilt."),
                       "Die <strong>BRD</strong> wurde <em>1949</em> gegründet und <code>Art 1</code> gilt.")
        XCTAssertEqual(AnswerHTML.inline("~~gestrichen~~"), "<del>gestrichen</del>")
    }

    func testMarkdownSyntaxNeverSurvives() {
        let html = AnswerHTML.blocks(in: "Die **BRD** wurde 1949 gegründet.\n\n- Punkt **fett**\n- Punkt zwei",
                                     sources: [])
        XCTAssertFalse(html.contains("**"))
        XCTAssertFalse(html.contains("\n- "))
        XCTAssertTrue(html.contains("<strong>BRD</strong>"))
        XCTAssertTrue(html.contains("<ul><li>Punkt <strong>fett</strong></li><li>Punkt zwei</li></ul>"))
    }

    func testLinksAndHeadingsAreRendered() {
        XCTAssertEqual(AnswerHTML.inline("mehr unter [Grundgesetz](https://de.wikipedia.org/x)"),
                       "mehr unter <a href=\"https://de.wikipedia.org/x\">Grundgesetz</a>")
        let html = AnswerHTML.blocks(in: "## Zwischenstand\nText", sources: [])
        XCTAssertTrue(html.contains("<h3>Zwischenstand</h3>"))
    }

    func testATelephoneLinkKeepsItsDialTargetInTheExport() {
        XCTAssertEqual(AnswerHTML.inline("Ruf [030 1234567](tel:+49301234567) an."),
                       "Ruf <a href=\"tel:+49301234567\">030 1234567</a> an.")
    }

    func testListsSeparatedByBlankLinesStayOneList() {
        let html = AnswerHTML.blocks(in: "Meilensteine:\n\n- **508** – Chlodwig\n\n- **1958** – de Gaulle\n\nDanach.",
                                     sources: [])
        XCTAssertEqual(html.components(separatedBy: "<ul>").count - 1, 1)
        XCTAssertTrue(html.contains("<ul><li><strong>508</strong> – Chlodwig</li><li><strong>1958</strong> – de Gaulle</li></ul>"))
        XCTAssertTrue(html.contains("<p>Meilensteine:</p>"))
        XCTAssertTrue(html.contains("<p>Danach.</p>"))
    }

    func testMixedListKindsStillSplit() {
        let html = AnswerHTML.blocks(in: "- a\n\n1. b", sources: [])
        XCTAssertTrue(html.contains("<ul><li>a</li></ul>"))
        XCTAssertTrue(html.contains("<ol><li>b</li></ol>"))
    }

    func testOrderedListsBecomeOl() {
        let html = AnswerHTML.blocks(in: "1. erstes **eine** Zahl\n2. zweites\n\nAbsatz danach", sources: [])
        XCTAssertTrue(html.contains("<ol><li>erstes <strong>eine</strong> Zahl</li><li>zweites</li></ol>"))
        XCTAssertTrue(html.contains("<p>Absatz danach</p>"))
    }

    func testParenthesisListsWithADotLaterInTheLineBecomeOl() {
        let html = AnswerHTML.blocks(in: "1) Preis 3.50 Euro\n2) Siehe www.example.de", sources: [])
        XCTAssertTrue(html.contains("<ol><li>Preis 3.50 Euro</li><li>Siehe www.example.de</li></ol>"), html)
        XCTAssertTrue(AnswerHTML.blocks(in: "3.50 Euro kostet es", sources: []).hasPrefix("<p>"))
        XCTAssertTrue(AnswerHTML.blocks(in: "12", sources: []).hasPrefix("<p>"))
        XCTAssertTrue(AnswerHTML.blocks(in: "1.Kein Abstand", sources: []).hasPrefix("<p>"))
    }

    func testHostileModelTextIsEscaped() {
        let html = AnswerHTML.inline("<script>alert(&1)</script> **fett**")
        XCTAssertFalse(html.contains("<script"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("alert(&amp;1)"))
        XCTAssertTrue(html.contains("<strong>fett</strong>"))
    }

    func testLinkTargetCannotBreakOutOfTheHrefAttribute() {
        let html = AnswerHTML.inline("[X](https://a.test/\"/onmouseover/alert)")
        XCTAssertEqual(html, "<a href=\"https://a.test/&quot;/onmouseover/alert\">X</a>")
    }

    func testCodeSpansKeepTheirOwnMarkdownAndAreEscaped() {
        let html = AnswerHTML.inline("nutze `a < b **c**` bitte")
        XCTAssertTrue(html.contains("<code>a &lt; b **c**</code>"))
        XCTAssertFalse(html.contains("<strong>c</strong>"))
    }

    func testFootnoteReferencesLinkToTheSourceList() {
        let sources = [Fixtures.source("A", "https://a.test", "a.test"), Fixtures.source("B", "https://b.test", "b.test")]
        XCTAssertEqual(AnswerHTML.inline("Belegt [1] und [2] und [7].", sources: sources),
                       "Belegt [<a href=\"#quelle-1\">1</a>] und [<a href=\"#quelle-2\">2</a>] und [7].")
    }

    func testGroupedFootnoteReferencesLinkEverySourceNumber() {
        let sources = [Fixtures.source("A", "https://a.test", "a.test"),
                       Fixtures.source("B", "https://b.test", "b.test"),
                       Fixtures.source("C", "https://c.test", "c.test"),
                       Fixtures.source("D", "https://d.test", "d.test")]
        XCTAssertEqual(AnswerHTML.inline("Belegt [1, 3, 4] und [2; 9].", sources: sources),
                       "Belegt [<a href=\"#quelle-1\">1</a>, <a href=\"#quelle-3\">3</a>, "
                       + "<a href=\"#quelle-4\">4</a>] und [<a href=\"#quelle-2\">2</a>; 9].")
    }

    func testSourceListRendersTitlesAndSkipsUnsafeURLs() {
        let sources = [Fixtures.source("Statista", "https://statista.test/x", "statista.test"),
                       Fixtures.source("", "javascript:alert(1)", "evil.test")]
        let html = AnswerHTML.sourceList(sources: sources, heading: "Quellen")
        XCTAssertTrue(html.contains("<section class=\"quellen\"><h3>Quellen</h3><ol>"))
        XCTAssertTrue(html.contains("<li id=\"quelle-1\"><a href=\"https://statista.test/x\">Statista</a>"))
        XCTAssertTrue(html.contains("<li id=\"quelle-2\"><a href=\"#\">evil.test</a>"))
        XCTAssertFalse(html.contains("javascript:"))
    }

    func testDocumentCarriesLanguageStylesheetAndMeta() {
        L.apply(.de)
        let html = AnswerHTML.document(text: "Antwort **mit** Fett",
                                       sources: [Fixtures.source("A", "https://a.test", "a.test")],
                                       heading: "Quellen",
                                       title: "Was ist die Hauptstadt <von> Frankreich? & Co.",
                                       meta: AnswerHTML.metaLine(model: "qwen3.8-flash", elapsed: 22.24, time: "13:41"),
                                       language: L.lang.rawValue)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<html lang=\"de\">"))
        XCTAssertTrue(html.contains("<title>Was ist die Hauptstadt &lt;von&gt; Frankreich? &amp; Co.</title>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(html.contains("<strong>mit</strong>"))
        XCTAssertTrue(html.contains("qwen3.8-flash · 22.2 s · 13:41"))
        L.apply(.en)
    }

    func testMetaLineOmitsMissingPieces() {
        XCTAssertEqual(AnswerHTML.metaLine(model: nil, elapsed: nil, time: nil), "")
        XCTAssertEqual(AnswerHTML.metaLine(model: "m", elapsed: nil, time: nil), "m")
        XCTAssertEqual(AnswerHTML.metaLine(model: nil, elapsed: 3, time: "08:00"), "08:00")
    }
}
