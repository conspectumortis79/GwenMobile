import XCTest
@testable import GwenMobile

final class ChartIntentTests: XCTestCase {
    func testStatisticsToChartInGermanIsDetected() {
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("such im internet nach den einwohnerzahlen und stell sie als diagramm dar"))
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("mach eine grafik über die umsatzentwicklung der letzten jahre"))
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("visualisiere die prozentualen anteile der parteien"))
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("zeig mir die temperaturen als liniendiagramm"))
    }

    func testStatisticsToChartInEnglishIsDetected() {
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("search the web for the latest unemployment rates and plot them"))
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("create a bar chart of the population figures"))
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("show the revenue data as a pie chart"))
    }

    func testPlainQuestionsStayInChat() {
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("was sind statistiken?"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("wie hat sich die bevölkerung entwickelt?"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("erklär mir das diagramm im kapitel 3"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("wie spät ist es?"))
    }

    func testExplicitRejectionsAreRespected() {
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("gib die zahlen nur als text, kein diagramm"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("die statistiken ohne grafik und ohne diagramm"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("answer in text, no chart please"))
    }

    func testPictureWishesWithoutDataAreNotCharts() {
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("erzeuge ein bild von einem drachen"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("male eine grafik mit bunten tieren"))
    }

    func testQuestionsAboutAnExistingChartStayInChat() {
        XCTAssertFalse(ChartIntent.looksLikeChartRequest(
            "ich will wissen, woher du die statistik für österreich hast, die du in dem diagramm eingetragen hast"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest(
            "weißt du noch, welche werte du eingetragen hast im diagramm? bitte zeige sie mir"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("woher hast du die zahlen für das diagramm?"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("zeig mir die statistik, die du im diagramm genutzt hast"))
        XCTAssertFalse(ChartIntent.looksLikeChartRequest("was steht in der grafik über die arbeitslosenquote"))
    }

    func testRenewalOfAnExistingChartIsStillAChart() {
        XCTAssertTrue(ChartIntent.looksLikeChartRequest("mach das diagramm bitte neu mit den werten von 2025"))
        XCTAssertTrue(ChartIntent.looksLikeChartRequest(
            "erstelle ein diagramm aus den zahlen, die du im diagramm gezeigt hast"))
    }

    func testExistingVisualReferenceIsSeparatelyVisible() {
        XCTAssertTrue(ChartIntent.refersToExistingVisual("die du in dem diagramm eingetragen hast"))
        XCTAssertFalse(ChartIntent.refersToExistingVisual("mach ein diagramm daraus"))
    }

    func testWebDataWishIsSeparatelyVisible() {
        XCTAssertTrue(ChartIntent.wantsWebData("hol die zahlen aus dem internet und mach ein diagramm"))
        XCTAssertFalse(ChartIntent.wantsWebData("stell die zahlen aus meiner tabelle als diagramm dar"))
    }
}
