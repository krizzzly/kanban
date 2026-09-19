import Foundation

public struct WorkflowResolution: Sendable, Hashable {
    public let column: KanbanColumn
    public let badges: [CardBadge]

    public init(column: KanbanColumn, badges: [CardBadge]) {
        self.column = column
        self.badges = badges
    }
}

/// The derived-status precedence engine. Pure function, fully unit-testable.
///
/// Precedence (first match wins):
///   0. „wieder aufgemacht" — Jira führt das Ticket ausdrücklich als **nicht** erledigt und es gibt
///                        einen offenen MR, der neuer ist als jeder gemergte (`isReopened`). Dann
///                        fallen 1 und 2 aus: weder der gemergte MR noch ein altes ✅ im Task-File
///                        halten die Karte in Done fest.
///   1. Done            — the Jira status is Erledigt/Geschlossen, or a matching MR is merged
///   2. Done            — task-file `### Status` == ✅ Done (user-set final; wins over an open MR)
///   3. Review          — a matching MR is opened
///   4. marker column   — task-file marker decides the *work* stage: 🔴 Offen → Offen ·
///                        🟡 In Arbeit / 🟢 Abgeschlossen → In Bearbeitung · 🔵 Review → Review.
///                        ("Abgeschlossen" = Claude finished implementing; stays In Bearbeitung —
///                        it is NOT the final Done.) **⏸️ Hold has no column** (`marker.column` is
///                        nil) and falls through to the artifact rules below: a pause says the work
///                        rests, not how far it got.
///   5. In Bearbeitung  — no marker but a matching worktree exists (work has started)
///   6. Offen           — no marker but a task file exists
///   7. In Bearbeitung  — nichts davon, aber ein **offener MR**: daran wird gearbeitet. Trägt die
///                        Karte ohne Ticketnummer (freier Modus, `branch`), deren MR noch Draft
///                        ist — sie fiele sonst nach „Sprint", eine Spalte, die es dort nicht gibt.
///   8. Offen           — nothing local yet, but the ticket is **assigned to me** in Jira
///                        (`isAssignedToMe`): verantwortlich heisst offen, nicht „irgendwo im Sprint".
///   9. Sprint          — otherwise
///
/// Ein Ticket **ohne Nummer** (`branch` gesetzt) wird über seinen Branch statt über den Key erkannt
/// — `!130` steht in keinem Branchnamen (siehe `TicketMatching.matches`).
///
/// The full granular marker is also shown as a coloured dot on the card (coloured by the matching
/// column accent).
public enum WorkflowStatus {
    public static func resolve(ticketKey: String,
                               hasTaskFile: Bool,
                               statusMarker: TaskStatusMarker?,
                               worktree: Worktree?,
                               mergeRequests: [MergeRequestRef],
                               jiraState: JiraDoneState = .unknown,
                               isAssignedToMe: Bool = false,
                               branch: String? = nil) -> WorkflowResolution {
        let matching = mergeRequests.filter {
            TicketMatching.matches($0, ticketKey: ticketKey, branch: branch)
        }
        let merged = matching.filter { $0.state == "merged" }
        let opened = matching.filter { $0.state == "opened" }
        // A draft MR is opened but not ready for review, so it must not drive the Review column.
        let review = opened.filter { !$0.draft }
        // Das Ticket ist nach einem „fertig" wieder aufgemacht worden — dann zählen die aktuellen
        // Artefakte, nicht die alten (siehe `isReopened`).
        let reopened = isReopened(jiraState: jiraState, merged: merged, opened: opened)

        // Badges are independent of the column — they explain *why* the card sits where it does.
        var badges: [CardBadge] = []
        if hasTaskFile { badges.append(.file) }
        if worktree != nil { badges.append(.worktree) }
        // Prefer a merged MR for the badge, else the newest opened one (highest iid as proxy) — bei
        // einem wieder aufgemachten Ticket umgekehrt, dort interessiert der MR, der jetzt läuft. A draft
        // badge (🚧) makes it visible why a card with an MR is still In Bearbeitung, not in Review.
        let newestMerged = merged.max(by: { $0.iid < $1.iid })
        let newestOpened = opened.max(by: { $0.iid < $1.iid })
        if let mr = reopened ? (newestOpened ?? newestMerged) : (newestMerged ?? newestOpened) {
            badges.append(.mergeRequest(iid: mr.iid, draft: mr.state == "opened" && mr.draft))
        }

        let column: KanbanColumn
        if jiraState == .done {
            column = .done                   // Jira status = Erledigt/Geschlossen
        } else if !merged.isEmpty && !reopened {
            column = .done                   // merged MR — unless the work has been reopened
        } else if statusMarker == .done && !reopened {
            column = .done                   // ✅ user-set final Done wins over an open MR
        } else if !review.isEmpty {
            column = .review                 // a non-draft opened MR
        } else if let marker = statusMarker, !(reopened && marker == .done),
                  let markerColumn = marker.column {
            column = markerColumn            // 🔴 Offen · 🟡/🟢 In Bearbeitung · 🔵 Review
                                             // (das veraltete ✅ wird beim Wiederaufmachen übergangen;
                                             //  ⏸️ Hold hat keine Spalte → fällt auf die Artefakte durch)
        } else if worktree != nil {
            column = .inBearbeitung          // work has started (a worktree exists)
        } else if hasTaskFile {
            column = .offen
        } else if !opened.isEmpty {
            // Ein offener MR, sonst nichts: daran **wird** gearbeitet. „Sprint" heisst „eingeplant,
            // niemand hat es angefasst" — mit einem offenen Merge Request ist das keine Beschreibung
            // mehr, genauso wenig wie bei einem zugewiesenen Ticket eine Zeile weiter unten.
            //
            // Ohne diese Stufe verschwindet eine Karte **ganz**: ein Ticket ohne Nummer entsteht nur
            // aus einem offenen MR, und ist der ein Draft (also nicht review-reif), fiel es bis
            // hierher durch — nach „Sprint", eine Spalte, die es im freien Modus gar nicht gibt.
            column = .inBearbeitung
        } else if isAssignedToMe {
            // Zugewiesen heisst verantwortlich: das Ticket ist meins, auch wenn lokal noch nichts
            // liegt. „Sprint" heisst „in Jira eingeplant, niemand hat es angefasst" — sobald es
            // jemandem gehört, ist das keine Beschreibung mehr.
            column = .offen
        } else {
            column = .sprint
        }

        return WorkflowResolution(column: column, badges: badges)
    }

    /// The ticket's most relevant GitLab MR (newest opened, else newest merged) — the one whose
    /// branch and URL are synced into the task file. nil if no MR matches.
    public static func primaryMR(ticketKey: String, mergeRequests: [MergeRequestRef],
                                 branch: String? = nil) -> MergeRequestRef? {
        let matching = mergeRequests.filter {
            TicketMatching.matches($0, ticketKey: ticketKey, branch: branch)
        }
        let newestOpened = matching.filter { $0.state == "opened" }.max(by: { $0.iid < $1.iid })
        let newestMerged = matching.filter { $0.state == "merged" }.max(by: { $0.iid < $1.iid })
        return newestOpened ?? newestMerged
    }

    /// The source branch of the ticket's primary MR, for the `🌿 **BRANCH**` line. nil if none.
    public static func mrSourceBranch(ticketKey: String, mergeRequests: [MergeRequestRef]) -> String? {
        primaryMR(ticketKey: ticketKey, mergeRequests: mergeRequests)?.sourceBranch
    }

    /// Whether the persisted task-file `### Status` marker should be auto-advanced to ✅ Done: the
    /// ticket is Erledigt/Geschlossen in Jira (statusCategory "done") and has a task file whose
    /// marker isn't already ✅ Done. Pure — the caller performs the actual write.
    ///
    /// **⏸️ Hold is overwritten here** — deliberately, and unlike in `shouldAutoSetReview`. Jira
    /// closing the ticket is a statement from outside that there is nothing left to pause; the same
    /// reason the derivation puts Done ahead of the marker. "In review" is the opposite: one pauses
    /// *because* of a question on the MR, so a pause outranks it there.
    public static func shouldAutoSetDone(hasTaskFile: Bool,
                                         currentMarker: TaskStatusMarker?,
                                         jiraDone: Bool) -> Bool {
        jiraDone && hasTaskFile && currentMarker != .done
    }

    /// Whether the persisted task-file `### Status` marker should be auto-advanced to 🔵 Review:
    /// an MR for the ticket is **opened** (and none merged), a task file exists, and the marker
    /// isn't already Review or the final ✅ Done. Pure — the caller performs the actual write.
    ///
    /// Ein **wieder aufgemachtes** Ticket (`isReopened`) hebt die beiden letzten Sperren auf: dort ist
    /// das ✅ nachweislich veraltet (Jira führt das Ticket als nicht erledigt, ein neuerer MR ist
    /// offen), und der alte gemergte MR gehört zur vorigen Runde. Sonst bliebe der Marker für immer
    /// auf ✅ stehen — er ist der Grund, warum die Karte in Done klebte.
    ///
    /// **⏸️ Hold sperrt unbedingt**, noch vor dieser Ausnahme: ein Hold ist nie veraltet, sondern die
    /// aktuelle Absicht eines Menschen, und der Normalfall einer Pause *ist* ein offener MR, auf
    /// dessen Rückfrage man wartet. Ohne die Sperre schriebe der nächste Board-Refresh 🔵 in die
    /// Datei — der Status hielte keine fünf Minuten.
    public static func shouldAutoSetReview(ticketKey: String,
                                           hasTaskFile: Bool,
                                           currentMarker: TaskStatusMarker?,
                                           mergeRequests: [MergeRequestRef],
                                           jiraState: JiraDoneState = .unknown) -> Bool {
        guard hasTaskFile, currentMarker != .review, currentMarker != .hold else { return false }
        let matching = mergeRequests.filter {
            TicketMatching.references($0.sourceBranch, ticketKey: ticketKey)
                || TicketMatching.references($0.title, ticketKey: ticketKey)
        }
        let reopened = isReopened(jiraState: jiraState,
                                  merged: matching.filter { $0.state == "merged" },
                                  opened: matching.filter { $0.state == "opened" })
        guard reopened || currentMarker != .done else { return false }
        guard reopened || !matching.contains(where: { $0.state == "merged" }) else { return false }
        // A draft MR is not review-ready, so it must not auto-advance the marker to 🔵 Review.
        return matching.contains { $0.state == "opened" && !$0.draft }
    }

    /// **„Wieder aufgemacht"**: Jira führt das Ticket *ausdrücklich* als nicht erledigt **und** es gibt
    /// einen offenen MR, der neuer ist als jeder gemergte (iid als Alters-Proxy, wie beim Badge).
    ///
    /// Beide Hälften sind nötig, jede allein wäre falsch:
    /// - **Jira allein** nicht: der Status hinkt hier regelmässig nach (gemergt, Jira noch „In Arbeit").
    ///   Sonst fiele jedes fertige Ticket aus Done heraus, bis jemand Jira nachzieht — 22 von 36
    ///   geprüften ✅-Tickets standen genau so da, nur eben mit Jira *schon* auf Erledigt.
    /// - **Der offene MR allein** nicht: ein liegengebliebener MR auf einem von Hand auf ✅ gesetzten
    ///   Ticket darf es nicht aus Done ziehen — genau dafür gibt es Stufe 2 der Präzedenz.
    ///
    /// „Neuer als jeder gemergte" schliesst den alten, neben dem gemergten stehengebliebenen MR aus.
    /// Beobachteter Fall (BFEZVM-4569): Jira „In Arbeit", Task-File ✅ Done, MR 1123 alt offen, 1124
    /// gemergt, 1140–1142 neu und review-reif offen → wieder aufgemacht, Karte gehört in Review.
    static func isReopened(jiraState: JiraDoneState,
                           merged: [MergeRequestRef],
                           opened: [MergeRequestRef]) -> Bool {
        guard jiraState == .notDone else { return false }
        guard let newestMerged = merged.map(\.iid).max() else { return !opened.isEmpty }
        return opened.contains { $0.iid > newestMerged }
    }
}
