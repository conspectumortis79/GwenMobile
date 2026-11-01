@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit
import SwiftUI
import UIKit

enum SourceChip {
    static let nameFontSize: CGFloat = 11
    static let maxNameWidth: CGFloat = 38
    static let markSize: CGFloat = 16
    static let rowSpacing: CGFloat = 5
    static let insets = EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 7)

    static func shortName(_ domain: String) -> String {
        let root = WebSearch.root(ofDomain: domain)
        return root.split(separator: ".").first.map(String.init) ?? domain
    }

    static func needsCut(_ name: String, fontSize: CGFloat = nameFontSize) -> Bool {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        return (name as NSString).size(withAttributes: [.font: font]).width > maxNameWidth
    }

    static func tint(_ domain: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in domain.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.75)
    }
}

struct SourceChipLabel: View {
    let number: Int
    let domain: String
    var flagged: Bool = false
    @ScaledMetric var nameSize: CGFloat = SourceChip.nameFontSize

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: String(number))
                .scaledFont(9, weight: .heavy)
                .foregroundStyle(.white)
                .frame(width: SourceChip.markSize, height: SourceChip.markSize)
                .background(Circle().fill(SourceChip.tint(domain)))
            name
            if flagged {
                Image(systemName: "exclamationmark.triangle.fill")
                    .scaledFont(9)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var name: some View {
        let short = SourceChip.shortName(domain)
        let text = Text(verbatim: short)
            .font(.system(size: nameSize, weight: .semibold))
            .lineLimit(1)
        if SourceChip.needsCut(short, fontSize: nameSize) {
            text.truncationMode(.tail)
                .frame(width: SourceChip.maxNameWidth, alignment: .leading)
        } else {
            text.fixedSize()
        }
    }
}
