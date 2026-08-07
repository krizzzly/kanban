import Foundation
import KanbanCore

/// Der Auslieferungsstand der Claude-Assets (SPM-Resources im App-Bundle) und das Seeding beim
/// App-Start: fehlende Assets werden in den kanonischen Bestand kopiert, editierte nie angefasst.
enum ClaudeAssetFactory {
    /// `ClaudeAssets/` aus den Bundle-Resources; nil bei kaputtem Bundle (dann bleibt der Bestand,
    /// wie er ist — die App funktioniert ohne Auslieferungsstand, nur Zurücksetzen geht nicht).
    static var bundledRoot: URL? {
        Bundle.module.url(forResource: "ClaudeAssets", withExtension: nil)
    }

    /// Still und nicht-fatal — ein fehlgeschlagenes Seeding darf den App-Start nicht verhindern.
    @discardableResult
    static func seedAtLaunch() -> [ClaudeAsset] {
        guard let factory = bundledRoot else { return [] }
        return (try? ClaudeAssetStore().seedMissing(from: factory)) ?? []
    }
}
