#if DEBUG
@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation

struct FlowCase {
    let text: String
    let number: String?
    let words: [String]

    @MainActor
    static func run<Record>(_ cases: [FlowCase], in view: ChatView, report: SweepReport,
                            records: () -> [Record],
                            numberOf: (Record) -> DialNumber,
                            detail: (Bool, [Record], DialNumber?, String) -> String) async -> Int {
        var right = 0
        for (index, item) in cases.enumerated() {
            let before = records().count
            let answer = await view.ask(item.text, fresh: true)
            let produced = Array(records().dropFirst(before))
            let expected = item.number.flatMap(DialNumber.init)
            let numberFits = expected.map { produced.map(numberOf) == [$0] } ?? produced.isEmpty
            let reply = answer?.text ?? ""
            let folded = TextFolding.fold(reply)
            let wordsFit = item.words.allSatisfy { folded.contains(TextFolding.fold($0)) }
            let fits = numberFits && wordsFit
            right += fits ? 1 : 0
            report.add("FALL_\(index + 1)", detail(fits, produced, expected, reply))
        }
        return right
    }

    @MainActor
    static func runSentences(_ sentences: [String], in view: ChatView, report: SweepReport,
                             evaluate: (Int, String, ChatMessage?, Int) -> (Bool, String)) async -> Int {
        report.add("KONFIG", "faelle=\(sentences.count) schluessel=\(view.settings.isConfigured)")
        var right = 0
        for (index, sentence) in sentences.enumerated() {
            let started = ContinuousClock.now
            let answer = await view.ask(sentence, fresh: true)
            let (fits, line) = evaluate(index, sentence, answer, msOf(started.duration(to: .now)))
            right += fits ? 1 : 0
            report.add("FALL_\(index + 1)", line)
        }
        return right
    }

    static func infoFlag(for key: String) -> String {
        let flag = Bundle.main.object(forInfoDictionaryKey: key).map { "\($0)" } ?? "-"
        return "\(key)=\(flag.isEmpty ? "leer" : flag)"
    }
}
#endif
