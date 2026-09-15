import Foundation

/// Der Stand des Jira-Felds „Lösung" für ein Ticket.
public struct JiraSolution: Sendable, Equatable {
    /// Die Feld-Id auf dieser Instanz (z. B. `customfield_10052`) — pro Instanz und Projekt anders,
    /// deshalb aufgelöst statt hartkodiert.
    public let fieldId: String
    /// Der aktuelle Inhalt als Markdown (leer = Feld leer).
    public let markdown: String

    public var isEmpty: Bool { markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public init(fieldId: String, markdown: String) {
        self.fieldId = fieldId
        self.markdown = markdown
    }
}

extension JiraClient {
    /// Die Namen, unter denen das Feld auftreten darf. Aufgelöst wird über den **Edit-Screen** des
    /// Tickets (`/editmeta`) — dieselbe Auflösung wie in Hermes' `set-jira-solution`. Gegen eine
    /// feste Id wäre es Glück: `customfield_10052` gilt für diese Instanz, nicht als Naturgesetz,
    /// und der Screen entscheidet ausserdem, ob das Feld auf dem Vorgangstyp überhaupt beschreibbar
    /// ist.
    static let solutionFieldNames = ["lösung", "loesung", "solution"]

    /// Liest das Lösungsfeld: Id aus dem Edit-Screen, Inhalt aus dem Issue (ADF → Markdown, damit im
    /// Editor derselbe Text steht, den `solve-task` ins Task-File schreibt).
    ///
    /// nil heisst „das Ticket hat kein solches Feld" — dann bleibt der Knopf weg, statt beim Klick
    /// zu scheitern.
    /// `knownFieldId` überspringt den Edit-Screen-Aufruf. Der Aufrufer merkt die Id je Projekt: sie
    /// ist eine Eigenschaft der Instanz, und `editmeta` ist der teuerste Teil des Ladens — beim
    /// Durchklicken von Karten wäre das jedes Mal eine Anfrage mehr.
    public func solution(issueKey: String, baseUrl: String,
                         knownFieldId: String? = nil) async throws -> JiraSolution? {
        let resolved: String?
        if let knownFieldId { resolved = knownFieldId }
        else { resolved = try await solutionFieldId(issueKey: issueKey, baseUrl: baseUrl) }
        guard let fieldId = resolved else { return nil }
        let issue: JSONValue = try await http.getJSON(
            "\(baseUrl)/rest/api/3/issue/\(issueKey)?fields=\(fieldId)")
        let value = issue.value(at: ["fields", fieldId])
        let markdown: String
        if let value, value != .null {
            markdown = ADFToMarkdown.convert(value).markdown
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            markdown = ""
        }
        return JiraSolution(fieldId: fieldId, markdown: markdown)
    }

    /// Schreibt Markdown als ADF in das Feld. Leerer Text leert das Feld (`null`) — sonst stünde
    /// dort ein leeres Dokument, das Jira als Inhalt zählt.
    public func setSolution(issueKey: String, fieldId: String, markdown: String,
                            baseUrl: String) async throws {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any = trimmed.isEmpty
            ? NSNull()
            : try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                MarkdownToADF.convert(trimmed)))
        try await http.putJSON("\(baseUrl)/rest/api/3/issue/\(issueKey)",
                               body: ["fields": [fieldId: value]])
    }

    /// Die Feld-Id auf dem Edit-Screen dieses Tickets, oder nil.
    func solutionFieldId(issueKey: String, baseUrl: String) async throws -> String? {
        let meta: JSONValue = try await http.getJSON(
            "\(baseUrl)/rest/api/3/issue/\(issueKey)/editmeta")
        guard let fields = meta.value(at: ["fields"])?.objectValue else { return nil }
        for (id, field) in fields {
            let name = (field.value(at: ["name"])?.stringValue ?? "").lowercased()
            if Self.solutionFieldNames.contains(name) { return id }
        }
        return nil
    }
}
