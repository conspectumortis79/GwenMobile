#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

struct MacSelectableAnswerText: UIViewRepresentable {
    let attributed: AttributedString
    let textColor: UIColor
    let onOpen: (URL) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        view.textContainer.lineFragmentPadding = 0
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = textColor
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onOpen = onOpen
        view.textColor = textColor
        view.attributedText = Self.makeAttributed(attributed, textColor: textColor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let maxWidth = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let unlimited = UIView.layoutFittingExpandedSize
        let natural = uiView.sizeThatFits(CGSize(width: unlimited.width, height: unlimited.height))
        let width = min(maxWidth, natural.width)
        uiView.frame.size.width = width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: unlimited.height))
        return CGSize(width: width, height: fitted.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpen: (URL) -> Bool

        init(onOpen: @escaping (URL) -> Bool) {
            self.onOpen = onOpen
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            return UIAction { [weak self] _ in _ = self?.onOpen(url) }
        }
    }

    static func makeAttributed(_ attributed: AttributedString, textColor: UIColor) -> NSAttributedString {
        let base = UIFont.preferredFont(forTextStyle: .body)
        let output = NSMutableAttributedString()
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            guard !text.isEmpty else { continue }
            let attributes = run.attributes
            var font = base
            if let intent = attributes[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] {
                if intent.contains(.code) {
                    font = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
                }
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    font = UIFont(descriptor: descriptor, size: base.pointSize)
                }
            }
            let link = attributes[AttributeScopes.FoundationAttributes.LinkAttribute.self]
            var values: [NSAttributedString.Key: Any] = [.font: font]
            if let color = attributes[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] {
                values[.foregroundColor] = UIColor(color)
            } else if link != nil {
                values[.foregroundColor] = UIColor.systemBlue
            } else {
                values[.foregroundColor] = textColor
            }
            if let background = attributes[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] {
                values[.backgroundColor] = UIColor(background)
            }
            if let link {
                values[.link] = link
                if link.scheme?.lowercased() == "tel" {
                    values[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            output.append(NSAttributedString(string: text, attributes: values))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        output.addAttribute(.paragraphStyle, value: paragraph,
                            range: NSRange(location: 0, length: output.length))
        return output
    }
}
#endif
