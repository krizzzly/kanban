import Foundation

/// Ruft die `claude`-CLI im Print-Modus auf und gibt ihre Antwort zurück.
///
/// Bewusst wirkungslos gehalten: MCP-Server sind abgeschaltet und alle Datei- und Ausführ-Werkzeuge
/// verboten. Ein Hintergrund-Durchgang kann so kein Repo anfassen, nicht sekundenlang den
/// MCP-Stack laden und keine Freigabe-Abfrage auslösen — alles, worüber er urteilt, steht im Prompt.
public struct ClaudeHeadless: Sendable {

    public struct Antwort: Sendable {
        public let text: String
        public let kostenUSD: Double?
        public let dauerMs: Int?
    }

    public enum Fehler: Error, LocalizedError, Equatable {
        case cliFehlt
        case abgelaufen(Int)
        case fehlgeschlagen(String)
        case leereAntwort

        public var errorDescription: String? {
            switch self {
            case .cliFehlt:
                return "Die `claude`-CLI wurde nicht gefunden. Ohne sie kann der Watchdog nicht auswerten."
            case .abgelaufen(let s):
                return "claude hat nach \(s)s nicht geantwortet."
            case .fehlgeschlagen(let m):
                return m
            case .leereAntwort:
                return "claude hat kein Ergebnis geliefert."
            }
        }
    }

    private let modell: String
    private let executable: String?

    public init(modell: String, executable: String? = nil) {
        self.modell = modell
        self.executable = executable
    }

    /// Übliche Installationsorte; `which` über eine Login-Shell wäre für einen Timer-Durchgang
    /// unnötig teuer.
    public static func findeCLI() -> String? {
        if let pfad = ProcessInfo.processInfo.environment["CLAUDE_CLI"], !pfad.isEmpty,
           FileManager.default.isExecutableFile(atPath: pfad) { return pfad }
        let kandidaten = [
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            ("~/.local/bin/claude" as NSString).expandingTildeInPath,
            ("~/.claude/local/claude" as NSString).expandingTildeInPath,
        ]
        return kandidaten.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var verfuegbar: Bool { findeCLI() != nil }

    /// Die gerade laufenden Aufrufe. Ein `claude -p` überlebt das Beenden der App sonst als
    /// **Waise** (beobachtet: `ppid=1`, 5½ Minuten Restlaufzeit, 300 MB) — sein Zeitlimit lebte im
    /// Elternprozess und stirbt mit ihm. Über die Liste beendet die App ihre Kinder beim Schliessen
    /// und der Mensch einen laufenden Scan von Hand.
    private static let laufende = Prozessliste()

    /// Beendet alle laufenden Aufrufe. Liefert, wie viele es waren.
    @discardableResult
    public static func alleBeenden() -> Int { laufende.alleBeenden() }

    public static var laeuftGerade: Bool { laufende.anzahl > 0 }

    public func frage(_ prompt: String, timeout: TimeInterval = 900) throws -> Antwort {
        guard let claude = executable ?? Self.findeCLI() else { throw Fehler.cliFehlt }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = [
            "-p", prompt,
            "--output-format", "json",
            "--model", modell,
            // Den MCP-Stack des Benutzers überspringen: das Laden kostet Sekunden und würde einem
            // Hintergrund-Job Werkzeuge zeigen, die er nicht braucht.
            "--strict-mcp-config",
            "--mcp-config", "{\"mcpServers\":{}}",
            "--disallowed-tools", "Bash", "Edit", "Write", "Read", "Task",
            "WebFetch", "WebSearch", "NotebookEdit", "Glob", "Grep",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do { try process.run() } catch {
            throw Fehler.fehlgeschlagen("claude liess sich nicht starten: \(error.localizedDescription)")
        }
        Self.laufende.dazu(process)
        defer { Self.laufende.weg(process) }

        // Die Frist muss **vor** dem Lesen stehen: `readDataToEndOfFile` blockiert, bis das Kind
        // seine Pipe schliesst — was erst das Beenden auslöst.
        let abgelaufen = AbgelaufenFlag()
        let killer = DispatchWorkItem {
            guard process.isRunning else { return }
            abgelaufen.setzen()
            process.terminate()
        }
        Self.timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: killer)

        let ausgabe = stdout.fileHandleForReading.readDataToEndOfFile()
        let fehlerText = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        if abgelaufen.wert { throw Fehler.abgelaufen(Int(timeout)) }

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: fehlerText, as: UTF8.self)
            let kurz = detail.isEmpty ? String(decoding: ausgabe, as: UTF8.self) : detail
            throw Fehler.fehlgeschlagen("claude endete mit \(process.terminationStatus): \(kurz.prefix(400))")
        }

        return try Self.leseHuelle(String(decoding: ausgabe, as: UTF8.self))
    }

    private static let timeoutQueue = DispatchQueue(label: "kanban.watchdog.timeout")

    /// `--output-format json` liefert ein JSON-Array von Stream-Ereignissen; das mit
    /// `type == "result"` trägt die Antwort. Eigener Schritt, damit die Form ohne Prozess testbar ist.
    public static func leseHuelle(_ stdout: String) throws -> Antwort {
        guard let data = stdout.data(using: .utf8) else { throw Fehler.leereAntwort }

        let ereignisse: [[String: Any]]
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            ereignisse = array
        } else if let einzel = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            ereignisse = [einzel]
        } else {
            throw Fehler.fehlgeschlagen("Unlesbare claude-Ausgabe: \(stdout.prefix(200))")
        }

        guard let ergebnis = ereignisse.last(where: { $0["type"] as? String == "result" }) else {
            throw Fehler.leereAntwort
        }
        if ergebnis["is_error"] as? Bool == true {
            let subtyp = ergebnis["subtype"] as? String ?? "error"
            let text = ergebnis["result"] as? String ?? ""
            throw Fehler.fehlgeschlagen("claude meldet \(subtyp): \(text.prefix(300))")
        }
        guard let text = ergebnis["result"] as? String, !text.isEmpty else {
            throw Fehler.leereAntwort
        }

        return Antwort(text: text,
                       kostenUSD: ergebnis["total_cost_usd"] as? Double,
                       dauerMs: ergebnis["duration_ms"] as? Int)
    }

    /// Holt das JSON-Objekt aus einer Modellantwort.
    ///
    /// „Nur JSON" ist keine Garantie: das Modell packt es regelmässig in einen ```json-Block und
    /// stellt gelegentlich einen Satz davor. Beides wird abgefangen, statt den ganzen Scan an der
    /// Formatierung scheitern zu lassen.
    public static func jsonObjekt(aus text: String) -> Data? {
        let getrimmt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let block = codeBlock(in: getrimmt) { return block.data(using: .utf8) }
        guard let start = getrimmt.firstIndex(of: "{"),
              let ende = getrimmt.lastIndex(of: "}"), start < ende else { return nil }
        return String(getrimmt[start...ende]).data(using: .utf8)
    }

    private static func codeBlock(in text: String) -> String? {
        guard let start = text.range(of: "```") else { return nil }
        let nachZaun = text[start.upperBound...]
        guard let zeilenende = nachZaun.firstIndex(of: "\n") else { return nil }
        let rumpf = nachZaun[nachZaun.index(after: zeilenende)...]
        guard let ende = rumpf.range(of: "```") else { return nil }
        let inhalt = String(rumpf[..<ende.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return inhalt.isEmpty ? nil : inhalt
    }
}

/// Die laufenden `claude -p`-Prozesse. Kein Actor, aus demselben Grund wie beim Flag: die
/// Aufrufer sind synchrone GCD-Kontexte, und `alleBeenden()` muss auch aus
/// `applicationWillTerminate` heraus gehen, wo niemand mehr `await`en kann.
private final class Prozessliste: @unchecked Sendable {
    private let lock = NSLock()
    private var prozesse: [Process] = []

    func dazu(_ process: Process) {
        lock.lock(); prozesse.append(process); lock.unlock()
    }

    func weg(_ process: Process) {
        lock.lock(); prozesse.removeAll { $0 === process }; lock.unlock()
    }

    var anzahl: Int {
        lock.lock(); defer { lock.unlock() }
        return prozesse.count
    }

    @discardableResult
    func alleBeenden() -> Int {
        lock.lock()
        let kopie = prozesse
        lock.unlock()
        var beendet = 0
        for process in kopie where process.isRunning {
            process.terminate()
            beendet += 1
        }
        return beendet
    }
}

/// Kleines, gesperrtes Flag zwischen Lese- und Timeout-Queue. Kein Actor: beide Seiten sind
/// synchrone GCD-Kontexte.
private final class AbgelaufenFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func setzen() {
        lock.lock(); flag = true; lock.unlock()
    }

    var wert: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
}
