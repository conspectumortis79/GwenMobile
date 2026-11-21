import XCTest
import GwenMobileKit

final class TextUtilitiesTests: GwenTestCase {
    func testTrimmedDropsOuterWhitespaceForStringAndSubstring() {
        XCTAssertEqual("  hallo \n".trimmed, "hallo")
        let whole = " a b "
        let part = whole.dropFirst().dropLast()
        XCTAssertEqual(part.trimmed, "a b")
        XCTAssertEqual("".trimmed, "")
        XCTAssertEqual("\n\t ".trimmed, "")
    }

    func testNilIfEmptyKeepsNonEmptyText() {
        XCTAssertNil("".nilIfEmpty)
        XCTAssertEqual(" x ".nilIfEmpty, " x ")
    }

    func testHTMLPlainReusesTheCompiledBlockPattern() {
        XCTAssertEqual(HTMLText.plain("<nav>weg</nav><p>bleibt</p>", hiding: HTMLText.pageNoiseBlocks),
                       "bleibt")
        XCTAssertEqual(HTMLText.plain("<footer>weg</footer><b>da</b>", hiding: HTMLText.pageNoiseBlocks),
                       "da")
        XCTAssertEqual(HTMLText.plain("<i>nur text</i>", hiding: HTMLText.invisibleBlocks), "nur text")
        XCTAssertEqual(HTMLText.plain("<u>alles bleibt</u>", hiding: []), "alles bleibt")
    }

    func testHTMLPlainKeepsTagsThatOnlyStartLikeANoiseTag() {
        XCTAssertEqual(HTMLText.plain("<navbar>Hallo</navbar><nav>Weg</nav>", hiding: HTMLText.pageNoiseBlocks),
                       "Hallo")
    }

    func testHTMLPlainDecodesEntitiesInsteadOfDroppingThem() {
        XCTAssertEqual(HTMLText.plain("<p>Preis: 19,99&nbsp;&euro;</p>", hiding: []), "Preis: 19,99\u{00A0}€")
        XCTAssertEqual(HTMLText.plain("<p>M&uuml;ller &amp; S&ouml;hne</p>", hiding: []), "Müller & Söhne")
        XCTAssertEqual(HTMLText.plain("<p>&lt;b&gt;bleibt&lt;/b&gt;</p>", hiding: []), "<b>bleibt</b>")
        XCTAssertEqual(HTMLText.plain("a&nbsp;&nbsp;&nbsp;b", hiding: []), "a b")
    }

    func testNamedEntitiesAreDecodedCaseSensitively() {
        XCTAssertEqual(HTMLEntities.decoded("&Auml;&auml;&szlig;&euro;&apos;"), "Ääß€'")
        XCTAssertEqual(HTMLEntities.decoded("&unbekannt; &AUML;"), "&unbekannt; &AUML;")
        XCTAssertEqual(HTMLEntities.decoded("AT&T und Q&A"), "AT&T und Q&A")
        XCTAssertEqual(HTMLEntities.decoded("ohne Zeichen"), "ohne Zeichen")
    }

    func testNumericEntitiesAreDecoded() {
        XCTAssertEqual(HTMLEntities.decoded("&#8364; &#x20AC; &#X20ac; &#39;"), "€ € € '")
        XCTAssertEqual(HTMLEntities.decoded("&#128;&#150;&#129;"), "€–\u{81}")
        XCTAssertEqual(HTMLEntities.decoded("&#0;&#xD800;&#x110000;&#9999999;"),
                       "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}")
    }

    func testDoubleEscapedEntitiesAreDecodedOnlyOnce() {
        XCTAssertEqual(HTMLEntities.decoded("&amp;quot;"), "&quot;")
        XCTAssertEqual(HTMLEntities.decoded("&amp;amp;"), "&amp;")
        XCTAssertEqual(HTMLEntities.decoded("a &amp; b &quot;c&#39;d"), "a & b \"c'd")
        XCTAssertEqual(HTMLEntities.decoded("x&nbsp;y&ndash;z&mdash;u&bdquo;v"), "x\u{00A0}y–z—u„v")
    }

    func testUnquotedStripsMatchingOuterQuotesAndFnv1aMatchesStandardOffset() {
        XCTAssertEqual(TextLine.unquoted("  \"Hallo\"  "), "Hallo")
        XCTAssertEqual(TextLine.unquoted("«Bonjour»"), "Bonjour")
        XCTAssertEqual(TextLine.unquoted("„Welt“"), "Welt")
        XCTAssertEqual(TextLine.unquoted("55\" TV"), "55\" TV")
        XCTAssertEqual(TextFolding.fnv1a64(""), 14_695_981_039_346_656_037)
        XCTAssertEqual(TextFolding.fnv1a64("a"), 0xAF63_DC4C_8601_EC8C)
    }

    func testRegexCacheFirstMatchExtractsGroupOneSafely() {
        let cache = RegexCache(options: [.caseInsensitive])
        XCTAssertEqual(cache.firstMatch(in: "<title>Hallo</title>", pattern: "<title>([^<]+)</title>"), "Hallo")
        XCTAssertNil(cache.firstMatch(in: "ohne", pattern: "<title>([^<]+)</title>"))
        XCTAssertNil(cache.firstMatch(in: "abc", pattern: "(?:abc)(def)?"))
        XCTAssertNil(RegexCache.firstMatch(in: "abc", regex: nil))
    }

    func testTruncatedStringListRequiresKeyColonArray() {
        XCTAssertEqual(TruncatedStringList.strings(under: "wishes",
                                                   in: #"{"note":"wishes","other":["falsch"]}"#), [])
        XCTAssertEqual(TruncatedStringList.strings(under: "wishes",
                                                   in: #"{"wishes":null,"other":["falsch"]}"#), [])
        XCTAssertEqual(TruncatedStringList.strings(under: "wishes",
                                                   in: #"{"note":"wishes","wishes":["eins","zwei""#),
                       ["eins", "zwei"])
    }
}
