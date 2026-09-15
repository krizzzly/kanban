import Foundation

/// Liest einen einzelnen Codex-Turn aus der Rollout-Datei zurück — das Gegenstück zu
/// `ClaudeTurnReader`, mit demselben Ergebnis-Typ, damit die Bubble im Prompt-Panel nichts über den
/// Agent wissen muss.
///
/// Turn-Grenzen sind dieselben wie in `CodexTurnAccumulator`: das Paar `task_started` …
/// `task_complete`/`turn_aborted`. Gezählt werden nur **abgeschlossene** Turns, sonst zeigte der
/// Index auf einen anderen Turn als die ⏱-Liste.
///
/// Auch hier gilt die Sparsamkeit des Claude-Lesers: Codex' Prosa wird gerendert, der Werkzeug-
/// Verkehr nur gezählt. Ein `custom_tool_call_output` trägt gern Kilobytes Skript-Ausgabe — das liest
/// niemand in einer Chat-Bubble nach.
public enum CodexTurnReader {
    public static func content(turnIndex: Int, rollout url: URL) -> ClaudeTurnContent? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var completed = -1          // Index des zuletzt abgeschlossenen Turns
        var inTurn = false
        var collecting = false
        var answer: [String] = []
        var toolOrder: [String] = []
        var toolCounts: [String: Int] = [:]
        var hiddenResults = 0
        var hiddenBytes = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(Event.self, from: data),
                  let payload = event.payload, let type = payload.type else { continue }

            switch type {
            case "task_started":
                inTurn = true
                collecting = (completed + 1) == turnIndex

            case "task_complete", "turn_aborted":
                guard inTurn else { continue }
                inTurn = false
                completed += 1
                if collecting {
                    // Codex' Schlusswort steht auch im Payload — es fehlt in der Prosa, wenn der
                    // Turn abgebrochen wurde, bevor die Nachricht als `message` geschrieben war.
                    if answer.isEmpty, let last = payload.last_agent_message, !last.isEmpty {
                        answer.append(last)
                    }
                    return ClaudeTurnContent(
                        turnIndex: turnIndex,
                        answer: answer.joined(separator: "\n\n"),
                        tools: toolOrder.map { ClaudeToolUse(name: $0, count: toolCounts[$0] ?? 0) },
                        hiddenResults: hiddenResults,
                        hiddenBytes: hiddenBytes)
                }

            case "message":
                // `assistant` ist Codex' Prosa; `user` ist der Prompt (steht schon in der Bubble),
                // `developer` sind eingespeiste Instruktionen (z. B. der Skills-Block).
                guard collecting, payload.role == "assistant" else { continue }
                let prose = (payload.content ?? []).compactMap(\.text).joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !prose.isEmpty { answer.append(prose) }

            case "custom_tool_call", "function_call":
                guard collecting, let name = payload.name, !name.isEmpty else { continue }
                if toolCounts[name] == nil { toolOrder.append(name) }
                toolCounts[name, default: 0] += 1

            case "custom_tool_call_output", "function_call_output":
                guard collecting else { continue }
                hiddenResults += 1
                hiddenBytes += payload.outputByteCount

            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Rollout-Zeilen

    private struct Event: Decodable {
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let type: String?
        let role: String?
        let name: String?
        let content: [Content]?
        let last_agent_message: String?
        let output: Output?

        /// Wie viel Ergebnis-Text nicht gerendert wird — nur die Grösse, nicht der Inhalt.
        var outputByteCount: Int {
            switch output {
            case .text(let text): return text.utf8.count
            case .blocks(let blocks): return blocks.reduce(0) { $0 + ($1.text?.utf8.count ?? 0) }
            case nil: return 0
            }
        }
    }

    private struct Content: Decodable {
        let text: String?
    }

    /// `output` ist mal ein String, mal eine Liste von Blöcken — beides kommt vor.
    private enum Output: Decodable {
        case text(String)
        case blocks([Content])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { self = .text(text) }
            else { self = .blocks((try? container.decode([Content].self)) ?? []) }
        }
    }
}
