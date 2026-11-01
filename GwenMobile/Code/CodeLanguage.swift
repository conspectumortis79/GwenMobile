import GwenMobileKit
import Foundation

enum CodeLanguage: String, CaseIterable, Codable, Equatable, Sendable {
    case html
    case css
    case javascript
    case typescript
    case json
    case markdown
    case yaml
    case sql
    case shell
    case python
    case swift
    case kotlin
    case java
    case c
    case cpp
    case csharp
    case go
    case rust
    case ruby
    case php
    case text

    static let toolValues: [String] = allCases.map(\.rawValue)

    private static let aliases: [String: CodeLanguage] = [
        "htm": .html, "html5": .html, "xhtml": .html, "webpage": .html, "website": .html,
        "js": .javascript, "jsx": .javascript, "node": .javascript, "nodejs": .javascript,
        "ts": .typescript, "tsx": .typescript,
        "md": .markdown, "yml": .yaml, "bash": .shell, "zsh": .shell, "sh": .shell,
        "console": .shell, "shell-session": .shell, "py": .python, "python3": .python,
        "kt": .kotlin, "c++": .cpp, "hpp": .cpp, "c#": .csharp, "cs": .csharp,
        "golang": .go, "rs": .rust, "rb": .ruby, "plaintext": .text, "txt": .text,
        "jsonc": .json, "json5": .json, "toml": .yaml, "ini": .text,
    ]

    private static let webPageMarkers: [String] = [
        "<!doctype html", "<html", "<head", "<body", "<main", "<section", "<style", "<script",
    ]

    var label: String {
        switch self {
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .yaml: return "YAML"
        case .sql: return "SQL"
        case .shell: return "Shell"
        case .python: return "Python"
        case .swift: return "Swift"
        case .kotlin: return "Kotlin"
        case .java: return "Java"
        case .c: return "C"
        case .cpp: return "C++"
        case .csharp: return "C#"
        case .go: return "Go"
        case .rust: return "Rust"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .text: return "Text"
        }
    }

    var fileExtension: String {
        switch self {
        case .javascript: return "js"
        case .typescript: return "ts"
        case .markdown: return "md"
        case .shell: return "sh"
        case .python: return "py"
        case .kotlin: return "kt"
        case .cpp: return "cpp"
        case .csharp: return "cs"
        case .rust: return "rs"
        case .ruby: return "rb"
        case .text: return "txt"
        default: return rawValue
        }
    }

    var fenceTag: String { self == .text ? "" : rawValue }

    var opensInBrowser: Bool { self == .html }

    init(toolValue: String?) {
        let wanted = CodeLanguage.normalized(toolValue)
        self = CodeLanguage(rawValue: wanted)
            ?? CodeLanguage.aliases[wanted]
            ?? CodeLanguage(rawValue: wanted.replacingOccurrences(of: "-", with: ""))
            ?? .text
    }

    static func sniffed(from code: String) -> CodeLanguage? {
        let head = normalizedHead(of: code)
        guard !head.isEmpty else { return nil }
        return webPageMarkers.contains { head.hasPrefix($0) } ? .html : nil
    }

    static func resolved(fenceLabel: String?, code: String) -> CodeLanguage {
        let labelled = CodeLanguage(toolValue: fenceLabel)
        guard labelled == .text else { return labelled }
        return sniffed(from: code) ?? .text
    }

    private static func normalized(_ raw: String?) -> String {
        (raw ?? "").trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedHead(of code: String) -> String {
        for line in code.split(separator: "\n", omittingEmptySubsequences: false).prefix(6) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
