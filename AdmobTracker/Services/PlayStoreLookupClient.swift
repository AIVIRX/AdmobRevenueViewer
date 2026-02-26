import Foundation

protocol PlayStoreLookupClient {
    func fetchIconURL(packageName: String) async throws -> URL?
}

final class LivePlayStoreLookupClient: PlayStoreLookupClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIconURL(packageName: String) async throws -> URL? {
        guard let url = URL(string: "https://play.google.com/store/apps/details?id=\(packageName)&hl=en&gl=US") else {
            return nil
        }
        let (data, _) = try await session.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        if let url = extractMetaContent(html: html, property: "og:image") {
            return url
        }
        if let url = extractMetaContent(html: html, property: "image") {
            return url
        }
        return nil
    }

    private func extractMetaContent(html: String, property: String) -> URL? {
        let pattern = "property=\\\"og:image\\\"\\s*content=\\\"([^\\\"]+)\\\""
        let itemPropPattern = "itemprop=\\\"image\\\"\\s*content=\\\"([^\\\"]+)\\\""
        let regexPattern = property == "og:image" ? pattern : itemPropPattern
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else { return nil }
        guard let urlRange = Range(match.range(at: 1), in: html) else { return nil }
        let raw = String(html[urlRange])
        let unescaped = raw.replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: unescaped)
    }
}
