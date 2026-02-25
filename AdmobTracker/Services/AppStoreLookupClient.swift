import Foundation

protocol AppStoreLookupClient {
    func fetchIconURL(appStoreId: String) async throws -> URL?
}

final class LiveAppStoreLookupClient: AppStoreLookupClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchIconURL(appStoreId: String) async throws -> URL? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreId)") else {
            return nil
        }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        guard let result = response.results?.first else { return nil }
        if let urlString = result.artworkUrl512 ?? result.artworkUrl100 ?? result.artworkUrl60 {
            return URL(string: urlString)
        }
        return nil
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]?
}

private struct AppStoreLookupResult: Decodable {
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl512: String?
}
