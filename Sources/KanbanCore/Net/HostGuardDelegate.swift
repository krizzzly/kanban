import Foundation

/// A URLSession task delegate that strips auth headers when a redirect leaves the
/// configured host — mirrors Hermes' host-guard so credentials never leak to e.g.
/// S3 attachment redirects.
public final class HostGuardDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHost: String

    public init(allowedHost: String) {
        self.allowedHost = allowedHost.lowercased()
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? {
        guard let host = request.url?.host?.lowercased(), host == allowedHost else {
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            stripped.setValue(nil, forHTTPHeaderField: "PRIVATE-TOKEN")
            return stripped
        }
        return request
    }
}

public enum APIError: Error, LocalizedError {
    case badURL(String)
    case http(Int)
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .badURL(let u): return "Ungültige URL: \(u)"
        case .http(let code): return "HTTP \(code)"
        case .decode(let m): return "Antwort konnte nicht gelesen werden: \(m)"
        }
    }
}

enum HTTPHelper {
    /// Performs a GET with the given headers, host-guarded, and decodes the JSON body.
    static func getJSON<T: Decodable>(_ urlString: String,
                                      headers: [String: String]) async throws -> T {
        let data = try await getData(urlString, headers: headers)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decode(error.localizedDescription) }
    }

    static func getData(_ urlString: String, headers: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString), let host = url.host else {
            throw APIError.badURL(urlString)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let delegate = HostGuardDelegate(allowedHost: host)
        let (data, resp) = try await URLSession.shared.data(for: req, delegate: delegate)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return data
    }
}
