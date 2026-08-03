import Foundation

/// Minimal client for the Hermes daemon's local HTTP bridge (`http://localhost:7891`).
///
/// The daemon proxies a URL fetch through the logged-in browser session (Chrome extension) — the
/// same `fetch` command Hermes uses internally (`fetchViaExtension`). We need this for GitLab
/// because the configured GitLab token is an AI/MCP token that GitLab rejects for the REST
/// merge-request API (403 insufficient_scope); the browser session, however, is authorized.
public struct HermesDaemon: Sendable {
    public static let baseURL = "http://localhost:7891"

    public enum DaemonError: Error, LocalizedError {
        case unreachable
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unreachable: return "Hermes-Daemon nicht erreichbar (localhost:7891)."
            case .failed(let m): return "Hermes-Daemon-Fehler: \(m)"
            }
        }
    }

    /// Fetches `url` through the daemon's `fetch` command (browser-session auth) and decodes the
    /// returned JSON payload as `T`.
    public static func fetchJSON<T: Decodable>(_ url: String, as type: T.Type) async throws -> T {
        guard let endpoint = URL(string: "\(baseURL)/command") else { throw DaemonError.unreachable }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "command": "fetch",
            "params": ["url": url, "responseType": "json"],
        ])

        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) }
        catch { throw DaemonError.unreachable }

        let envelope = try JSONDecoder().decode(DaemonResponse<T>.self, from: data)
        guard envelope.success, let payload = envelope.data else {
            throw DaemonError.failed(envelope.error ?? "unbekannt")
        }
        return payload
    }

    /// Whether the daemon answers its health check (extension connectivity not required).
    public static func isReachable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    private struct DaemonResponse<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
        let error: String?
    }
}
