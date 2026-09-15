import Foundation

/// Per-module HTTP client — the Swift twin of Hermes' `lib/http.js`, auf **einen** Transport
/// eingedampft: direkte Anfrage mit dem API-Token des Moduls.
///
/// Hermes kennt daneben ein `extension`-Backend (Anfrage durch die Browser-Session eines Daemons,
/// für ein Token ohne REST-Scope) und macht es sogar zum Default. Kanban nicht: die App soll ohne
/// Zusatzsoftware laufen, und mit einem `glpat`-Token braucht es den Umweg nicht.
///
/// Sicherheit wie in Hermes, an einer Stelle strenger: der Auth-Header geht nur an Hosts, für die das
/// Modul konfiguriert ist, und das wird **vor** der Anfrage geprüft — nicht erst beim Redirect. Ein
/// Redirect, der die Hosts verlässt, verliert ihn (`HostGuardDelegate`, z. B. Jira-Attachment → S3).
/// Mehrere Hosts sind erlaubt, weil ein Jira-Projekt eine eigene `baseUrl` haben darf (`zvmsupport`).
public struct ModuleHTTPClient: Sendable {
    /// Nur für Fehlermeldungen („jira: …") — nie Teil einer Anfrage.
    public let module: String
    private let authHeaders: [String: String]
    private let allowedHosts: Set<String>

    public init(module: String, baseUrls: [String], authHeaders: [String: String]) {
        self.module = module
        self.authHeaders = authHeaders
        self.allowedHosts = Set(baseUrls.compactMap { URL(string: $0)?.host?.lowercased() })
    }

    // MARK: - Reading

    public func getJSON<T: Decodable>(_ url: String) async throws -> T {
        let data = try await getData(url)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decode(error.localizedDescription) }
    }

    public func getData(_ url: String) async throws -> Data {
        try await request(url, method: "GET", body: nil)
    }

    public func getText(_ url: String) async throws -> String {
        String(decoding: try await getData(url), as: UTF8.self)
    }

    /// Binary payloads (Jira attachments).
    public func getBinary(_ url: String) async throws -> (data: Data, contentType: String?) {
        let (data, response) = try await perform(url, method: "GET", body: nil, accept: "*/*")
        return (data, response.value(forHTTPHeaderField: "Content-Type"))
    }

    /// Walks a paginated list endpoint (`per_page`/`page`) until a short page arrives — GitLab's
    /// scheme, mirrored from Hermes' `fetchAllPages`. `maxPages` is a runaway guard, not a limit
    /// anyone should hit; it errors instead of silently returning a truncated list.
    public func pagedJSON<T: Decodable>(_ url: String, perPage: Int = 100,
                                        maxPages: Int = 100) async throws -> [T] {
        let separator = url.contains("?") ? "&" : "?"
        var all: [T] = []
        for page in 1...maxPages {
            let batch: [T] = try await getJSON("\(url)\(separator)per_page=\(perPage)&page=\(page)")
            all.append(contentsOf: batch)
            if batch.count < perPage { return all }
        }
        throw APIError.tooManyPages(module: module, pages: maxPages)
    }

    // MARK: - Writing

    /// POST with a JSON body; returns the raw response (empty on 204). A non-2xx carries the API's
    /// own message where it has one — a rejected Jira worklog should say why.
    @discardableResult
    public func postJSON(_ url: String, body: [String: Any]) async throws -> Data {
        try await request(url, method: "POST",
                          body: try JSONSerialization.data(withJSONObject: body))
    }

    public func postJSON<T: Decodable>(_ url: String, body: [String: Any], as type: T.Type) async throws -> T {
        let data = try await postJSON(url, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decode(error.localizedDescription) }
    }

    /// PUT with a JSON body — Jiras Weg, ein Feld eines bestehenden Issues zu ändern
    /// (`PUT /rest/api/3/issue/<KEY>`). Antwortet mit 204 und leerem Body.
    @discardableResult
    public func putJSON(_ url: String, body: [String: Any]) async throws -> Data {
        try await request(url, method: "PUT",
                          body: try JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - Transport

    private func request(_ url: String, method: String, body: Data?) async throws -> Data {
        try await perform(url, method: method, body: body, accept: "application/json").0
    }

    /// Der Host-Guard, als eigene Funktion: er entscheidet **vor** jedem Netzverkehr und ist damit
    /// ohne Netz prüfbar.
    func guarded(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            throw APIError.badURL(urlString)
        }
        guard allowedHosts.contains(host) else {
            throw APIError.forbiddenHost(module: module, host: host)
        }
        return url
    }

    private func perform(_ urlString: String, method: String, body: Data?,
                         accept: String) async throws -> (Data, HTTPURLResponse) {
        let url = try guarded(urlString)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (key, value) in authHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = body

        let delegate = HostGuardDelegate(allowedHosts: allowedHosts)
        let (data, response) = try await URLSession.shared.data(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.api(module: module, status: http.statusCode,
                               message: APIErrorBody.message(in: data))
        }
        return (data, http)
    }
}

// MARK: - Module factories

public extension ModuleHTTPClient {
    /// Jira: Basic auth over every host the config mentions — the default one plus any project that
    /// overrides `baseUrl`.
    static func jira(email: String, apiToken: String, baseUrls: [String]) -> ModuleHTTPClient {
        let credentials = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        return ModuleHTTPClient(module: "jira", baseUrls: baseUrls,
                                authHeaders: ["Authorization": "Basic \(credentials)"])
    }

    static func gitlab(baseUrl: String, apiToken: String) -> ModuleHTTPClient {
        ModuleHTTPClient(module: "gitlab", baseUrls: [baseUrl],
                         authHeaders: ["PRIVATE-TOKEN": apiToken])
    }
}
