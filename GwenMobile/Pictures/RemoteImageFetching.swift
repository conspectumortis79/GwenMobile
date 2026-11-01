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

struct HTTPPictureFetching: RemoteImageFetching {
    func data(from url: URL) async throws -> Data {
        guard url.scheme == "https", url.host != nil else { throw APIError(message: L.t("pictures_insecure")) }
        var request = URLRequest(url: url)
        request.setValue(WebSearch.searchUA, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = APITimeout.pictureRequest
        let (bytes, response) = try await HTTP.data(request)
        try HTTP.ensureSuccess(response)
        guard ImageBytes.isPicture(bytes) else { throw APIError(message: L.t("pictures_not_a_picture")) }
        return bytes
    }
}

extension HTTPPictureFetching {
    static func secureURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
