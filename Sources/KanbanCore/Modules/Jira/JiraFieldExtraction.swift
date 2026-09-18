import Foundation

/// Turning Jira's untyped `fields` object into something displayable — the Swift port of Hermes'
/// `extractCustomFields` / `renderCustomFieldValue` / `stringifyFieldValue` / `extractMeta`.
///
/// Jira field values come in half a dozen shapes (ADF documents, option objects, account references,
/// arrays, plain scalars). Every field is rendered in exactly **one** place: a rich-text field becomes
/// its own section (`customFields`), everything a flat line can express stays in the exhaustive
/// „Weitere Felder"-Liste (`extraFields`). Ohne diese Trennung stand dasselbe Feld doppelt da.
enum JiraFieldExtraction {
    /// Already surfaced under their own headings — the generic loops skip them.
    static let knownCustomFieldIDs: Set<String> = [
        "customfield_10058",  // Ausgangslage
        "customfield_10059",  // Erwartetes Ergebnis / Verhalten
        "customfield_10076",  // Akzeptanzkriterien
        "customfield_10077",  // Erweiterte Beschreibung
        "customfield_10016",  // Story Points (steht in meta)
    ]

    /// Own section, identity-bearing, or pure structure — never part of „Weitere Felder".
    ///
    /// Bewusst **nicht** gefiltert: Felder, die auch im Meta-Block stehen (Status, Priorität, …) und
    /// Jira-Buchhaltung (Rang, workratio). Die Liste ist als vollständiges Metadaten-Archiv gedacht,
    /// der Meta-Block ist die Bequemlichkeit obendrauf, nicht sein Ersatz.
    static let extraFieldsSkip: Set<String> = [
        "summary", "issuetype", "description",
        "customfield_10058", "customfield_10059", "customfield_10077", "customfield_10076",
        "reporter", "assignee", "creator", "watcher", "watches",
        "comment", "attachment", "subtasks", "issuelinks",
    ]

    // MARK: - Value rendering

    /// True when the value is (or contains) a Jira account reference. Solche Felder gehen über den
    /// Custom-Field-Pfad, nicht über `stringify` — dort stünde die rohe Mailadresse.
    static func isIdentityBearing(_ value: JSONValue) -> Bool {
        switch value {
        case .array(let items): return items.contains(where: isIdentityBearing)
        case .object(let object): return object["accountId"] != nil || object["emailAddress"] != nil
        default: return false
        }
    }

    /// Best-effort flattening of an arbitrary field value to a short display string; nil for
    /// anything empty or not meaningfully renderable, so the caller can skip it.
    static func stringify(_ value: JSONValue) -> String? {
        switch value {
        case .null:
            return nil
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .int(let number):
            return String(number)
        case .double(let number):
            return number == number.rounded() ? String(Int(number)) : String(number)
        case .bool(let flag):
            return String(flag)
        case .array(let items):
            let parts = items.compactMap(stringify)
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        case .object(let object):
            for key in ["value", "name", "displayName", "emailAddress"] {
                if let inner = object[key] { return stringify(inner) }
            }
            return nil
        }
    }

    /// Jedes ADF-Dokument unter `fields` — die Grundlage für den Smart-Link-Vorlauf, der **einmal**
    /// über das ganze Issue läuft statt einmal je Feld.
    static func adfDocuments(in fields: [String: JSONValue]) -> [JSONValue] {
        fields.keys.sorted().compactMap { key in
            guard let value = fields[key], value.value(at: ["type"])?.stringValue == "doc" else { return nil }
            return value
        }
    }

    /// Rich values for a custom field's own section: ADF becomes Markdown (and contributes images),
    /// an account reference its display name, an option its label.
    static func render(_ value: JSONValue, imageCounter: inout Int,
                       images: inout [ADFImage],
                       smartLinks: [String: SmartLinkTarget]? = nil) -> String? {
        switch value {
        case .null:
            return nil
        case .object(let object) where object["type"]?.stringValue == "doc" && object["content"] != nil:
            let result = ADFToMarkdown.convert(value, imageCounter: imageCounter, smartLinks: smartLinks)
            images.append(contentsOf: result.images)
            imageCounter += result.images.count
            let text = result.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        case .array(let items):
            var parts: [String] = []
            for item in items {
                if let text = render(item, imageCounter: &imageCounter, images: &images,
                                     smartLinks: smartLinks) {
                    parts.append(text)
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        case .object(let object):
            if object["accountId"] != nil || object["emailAddress"] != nil {
                return object["displayName"]?.stringValue ?? object["emailAddress"]?.stringValue
            }
            if let option = object["value"]?.stringValue { return option }
            if let name = object["name"]?.stringValue { return name }
            return nil
        default:
            return stringify(value)
        }
    }

    // MARK: - Field sweeps

    /// Every populated `customfield_*` that has no named section of its own **and** cannot be
    /// expressed as a flat line (i.e. rich text or an identity) — those get their own section.
    static func customFields(_ fields: [String: JSONValue], names: [String: String],
                             imageCounter: inout Int,
                             images: inout [ADFImage],
                             smartLinks: [String: SmartLinkTarget]? = nil) -> [JiraCustomField] {
        var result: [JiraCustomField] = []
        for key in fields.keys.sorted() {
            guard key.hasPrefix("customfield_"), !knownCustomFieldIDs.contains(key),
                  let value = fields[key], value != .null else { continue }
            guard isIdentityBearing(value) || stringify(value) == nil else { continue }
            guard let text = render(value, imageCounter: &imageCounter, images: &images,
                                    smartLinks: smartLinks) else { continue }
            result.append(JiraCustomField(id: key, name: names[key] ?? key, value: text))
        }
        return result
    }

    /// The exhaustive metadata list: everything not already rendered elsewhere, as `name: value`.
    static func extraFields(_ fields: [String: JSONValue],
                            names: [String: String]) -> [JiraExtraField] {
        var result: [JiraExtraField] = []
        for key in fields.keys.sorted() {
            guard !extraFieldsSkip.contains(key), let value = fields[key], value != .null,
                  !isIdentityBearing(value), let rendered = stringify(value) else { continue }
            result.append(JiraExtraField(id: key, name: names[key] ?? key, value: rendered))
        }
        return result
    }

    // MARK: - Meta block

    static func meta(_ fields: [String: JSONValue]) -> JiraIssueMeta {
        let timetracking = fields["timetracking"]?.objectValue ?? [:]

        func duration(_ formatted: String?, _ seconds: JSONValue?...) -> String? {
            if let formatted, !formatted.isEmpty { return formatted }
            for value in seconds {
                if let number = value?.intValue { return JiraDuration.format(number) }
            }
            return nil
        }

        let original = duration(timetracking["originalEstimate"]?.stringValue,
                                timetracking["originalEstimateSeconds"], fields["timeoriginalestimate"])
        let remaining = duration(timetracking["remainingEstimate"]?.stringValue,
                                 timetracking["remainingEstimateSeconds"], fields["timeestimate"])
        let spent = duration(timetracking["timeSpent"]?.stringValue,
                             timetracking["timeSpentSeconds"], fields["timespent"])
        let aggregateOriginal = JiraDuration.format(fields["aggregatetimeoriginalestimate"]?.intValue)
        let aggregateRemaining = JiraDuration.format(fields["aggregatetimeestimate"]?.intValue)
        let aggregateSpent = JiraDuration.format(fields["aggregatetimespent"]?.intValue)

        let parent = fields["parent"]?.objectValue.map {
            JiraSubtaskRef(key: $0["key"]?.stringValue ?? "",
                           summary: $0["fields"]?.value(at: ["summary"])?.stringValue)
        }

        return JiraIssueMeta(
            status: fields["status"]?.value(at: ["name"])?.stringValue,
            priority: fields["priority"]?.value(at: ["name"])?.stringValue,
            resolution: fields["resolution"]?.value(at: ["name"])?.stringValue,
            resolutionDate: fields["resolutiondate"]?.stringValue,
            storyPoints: fields["customfield_10016"]?.doubleValue,
            labels: namedList(fields["labels"]),
            components: namedList(fields["components"]),
            fixVersions: namedList(fields["fixVersions"]),
            affectedVersions: namedList(fields["versions"]),
            created: fields["created"]?.stringValue,
            updated: fields["updated"]?.stringValue,
            dueDate: fields["duedate"]?.stringValue,
            originalEstimate: original,
            remainingEstimate: remaining,
            timeSpent: spent,
            aggregateOriginalEstimate: aggregateOriginal == original ? nil : aggregateOriginal,
            aggregateRemainingEstimate: aggregateRemaining == remaining ? nil : aggregateRemaining,
            aggregateTimeSpent: aggregateSpent == spent ? nil : aggregateSpent,
            watchers: fields["watches"]?.value(at: ["watchCount"])?.intValue ?? 0,
            votes: fields["votes"]?.value(at: ["votes"])?.intValue ?? 0,
            parent: parent)
    }

    /// `["a", {name: "b"}]` → `["a", "b"]`.
    private static func namedList(_ value: JSONValue?) -> [String] {
        (value?.arrayValue ?? []).compactMap {
            $0.stringValue ?? $0.value(at: ["name"])?.stringValue
        }
    }

    // MARK: - Users, attachments, images

    static func user(_ value: JSONValue?) -> JiraUser? {
        guard let object = value?.objectValue else { return nil }
        let name = object["displayName"]?.stringValue ?? object["name"]?.stringValue
        let email = object["emailAddress"]?.stringValue
        guard name != nil || email != nil else { return nil }
        let avatars = object["avatarUrls"]?.objectValue
        return JiraUser(accountId: object["accountId"]?.stringValue ?? object["key"]?.stringValue,
                        displayName: name ?? email ?? "Unbekannt",
                        emailAddress: email,
                        avatarUrl: (avatars?["48x48"] ?? avatars?["32x32"])?.stringValue)
    }

    static func attachments(_ value: JSONValue?) -> [JiraAttachment] {
        (value?.arrayValue ?? []).compactMap { item in
            guard let filename = item.value(at: ["filename"])?.stringValue else { return nil }
            return JiraAttachment(id: item.value(at: ["id"])?.stringValue,
                                  filename: filename,
                                  mimeType: item.value(at: ["mimeType"])?.stringValue,
                                  size: item.value(at: ["size"])?.intValue,
                                  contentUrl: item.value(at: ["content"])?.stringValue,
                                  created: item.value(at: ["created"])?.stringValue)
        }
    }

    /// Matches the images found in the rich text against the attachments (by filename) and appends
    /// every attachment nothing pointed at — Jira shows those below the description, so they belong
    /// to the issue just as much.
    static func images(_ adfImages: [ADFImage], attachments: [JiraAttachment],
                       imageCounter: inout Int) -> [JiraIssueImage] {
        var result = adfImages.map { image in
            JiraIssueImage(id: image.id, originalName: image.originalName,
                           filename: image.filename, index: image.index,
                           url: attachments.first { $0.filename == image.originalName }?.contentUrl,
                           unreferenced: false)
        }
        let referenced = Set(adfImages.map(\.originalName))
        for attachment in attachments where !referenced.contains(attachment.filename) {
            result.append(JiraIssueImage(id: attachment.id, originalName: attachment.filename,
                                         filename: "\(imageCounter + 1)-\(attachment.filename)",
                                         index: imageCounter, url: attachment.contentUrl,
                                         unreferenced: true))
            imageCounter += 1
        }
        return result
    }
}

