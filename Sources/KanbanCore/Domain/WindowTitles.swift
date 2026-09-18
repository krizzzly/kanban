import Foundation

/// Wie die offenen Board-Fenster im Fenster-Menü von macOS heissen.
///
/// Der Titel eines Fensters ist das, was macOS unter „Fenster" auflistet — ohne ihn stehen mehrere
/// Boards dort namenlos nebeneinander und man trifft das gemeinte nur durch Probieren. Er wird
/// deshalb gesetzt, obwohl die Titelleiste ihn nicht zeigt (`NSWindow.titleVisibility`): welches
/// Projekt ein Fenster zeigt, steht schon im Projekt-Menü der Kopfzeile, und zweimal dieselbe
/// Antwort im selben Fenster ist eine zu viel.
///
/// Reine Listenlogik, ohne AppKit — dieselbe Trennung wie bei `OpenProjects`: das Setzen gehört der
/// App (`ProjectWindows`), die Regel hierher, wo sie ohne Fenster prüfbar ist.
public enum WindowTitles {

    /// Ein Fenster ohne Projekt: Erststart, Setup-Schirm, Projekt aus der Config verschwunden. Es
    /// steht trotzdem im Menü, also braucht es einen Namen — ein leerer Eintrag wäre genau das
    /// Problem, das hier behoben wird.
    public static let ohneProjekt = "Kanban"

    /// Die Titel zu den Projekt-Keys der offenen Fenster, in derselben Reihenfolge.
    ///
    /// Dasselbe Projekt darf zweimal dastehen — das Projekt-Menü schaltet **im** Fenster um, ohne
    /// ein zweites aufzumachen. Zwei gleich benannte Einträge im Fenster-Menü wären aber nicht
    /// auseinanderzuhalten, deshalb zählt das zweite und jedes weitere mit: `EVEN`, `EVEN (2)`.
    /// Das erste bleibt schmucklos — eine „(1)" an einem Fenster, das allein dasteht, behauptete
    /// ein zweites, das es nicht gibt.
    ///
    /// Gezählt wird über die ganze Liste, nicht je Fenster: geht `EVEN (2)` zu, heisst das übrige
    /// wieder schlicht `EVEN`.
    public static func titel(fuer keys: [String?]) -> [String] {
        var gesehen: [String: Int] = [:]
        return keys.map { key in
            let name = key?.trimmingCharacters(in: .whitespaces).uppercased()
            guard let name, !name.isEmpty else { return ohneProjekt }
            let nummer = (gesehen[name] ?? 0) + 1
            gesehen[name] = nummer
            return nummer == 1 ? name : "\(name) (\(nummer))"
        }
    }
}
