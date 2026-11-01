import Foundation

enum HuggingFaceHub {
    static let modelsAPI = "https://huggingface.co/api/models"
    static let revision = "main"
    static let fileSuffixes = [".safetensors", ".json", ".jinja"]

    static func escapedPath(_ path: String) -> String {
        path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
    }

    static func detailURL(for repo: String) -> URL? {
        URL(string: "\(modelsAPI)/\(escapedPath(repo))?blobs=true")
    }

    static func fileURL(repo: String, path: String) -> URL? {
        URL(string: "https://huggingface.co/\(escapedPath(repo))/resolve/\(revision)/\(escapedPath(path))")
    }

    static func isModelFile(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasSuffix("/"), !path.hasPrefix(".") else { return false }
        guard !path.lowercased().hasPrefix("readme") else { return false }
        return fileSuffixes.contains { path.hasSuffix($0) }
    }
}
