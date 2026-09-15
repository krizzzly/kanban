import Foundation

/// Declarative schema of `~/Library/Application Support/Kanban/config.json` — the single source of
/// truth the settings UI renders from (`ConfigFieldSpec` & co. live in `ConfigSchema.swift`).
///
/// Die zwei Module, die Kanban selbst betreibt (Jira, GitLab) — plus **Confluence**, das keins ist:
/// dort steht nur, wo die exportierten Seiten liegen und zu welchem Space sie gehören. Geholt werden
/// sie von Hermes' `generate-confluence-page`, und genau dieser Eintrag sagt ihm, wohin.
/// Wer weitere Hermes-Module pflegen will, tut das in Hermes.
public enum KanbanConfigSchema {
    public static let sections: [ConfigSectionSpec] = [general, jira, gitlab, confluence,
                                                       knowledgebase, watchdog, hermes]

    /// Nur sinnvoll, solange eine `~/.hermes/config.json` existiert — die Einstellungen blenden die
    /// Sektion sonst aus (`HermesSync.isAvailable`).
    public static let hermesSectionID = "hermes"

    static let general = ConfigSectionSpec(
        id: "general", title: "Allgemein", icon: "gearshape",
        fields: [
            ConfigFieldSpec(["basePath"], "Basis-Pfad", kind: .path, placeholder: "~/code",
                            help: "Basisordner der Projekte; Tasks-Pfad und Repo-Ordner werden "
                                + "relativ dazu aufgelöst."),
            ConfigFieldSpec(["commit", "excludeClaudeProjectFile"],
                            ".claude/project.json nicht mitcommitten",
                            kind: .bool(defaultOn: true),
                            help: "Die Datei erzeugt Kanban selbst bei jedem Projektwechsel. In den "
                                + "meisten Repos ist .claude/ gitignored und sie taucht gar nicht "
                                + "auf; wo nicht, stünde sie sonst in jedem Commit. Der Haken setzt "
                                + "sie im Commit-Fenster nur **vorab** ab — abwählen lässt sich "
                                + "dort jede Datei, und dazuwählen auch diese."),
        ])

    static let jira = ConfigSectionSpec(
        id: "jira", title: "Jira", icon: "checklist",
        intro: "Pflichtteil: ohne Jira-Zugang und mindestens ein Projekt zeigt das Board nichts an.",
        fields: [
            ConfigFieldSpec(["modules", "jira", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://firma.atlassian.net", validation: .url),
            ConfigFieldSpec(["modules", "jira", "email"], "E-Mail", kind: .string,
                            placeholder: "ich@firma.ch", validation: .email),
            ConfigFieldSpec(["modules", "jira", "apiToken"], "API-Token", kind: .secret,
                            help: "Erstellen unter id.atlassian.com → Security → API tokens. "
                                + "Auth = Basic base64(E-Mail:Token)."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "jira", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("prefix", "Ticket-Präfix", required: true, placeholder: "EVEN"),
                ProjectFieldSpec("tasksPath", "Tasks-Pfad", required: true,
                                 placeholder: "~/Library/Application Support/Kanban/tasks/even",
                                 help: "Absolut, ~ oder relativ zum Basis-Pfad. Die Task-Files "
                                     + "liegen im Kanban-Ordner, nicht im Repo — dort wurden sie "
                                     + "nie mitcommittet."),
                ProjectFieldSpec("repoDir", "Repo-Ordner (Override)", required: false,
                                 placeholder: "even",
                                 help: "Lokales Git-Repo; absolut, ~ oder relativ zum Basis-Pfad. "
                                     + "Leer = erstes Segment des Tasks-Pfads."),
                ProjectFieldSpec("baseUrl", "Base-URL (Override)", required: false,
                                 placeholder: "https://andere-instanz.atlassian.net"),
                ProjectFieldSpec("agent", "Coding-Agent",
                                 kind: .choice(AgentKind.allCases.map(\.rawValue)),
                                 required: false,
                                 help: "Wer die Console dieses Projekts bedient. Claude tippt "
                                     + "/command, Codex $skill — die Workflow-Assets sind für beide "
                                     + "dieselben. Leer = Claude."),
            ]))

    static let gitlab = ConfigSectionSpec(
        id: "gitlab", title: "GitLab", icon: "arrow.triangle.branch",
        intro: "Optional — liefert die Spalten Review und Done. Gleicher Projekt-Key wie bei Jira → "
             + "Zuordnung. Ohne GitLab bleibt das Board auf den lokalen Artefakten.",
        fields: [
            ConfigFieldSpec(["modules", "gitlab", "baseUrl"], "Base-URL", kind: .string,
                            placeholder: "https://git.firma.io", validation: .url),
            ConfigFieldSpec(["modules", "gitlab", "apiToken"], "API-Token", kind: .secret,
                            help: "Personal Access Token (Settings → Access Tokens) mit read_api, "
                                + "Header PRIVATE-TOKEN."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "gitlab", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("path", "Projekt-Pfad", required: true, placeholder: "applications/even"),
            ]))

    static let confluence = ConfigSectionSpec(
        id: "confluence", title: "Confluence", icon: "book",
        intro: "Optional — der Ablageort der exportierten Seiten, je Projekt. Kanban holt keine "
             + "Seiten selbst; das tut Hermes' generate-confluence-page, und es entscheidet über "
             + "diesen Eintrag: Space → Ordner. Leer = "
             + "~/Library/Application Support/Kanban/docs/<projekt> — wie die Task-Files, denn "
             + "commitet wird die Doku im Repo ohnehin nie. Der Pfad steht als docsPath in "
             + "<repo>/.claude/project.json, damit die Skills ihn kennen.",
        fields: [],
        projectMap: ProjectMapSpec(
            path: ["modules", "confluence", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("space", "Space-Key", required: false, placeholder: "EVEN",
                                 help: "Confluence-Space, aus dem die Seiten dieses Projekts "
                                     + "kommen. Hermes findet darüber den Ordner, wenn beim Export "
                                     + "kein Projekt genannt wird."),
                ProjectFieldSpec("path", "Doku-Pfad", required: false,
                                 placeholder: "~/Library/Application Support/Kanban/docs/even",
                                 help: "Absolut, ~ oder relativ zum Basis-Pfad. Leer = der "
                                     + "Default-Ordner unter Application Support."),
            ]))

    /// Der Ort der Knowledgebase je Projekt. Kanban tut damit selbst nichts — es reicht ihn als
    /// `kbPath` in `<repo>/.claude/project.json` durch, damit die Skills ihn nachschlagen können.
    /// Ohne Eintrag fehlt der Schlüssel dort; ein erfundener Default-Ordner wäre eine Behauptung.
    static let knowledgebase = ConfigSectionSpec(
        id: "knowledgebase", title: "Knowledgebase", icon: "books.vertical",
        intro: "Optional — wo die Knowledgebase dieses Projekts liegt. Der Pfad landet als "
             + "`kbPath` in <repo>/.claude/project.json, damit Skills ihn auflösen können; Kanban "
             + "selbst liest den Ordner nicht. Leer = kein kbPath in der Datei. Mehrere Projekte "
             + "dürfen auf denselben Ordner zeigen.",
        fields: [],
        projectMap: ProjectMapSpec(
            path: ["modules", "knowledgebase", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("path", "Knowledgebase-Pfad", required: false,
                                 placeholder: "~/code/even-docs/kb",
                                 help: "Absolut, ~ oder relativ zum Basis-Pfad."),
            ]))

    /// Der Session-Watchdog. Kein Modul und kein Projekt-Kram — ein Schalter plus vier Stellschrauben
    /// für einen Hintergrund-Lauf, der Geld kostet. Deshalb steht hier auch, was er kostet: eine
    /// Vorgabe, die unbemerkt Tokens verbrennt, wäre ein schlechter Tausch für „praktisch".
    static let watchdog = ConfigSectionSpec(
        id: "watchdog", title: "Watchdog", icon: "waveform.path.ecg",
        intro: "Optional — liest die Claude-Sessions unter ~/.claude/projects (alle, nicht nur die "
             + "aus Kanban) und sucht nach Dingen, die immer wieder schiefgehen. Der Lauf filtert "
             + "erst lokal vor (Werkzeug-Fehler, gescheiterte Builds, verweigerte Freigaben, "
             + "Stellen an denen du korrigieren musstest) und lässt nur diese Ausschnitte von "
             + "Claude zu einer Liste verdichten. Die Befunde stehen hinter dem ⚡︎-Knopf rechts in "
             + "der Leiste. Aus = es läuft nichts und kostet nichts.",
        fields: [
            ConfigFieldSpec(["watchdog", "enabled"], "Watchdog einschalten",
                            kind: .bool(defaultOn: false),
                            help: "Scannt im Hintergrund. Auch ausgeschaltet lässt sich im Panel "
                                + "jederzeit ein einzelner Lauf starten."),
            ConfigFieldSpec(["watchdog", "intervalMinutes"], "Scan alle … Minuten",
                            kind: .choice(["15", "30", "60", "120", "240"]),
                            help: "Standard = 60. Jeder Lauf wertet nur aus, was sich seit dem "
                                + "letzten geändert hat."),
            ConfigFieldSpec(["watchdog", "lookbackHours"], "Rückblick (Stunden)",
                            kind: .choice(["24", "72", "168", "336"]),
                            help: "Standard = 72. Ältere Sessions zählen nicht mehr als "
                                + "„wiederkehrend\"."),
            ConfigFieldSpec(["watchdog", "model"], "Modell",
                            kind: .choice(["claude-haiku-4-5-20251001", "claude-sonnet-5",
                                           "claude-opus-5"]),
                            help: "Standard = Sonnet 5. Haiku ist deutlich billiger, Opus "
                                + "gründlicher. Die Kosten des letzten Laufs stehen im Panel."),
            ConfigFieldSpec(["watchdog", "minSignals"], "Auswerten ab … Signalen",
                            kind: .choice(["2", "4", "8", "15"]),
                            help: "Standard = 4. Darunter wird das Modell gar nicht erst gefragt — "
                                + "es gäbe nichts zu verdichten."),
            ConfigFieldSpec(["watchdog", "maxSessions"], "Sessions je Lauf",
                            kind: .choice(["10", "25", "50", "100"]),
                            help: "Standard = 25. Deckelt einen Rückstau, damit ein Lauf nicht "
                                + "plötzlich riesig wird."),
        ])

    static let hermes = ConfigSectionSpec(
        id: hermesSectionID, title: "Hermes", icon: "arrow.triangle.2.circlepath",
        intro: "Kanban besitzt seine Config selbst; beim ersten Start wurde eine vorhandene "
             + "Hermes-Config einmalig übernommen. Der Rückweg hält nur die **Projektliste** in "
             + "~/.hermes/config.json aktuell, damit hermes-CLI und MCP-Tools dieselben Projekte "
             + "sehen. Er ist additiv: Tokens, URLs und alles Unbekannte bleiben unangetastet, und "
             + "ein Projekt, das nur Hermes kennt, wird nie gelöscht.",
        fields: [
            ConfigFieldSpec(["hermes", "syncProjects"], "Projekte nach Hermes zurückschreiben",
                            kind: .bool(defaultOn: true),
                            help: "Läuft nach jedem Speichern. Aus, wenn du die Hermes-Config von "
                                + "Hand pflegst."),
        ])
}
