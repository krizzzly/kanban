import Foundation

/// One-time adoption of an existing `~/.hermes/config.json`.
///
/// Kanban owns its Jira and GitLab config, but it grew up inside a Hermes setup — on this machine the
/// credentials and the whole project list already exist there. So on the first start the two module
/// sections are copied over **verbatim** (unknown keys included), and from then on Kanban's own file
/// is the truth.
///
/// Everything here is a no-op when Hermes isn't installed. That is the point: a fresh install without
/// Hermes must reach the setup screen, not an error.
public enum HermesImport {
    public static var defaultPath: String {
        ("~/.hermes/config.json" as NSString).expandingTildeInPath
    }

    /// True when there is a Hermes config to adopt from (and thus a sync target later on).
    public static func isAvailable(at path: String? = nil) -> Bool {
        FileManager.default.fileExists(atPath: path ?? defaultPath)
    }

    /// Copies `basePath` and the `jira`/`gitlab` module sections into `document`.
    ///
    /// Runs **only** while Kanban has no `modules` of its own — the adoption is a bootstrap, never a
    /// recurring sync, so a value edited in Kanban is never overwritten from Hermes later. Returns nil
    /// when there is nothing to adopt, which spares the caller a pointless write. Pure, so it can be
    /// tested without touching either file.
    public static func adopting(_ hermes: JSONValue, into document: JSONValue) -> JSONValue? {
        guard document.value(at: ["modules"]) == nil else { return nil }

        var result = document
        var adopted = false
        for module in ["jira", "gitlab"] {
            guard var section = hermes.value(at: ["modules", module]) else { continue }
            // Die eine Ausnahme von „wortgleich": `backend` ist Hermes' Umschalter zwischen REST und
            // Browser-Session. Kanban kennt nur den API-Token, ein mitkopierter Schalter würde eine
            // Wahl vortäuschen, die es nicht gibt.
            section.set(nil, at: ["backend"])
            result.set(section, at: ["modules", module])
            adopted = true
        }
        guard adopted else { return nil }

        // Only as a fallback: a basePath Kanban already carries is its own decision.
        if result.value(at: ["basePath"]) == nil, let base = hermes.value(at: ["basePath"]) {
            result.set(base, at: ["basePath"])
        }
        return result
    }

    /// Adopts the Hermes config into Kanban's, if there is one and Kanban has no modules yet.
    /// Returns true when the config was written. Never throws: a broken or absent Hermes file leaves
    /// Kanban exactly as it was.
    @discardableResult
    public static func runIfNeeded(store: ConfigStore = ConfigStore(),
                                   hermesPath: String? = nil) -> Bool {
        let source = hermesPath ?? defaultPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: source)),
              let hermes = try? JSONDecoder().decode(JSONValue.self, from: data),
              var document = try? store.load(),
              let adopted = adopting(hermes, into: document.root) else { return false }

        document.root = adopted
        return (try? store.save(document, force: true)) != nil
    }
}
