import GwenMobileKit
import Foundation
import ImageIO

protocol RemoteImageFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

protocol GalleryStoring: Sendable {
    func storeGalleryPicture(_ data: Data) -> String?
}

extension MediaStore: GalleryStoring {
    func storeGalleryPicture(_ data: Data) -> String? { storeImageData(data) }
}

enum ImageBytes {
    static func isPicture(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}

enum ImageDownload {
    static func data(from url: URL, userAgent: String?, accept: String?,
                     timeout: TimeInterval) async throws -> Data {
        guard url.scheme == "https", url.host != nil,
              !(await URLSafety.isLocalOrPrivateResolved(url)) else {
            throw APIError(message: L.t("pictures_insecure"))
        }
        var request = URLRequest(url: url)
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        request.timeoutInterval = timeout
        let (data, response) = try await HTTP.data(request)
        try HTTP.ensureSuccess(response)
        guard !(await URLSafety.isLocalOrPrivateResolved(response.url)) else {
            throw APIError(message: L.t("pictures_insecure"))
        }
        guard ImageBytes.isPicture(data) else {
            throw APIError(message: L.t("pictures_not_a_picture"))
        }
        return data
    }
}

struct HTTPPictureFetching: RemoteImageFetching {
    func data(from url: URL) async throws -> Data {
        try await ImageDownload.data(from: url, userAgent: WebSearch.searchUA,
                                     accept: "image/*,*/*;q=0.8", timeout: APITimeout.pictureRequest)
    }
}

extension HTTPPictureFetching {
    static func secureURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil,
              !URLSafety.isLocalOrPrivate(url) else { return nil }
        return url
    }
}
