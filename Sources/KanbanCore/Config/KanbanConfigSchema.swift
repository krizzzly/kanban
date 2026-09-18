import Foundation

/// Declarative schema of `~/Library/Application Support/Kanban/config.json` — the single source of
/// truth the settings UI renders from (`ConfigFieldSpec` & co. live in `ConfigSchema.swift`).
///
/// Die Module, die Kanban selbst betreibt (Jira, GitLab, GitHub) — plus **Confluence**, das keins
/// ist: dort steht nur, wo die exportierten Seiten liegen und zu welchem Space sie gehören. Geholt
/// werden sie von Hermes' `generate-confluence-page`, und genau dieser Eintrag sagt ihm, wohin.
/// Wer weitere Hermes-Module pflegen will, tut das in Hermes.
public enum KanbanConfigSchema {
    public static let sections: [ConfigSectionSpec] = [general, jira, gitlab, github, confluence,
                                                       knowledgebase, docker, appearance, watchdog,
                                                       hermes]

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
                // Steht vorn, weil es die Bedeutung aller Felder darunter mitbestimmt: aus ist das
                // Projekt rein lokal, und Base-URL wie Sprint-Auswahl laufen ins Leere.
                ProjectFieldSpec("useJira", "An Jira angebunden", kind: .bool(defaultOn: true),
                                 required: false,
                                 help: "Aus = Projekt ohne Jira: kein Board, keine Sprints, keine "
                                     + "Worklog-Buchung. Das Board läuft dann nur im freien Modus "
                                     + "aus Task-Files, Worktrees und Merge/Pull Requests. Der "
                                     + "Ticket-Präfix bleibt trotzdem nötig — er benennt Task-Files "
                                     + "und Branches, nicht die Jira-Anbindung."),
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
             + "Zuordnung. Liegt ein Projekt stattdessen auf GitHub, gehört es in den Abschnitt "
             + "darunter; ohne beides bleibt das Board auf den lokalen Artefakten.",
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

    /// Die zweite Forge. Gleicher Zuschnitt wie GitLab — was ein Projekt bekommt, hängt nicht davon
    /// ab, wo sein Code liegt: Review- und Done-Spalte, PR-Badge, Branch-Links, Review-Skills.
    static let github = ConfigSectionSpec(
        id: "github", title: "GitHub", icon: "chevron.left.forwardslash.chevron.right",
        intro: "Optional, und die Alternative zu GitLab — dieselben Spalten Review und Done, nur "
             + "heisst ein Merge Request dort Pull Request. Gleicher Projekt-Key wie bei Jira → "
             + "Zuordnung. Ein Projekt gehört zu **einer** Forge: steht derselbe Key auch unter "
             + "GitLab, meldet Kanban das als Konfigurationsfehler, statt sich eine auszusuchen.",
        fields: [
            ConfigFieldSpec(["modules", "github", "baseUrl"], "API-Basis", kind: .string,
                            placeholder: "https://api.github.com",
                            help: "Leer = https://api.github.com. Für GitHub Enterprise die "
                                + "API-Basis der Instanz eintragen (https://<host>/api/v3); "
                                + "GraphQL und die Web-Adressen leitet Kanban daraus ab.",
                            validation: .url),
            ConfigFieldSpec(["modules", "github", "apiToken"], "API-Token", kind: .secret,
                            help: "Personal Access Token (Settings → Developer settings) mit "
                                + "Lesezugriff auf das Repo, Header Authorization: Bearer. Ein "
                                + "klassisches Token braucht den Scope „repo“ — ohne ihn bleiben "
                                + "die Thread-Zähler leer, weil sie über GraphQL kommen."),
        ],
        projectMap: ProjectMapSpec(
            path: ["modules", "github", "projects"],
            keyPlaceholder: "kanban",
            fields: [
                ProjectFieldSpec("path", "Repository", required: true, placeholder: "owner/repo"),
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

    /// Ob ein Projekt lokal als Docker-Stack läuft. Wie `knowledgebase` **kein Modul, das Kanban
    /// betreibt** und auch keins, das Hermes kennt: eine Projekt-Eigenschaft, die Kanban an zwei
    /// Stellen auswertet — in der eigenen Oberfläche und als `dockerStack` in
    /// `<repo>/.claude/project.json`, woran die Skills verzweigen.
    ///
    /// Eigene Sektion statt eines Felds unter „Jira": der Schalter hat mit Jira nichts zu tun. Dass
    /// er dieselbe **Form** hat wie `useJira` (ja/nein, Vorgabe ja, nur die Abschaltung wird
    /// geschrieben) macht ihn noch nicht zu einer Jira-Einstellung.
    static let docker = ConfigSectionSpec(
        id: "docker", title: "Docker", icon: "shippingbox",
        intro: "Optional — ob dieses Projekt einen eigenen Docker-Stack hat. Vorgabe ist **ja**: "
             + "jedes bestehende Projekt bleibt unverändert eine Web-Applikation mit Stack, der "
             + "Schlüssel wird nur geschrieben, wenn du ihn ausschaltest. Aus ist der Fall für "
             + "Pakete und Skript-Repos (Kanban selbst ist eins) — sie haben keine .iwf.yml und "
             + "sahen bisher falsch konfiguriert aus, obwohl alles stimmte.",
        fields: [],
        projectMap: ProjectMapSpec(
            path: ["modules", "docker", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("stack", "Docker-Stack", kind: .bool(defaultOn: true),
                                 required: false,
                                 help: "Aus = kein eigener Docker-Stack. Es entfallen die Reiter "
                                     + "Maintree und Worktree, die Snapshots, „Stacks stoppen\" "
                                     + "und jeder iwf-Aufruf; Worktrees werden als reine "
                                     + "Git-Worktrees angelegt (git worktree add). Es bleiben: "
                                     + "Worktrees, Branches, Task-Files, Commits und Merge "
                                     + "Requests. Vorbelegt beim Anlegen anhand einer .iwf.yml im "
                                     + "Repo — entschieden wird hier. Läuft gerade ein Stack "
                                     + "dieses Projekts, bleibt er nach dem Abschalten laufen; er "
                                     + "verschwindet nur aus der Oberfläche (stoppen z.B. mit "
                                     + "iwf worktree stop <NR>). Teilen sich zwei Projekte ein "
                                     + "Repo, gehört <repo>/.claude/project.json dem zuletzt "
                                     + "gewählten — dann sollten beide hier gleich stehen."),
            ]))

    /// Woran man auf einen Blick sieht, in welchem Projekt man steht: ein Bild links in der
    /// Kopfzeile und deren Farben. Kein Modul — reine Oberfläche, wandert nie nach Hermes.
    ///
    /// **Alles optional, und nichts davon ist voreingestellt.** Ohne Eintrag sieht die Kopfzeile aus
    /// wie bisher; das ist kein Sonderfall, sondern der Normalfall. Deshalb gibt es zu jedem Feld
    /// auch einen Weg zurück auf „nicht gesetzt" statt nur auf eine andere Farbe.
    static let appearance = ConfigSectionSpec(
        id: "appearance", title: "Darstellung", icon: "paintpalette",
        intro: "Optional — gibt jedem Projekt ein eigenes Gesicht in der Kopfzeile: ein Bild links "
             + "neben der Projektauswahl und die Farben der Zeile selbst. Das gewählte Bild wird "
             + "nach ~/Library/Application Support/Kanban/images kopiert, damit es nicht "
             + "verschwindet, wenn die Quelldatei umzieht. Nichts gesetzt = Kopfzeile wie immer.",
        fields: [],
        projectMap: ProjectMapSpec(
            path: ["appearance", "projects"],
            keyPlaceholder: "even",
            fields: [
                ProjectFieldSpec("image", "Bild", kind: .image, required: false,
                                 help: "Erscheint links neben der Projektauswahl, auf Zeilenhöhe "
                                     + "skaliert. SVG, PDF, PNG, JPEG, GIF, HEIC, TIFF oder BMP — "
                                     + "SVG und PDF bleiben dabei scharf, weil sie als Vektor "
                                     + "gezeichnet werden."),
                ProjectFieldSpec("headerBackground", "Hintergrund der Kopfzeile",
                                 kind: .color, required: false),
                ProjectFieldSpec("headerForeground", "Textfarbe der Kopfzeile",
                                 kind: .color, required: false,
                                 help: "Gilt für Kanbans eigene Knöpfe und Beschriftungen in der "
                                     + "Zeile. Fenstertitel und Ampelknöpfe zeichnet macOS."),
                ProjectFieldSpec("headerBorderColor", "Farbe des unteren Randes",
                                 kind: .color, required: false),
                ProjectFieldSpec("headerBorderWidth", "Dicke des unteren Randes",
                                 kind: .choice(["0", "1", "2", "3", "4", "6", "8"]),
                                 required: false,
                                 help: "In Punkten. Ohne Farbe passiert nichts — beides gehört "
                                     + "zusammen."),
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
            ConfigFieldSpec(["watchdog", "timeoutSeconds"], "Zeitlimit je Lauf (Sekunden)",
                            kind: .choice(["300", "600", "900", "1800"]),
                            help: "Standard = 900. Gemessen braucht ein voller Lauf 5–6 Minuten; "
                                + "mit 240 s lief er jedes Mal in die Frist und die bezahlte "
                                + "Antwort war weg."),
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
