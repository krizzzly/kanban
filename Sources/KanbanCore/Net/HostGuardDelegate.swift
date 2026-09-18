import Foundation

/// A URLSession task delegate that strips auth headers when a redirect leaves the configured
/// hosts — mirrors Hermes' host-guard so credentials never leak to e.g. S3 attachment redirects.
/// Several hosts are allowed because one module can span them (a Jira project with its own `baseUrl`).
public final class HostGuardDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>
    /// Obergrenze für die Umleitungskette, oder nil für die Voreinstellung von `URLSession`.
    /// Gebraucht wird sie dort, wo die Kette die Allowlist bewusst verlässt (Gravatar leitet auf
    /// `i1.wp.com` weiter): der Host-Guard kann dort nicht mehr begrenzen, die Zähllänge schon.
    private let maxRedirects: Int?
    private let count = Counter()

    public init(allowedHosts: Set<String>, maxRedirects: Int? = nil) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        self.maxRedirects = maxRedirects
    }

    public convenience init(allowedHost: String) {
        self.init(allowedHosts: [allowedHost])
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? {
        if let maxRedirects, count.next() > maxRedirects { return nil }
        guard let host = request.url?.host?.lowercased(), allowedHosts.contains(host) else {
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            stripped.setValue(nil, forHTTPHeaderField: "PRIVATE-TOKEN")
            return stripped
        }
        return request
    }

    /// Der Delegate wird von `URLSession` nebenläufig aufgerufen; der Zähler braucht deshalb eine
    /// eigene Sperre statt einer blossen `var`.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
    }
}

public enum APIError: Error, LocalizedError {
    case badURL(String)
    case http(Int)
    /// A non-2xx answer, with the API's own message where the body carries one.
    case api(module: String, status: Int, message: String?)
    case decode(String)
    /// The auth header would have gone to a host the module is not configured for — refused before
    /// the request leaves the process.
    case forbiddenHost(module: String, host: String)
    /// A paginated endpoint kept handing out full pages; better to say so than to return a silently
    /// truncated list.
    case tooManyPages(module: String, pages: Int)
    /// Die Antwort war grösser als der Aufrufer zugelassen hat.
    case tooLarge(module: String, bytes: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .badURL(let u): return "Ungültige URL: \(u)"
        case .http(let code): return "HTTP \(code)"
        case .api(let module, let status, let message):
            return message ?? "\(module) antwortete HTTP \(status)"
        case .decode(let m): return "Antwort konnte nicht gelesen werden: \(m)"
        case .forbiddenHost(let module, let host):
            return "\(module): Auth-Header nicht an \(host) gesendet — Host steht nicht in der Config."
        case .tooManyPages(let module, let pages):
            return "\(module): mehr als \(pages) Seiten — Abbruch statt unvollständiger Liste."
        case .tooLarge(let module, let bytes, let limit):
            return "\(module): Antwort zu gross (\(bytes) Bytes, erlaubt \(limit))"
        }
    }
}

/// Pulls the human-readable reason out of an error body: Jira's
/// `{"errorMessages":[…],"errors":{…}}` and GitLab's `{"message": …}` / `{"error": …}`.
enum APIErrorBody {
    static func message(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let messages = json["errorMessages"] as? [String], let first = messages.first { return first }
        if let errors = json["errors"] as? [String: Any], let first = errors.values.first as? String {
            return first
        }
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        return nil
    }
}
