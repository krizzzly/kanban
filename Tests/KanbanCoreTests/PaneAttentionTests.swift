import XCTest
@testable import KanbanCore

final class PaneAttentionTests: XCTestCase {
    func testDetectsPermissionPicker() {
        let pane = """
        Claude wants to edit File.swift

        Do you want to make this edit?
        ❯ 1. Yes
          2. Yes, and don't ask again
          3. No, and tell Claude what to do differently
        """
        XCTAssertTrue(PaneAttention.showsQuestion(pane))
    }

    func testDetectsNumberedMenuWithoutCursor() {
        let pane = "Which option?\n  1. Alpha\n  2. Beta\n  3. Gamma\n"
        XCTAssertTrue(PaneAttention.showsQuestion(pane))
    }

    func testWorkingPaneIsNotWaiting() {
        let pane = "· Working… (12s · 1.2k tokens · esc to interrupt)"
        XCTAssertTrue(PaneAttention.isWorking(pane))
        XCTAssertFalse(PaneAttention.showsQuestion(pane))
    }

    /// Eine eigene Statuszeile darf keine Arbeit vortäuschen. Wortlaut aus der echten Pane von
    /// CORETEST-4237 (cc-statusline, 2026-09-07): kein „esc to interrupt", aber zweimal das Wort
    /// „tokens" — die alte Regel hielt die Konsole deshalb für immer für arbeitend, und der
    /// ⏱-Zähler eines am 2026-09-03 abgebrochenen Turns stand bei 87 h.
    func testStatuslineTokenCounterIsNotWorking() {
        let pane = """
          Das ist wichtiger als die LNG/LPG-Frage. Soll ich beides ins Task-File schreiben?

        ✻ Sautéed for 50s

        ❯ kannst du die Kommentare einzeln holen?
        ────────────────────────────────────────
        ❯ 
        ────────────────────────────────────────
          Model: Opus 5 (1M context)  Effort: xhigh  Context: [█████████▒] 917k/980k (94%)
          cwd: ~/code/core ⎇ playground/tutorial Cost: $172.01 ΣTokens: 917k  Speed: 0 tok/s
          ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
                                                                            916703 tokens
        """
        XCTAssertFalse(PaneAttention.isWorking(pane))
    }

    /// …und dieselbe Statuszeile darf eine echte Rückfrage nicht verdecken: `showsQuestion` steigt
    /// bei `isWorking` sofort aus, ein Dauer-„arbeitend" hätte also jede Freigabe verschluckt.
    func testStatuslineDoesNotHideAPermissionPicker() {
        let pane = """
        Do you want to make this edit?
        ❯ 1. Yes
          2. No, and tell Claude what to do differently
          cwd: ~/code/core Cost: $172.01 ΣTokens: 917k  Speed: 0 tok/s
                                                                            916703 tokens
        """
        XCTAssertTrue(PaneAttention.showsQuestion(pane))
    }

    /// Der echte Hinweis zählt weiter — auch mit derselben Statuszeile darunter.
    func testWorkingFooterWinsOverStatusline() {
        let pane = """
        ✻ Sautéing… (23s · ↑ 3.1k tokens · esc to interrupt)
          cwd: ~/code/core Cost: $172.01 ΣTokens: 917k  Speed: 0 tok/s
        """
        XCTAssertTrue(PaneAttention.isWorking(pane))
        XCTAssertFalse(PaneAttention.showsQuestion(pane))
    }

    func testIdlePromptIsNotTreatedAsQuestion() {
        // Just the empty input box — not a blocking question (that's the hook's idle_prompt job).
        let pane = "────────────────────────────────────────\n> \n────────────────────────────────────────"
        XCTAssertFalse(PaneAttention.showsQuestion(pane))
    }

    // MARK: Codex

    /// Codex' Freigabe-Dialog (Wortlaut aus dem Binary 0.148).
    func testDetectsCodexApproval() {
        let pane = """
        • Allow Codex to run `rm -rf build`?
        › 1. Allow
          2. Allow for this session
          3. Cancel this request
        """
        XCTAssertTrue(PaneAttention.showsQuestion(pane))
    }

    func testDetectsCodexEditRequest() {
        XCTAssertTrue(PaneAttention.showsQuestion("Codex wants to edit AppModel.swift"))
    }

    /// Codex' Fusszeile beim Arbeiten — der Text unterscheidet sich von Claudes, der Hinweis nicht.
    func testCodexWorkingFooter() {
        XCTAssertTrue(PaneAttention.isWorking("  Esc to interrupt   100% context left"))
        XCTAssertFalse(PaneAttention.showsQuestion("  Esc to interrupt   100% context left"))
    }

    /// Der Fall, der die alte Regel zerlegt hätte: Codex' Eingabezeile trägt immer ein `›`, und eine
    /// nummerierte Zeile in einer Antwort ist keine Rückfrage.
    func testCodexAnswerWithSingleNumberedLineIsNotAQuestion() {
        let pane = """
        • Ich habe drei Dinge geprüft:
          1. Der Symlink zeigt auf den Bestand
        › Ask Codex to do anything
        """
        XCTAssertFalse(PaneAttention.showsQuestion(pane))
    }

    /// Ein Codex-Menü mit Cursor ist dagegen eine Rückfrage.
    func testCodexMenuWithCursorIsAQuestion() {
        XCTAssertTrue(PaneAttention.showsQuestion("Skills\n› 1. List skills\n"))
    }
}
