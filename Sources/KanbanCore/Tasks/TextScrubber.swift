import Foundation

/// Die Naht für die Anonymisierung: jede Textstelle, die Hermes durch `scrubText` schickt, läuft
/// hier durch einen austauschbaren Scrubber.
///
/// Der Default gibt den Text unverändert zurück — der native Export schreibt damit vorerst
/// Klartext, genau wie Hermes mit abgeschalteter Anonymisierung. Gefüllt wird die Naht im
/// Folge-Task, der den Anonymizer nach Swift portiert.
///
/// **Kein Protokoll, sondern ein Closure-Struct.** `KanbanCore` kennt keine Protokolle; Variabilität
/// läuft hier über Structs und Enums. Ein Protokoll mit einer einzigen Implementierung wäre die
/// erste Ausnahme, ohne etwas zu können, was die Closure nicht kann — Zustand trägt sie über die
/// eingeschlossene Instanz. Braucht die Naht später mehr als diese eine Operation, ist der Wechsel
/// eine lokale Änderung.
public struct TextScrubber: Sendable {
    public let scrub: @Sendable (String) -> String

    public init(_ scrub: @escaping @Sendable (String) -> String) {
        self.scrub = scrub
    }

    public static let passthrough = TextScrubber { $0 }

    /// Bequemlichkeit für die vielen optionalen Felder eines Issues.
    public func callAsFunction(_ text: String?) -> String? {
        guard let text else { return nil }
        return scrub(text)
    }

    public func callAsFunction(_ text: String) -> String { scrub(text) }
}
