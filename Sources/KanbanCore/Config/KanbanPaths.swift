import Foundation

/// Wo Kanbans Daten liegen — die eine Stelle, die den Datenordner kennt.
///
/// Davor rechnete jede Ablage ihren Pfad selbst aus `applicationSupportDirectory` zusammen. Solange
/// es eine einzige Welt gab, war das bloss Wiederholung; mit Profilen ist es der Unterschied
/// zwischen „eine Stelle umstellen" und „neun Stellen suchen".
///
/// Zwei Sorten Pfad, und die Trennung ist die eigentliche Aussage dieser Datei:
///
/// - **profilgebunden** (`root` und alles darunter): Config, Task-Files, Doku, Skill-Sets, Bilder,
///   Session-Ids, Worklog, Watchdog, Sperren. Das ist die Welt, die ein Profil ausmacht.
/// - **global** (`globalRoot` und die drei Werte daneben): `profiles.json` — die Frage, welche
///   Profile es überhaupt gibt, kann nicht in einem Profil stehen — sowie die Attention-Marker und
///   das Hook-Skript. Die beiden letzten, weil `~/.claude/settings.json` das Skript mit **absolutem
///   Pfad** aufruft: ein Hook je Profil hiesse, diese fremde Datei bei jedem Wechsel umzuschreiben.
///
/// Der Ordner des aktiven Profils wird beim **ersten Zugriff** aufgelöst, nicht in einem
/// Startschritt: `KanbanApp.init()` läuft vor dem `AppDelegate` und braucht die Pfade dort bereits
/// (Selftest, Task-File-Migration, Verlinkung der Skill-Sets in die Agent-Homes). Hinge die
/// Auflösung an einer Startreihenfolge, liefen genau diese drei gegen den falschen Ordner.
public enum KanbanPaths {
    private static let sperre = NSLock()
    private static var globaleWurzel: URL?
    private static var wurzel: URL?

    // MARK: - Global

    /// `~/Library/Application Support/Kanban` — der Ordner, den es unabhängig von jedem Profil gibt.
    public static var globalRoot: URL {
        sperre.lock(); defer { sperre.unlock() }
        if let globaleWurzel { return globaleWurzel }
        return Self.standardGlobaleWurzel
    }

    private static var standardGlobaleWurzel: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kanban", isDirectory: true)
    }

    /// Die Liste der Profile und welches gerade gilt. Das einzige Globale, das eine Einstellung ist.
    public static var profilesFile: URL { globalRoot.appendingPathComponent("profiles.json") }

    /// Die Attention-Marker des Claude-Hooks — eine Datei je `session_id`.
    public static var attentionDirectory: URL {
        globalRoot.appendingPathComponent("attention", isDirectory: true)
    }

    /// Das Hook-Skript selbst. Steht mit absolutem Pfad in `~/.claude/settings.json`.
    public static var hookScript: URL {
        globalRoot.appendingPathComponent("kanban-attention-hook.sh")
    }

    // MARK: - Profilgebunden

    /// Der Ordner des aktiven Profils. Beim migrierten Profil ist das `globalRoot` selbst.
    public static var root: URL {
        sperre.lock()
        if let wurzel { sperre.unlock(); return wurzel }
        sperre.unlock()
        // Ausserhalb der Sperre auflösen: das Lesen von profiles.json greift selbst auf
        // `globalRoot` zu, und eine rekursive Sperre wäre ein Deadlock.
        let aufgeloest = ProfileStore.activeFolder()
        sperre.lock(); defer { sperre.unlock() }
        if let wurzel { return wurzel }
        wurzel = aufgeloest
        return aufgeloest
    }

    public static var configFile: URL { root.appendingPathComponent("config.json") }
    public static var tasksRoot: URL { root.appendingPathComponent("tasks", isDirectory: true) }
    public static var docsRoot: URL { root.appendingPathComponent("docs", isDirectory: true) }
    /// Vorgabe-Sammelordner der Skill-Sets, solange `claude.setsPath` nichts sagt.
    public static var claudeSetsRoot: URL { root.appendingPathComponent("claude", isDirectory: true) }
    public static var imagesRoot: URL { root.appendingPathComponent("images", isDirectory: true) }
    public static var sessionsFile: URL { root.appendingPathComponent("sessions.json") }
    public static var worklogFile: URL { root.appendingPathComponent("worklog.json") }
    public static var watchdogFile: URL { root.appendingPathComponent("watchdog.json") }
    public static var locksDirectory: URL {
        root.appendingPathComponent(".locks", isDirectory: true)
    }

    // MARK: - Umschalten und Tests

    /// Das aktive Profil zeigt ab jetzt hierher. Ruft der Profilwechsel; Tests setzen damit einen
    /// Temp-Ordner.
    public static func setRoot(_ url: URL) {
        sperre.lock(); defer { sperre.unlock() }
        wurzel = url
    }

    /// Nur für Tests: die globale Wurzel umbiegen, damit `profiles.json` nicht im echten Home landet.
    public static func setGlobalRoot(_ url: URL?) {
        sperre.lock(); defer { sperre.unlock() }
        globaleWurzel = url
    }

    /// Vergisst den aufgelösten Profilordner; der nächste Zugriff fragt `ProfileStore` erneut.
    public static func reset() {
        sperre.lock(); defer { sperre.unlock() }
        wurzel = nil
    }
}
