import Foundation

/// Ein Eintrag im Knowledgebase-Baum: Ordner oder Datei.
///
/// Der Baum wird **gelesen, nicht verwaltet** — die Knowledgebase gehört jemand anderem (ein Repo
/// mit Markdown und generierten HTML-Artefakten). Kanban zeigt sie nur an, deshalb gibt es hier
/// keine Änderungsoperationen und keinen Zustand ausser dem, was auf der Platte steht.
public struct KBNode: Identifiable, Hashable, Sendable {
    /// Absoluter Pfad — zugleich die Identität in Liste und Auswahl.
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let children: [KBNode]

    public var id: String { path }

    public init(path: String, name: String, isDirectory: Bool, children: [KBNode] = []) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }

    /// Dateien im ganzen Teilbaum — die Zahl neben dem Ordner.
    public var fileCount: Int {
        isDirectory ? children.reduce(0) { $0 + $1.fileCount } : 1
    }

    public var kind: KBFileKind { KBFileKind(path: path) }
}

/// Womit eine Datei angezeigt wird. Die Knowledgebase besteht fast ganz aus Markdown; daneben
/// stehen die generierten HTML-Artefakte (`artefacts/`), die ihr eigenes Layout mitbringen und
/// deshalb in eine Web-Ansicht gehören statt durch den Markdown-Renderer.
public enum KBFileKind: String, Sendable {
    case markdown
    case html
    case text
    case binary

    /// Bekannt **binär** — alles andere gilt als Text. Andersherum (eine Liste erlaubter
    /// Text-Endungen) ginge es nicht: über einen Link landet man in Dateien des Projekt-Repos, und
    /// deren Endungen sind nicht aufzählbar (`.php`, `.twig`, `.lua`, `.dist`, `.lock`, gar keine).
    /// Was trotzdem binär ist, fällt beim Lesen auf (Null-Bytes), nicht an der Endung.
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "ico", "icns", "svgz",
        "pdf", "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "jar", "war",
        "mp3", "mp4", "mov", "avi", "mkv", "wav", "aac", "m4a", "webm",
        "woff", "woff2", "ttf", "otf", "eot",
        "xlsx", "xls", "docx", "doc", "pptx", "ppt", "key", "numbers", "pages",
        "sqlite", "db", "bin", "exe", "dll", "dylib", "so", "o", "a", "class", "pyc",
    ]

    public init(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "html", "htm": self = .html
        case let ext where Self.binaryExtensions.contains(ext): self = .binary
        default: self = .text
        }
    }
}

public enum KnowledgebaseTree {
    /// Was nie in den Baum gehört: Werkzeug-Ordner und Betriebssystem-Krempel. Alles andere bleibt
    /// drin — auch `_build/` und `assets/`, denn was zur Knowledgebase gehört, entscheidet die, der
    /// sie schreibt, nicht diese Liste.
    static let ignoredNames: Set<String> = [
        ".git", ".idea", ".vscode", ".svn", "node_modules", "__pycache__", ".DS_Store",
    ]

    /// Backstop gegen einen Baum, der sich nicht schliesst (verschachtelte Symlinks, ein
    /// versehentlich in die KB gelegtes Repo). Eine Dokumentation ist flach; 12 Ebenen sieht keine.
    static let maxDepth = 12

    /// Liest den Ordner rekursiv ein. Ordner zuerst, dann Dateien, beides natürlich sortiert
    /// (`README.md` vor `_anhang.md` wäre lexikografisch andersherum).
    ///
    /// **Leere Ordner fallen weg**: ein Ordner, unter dem nach dem Filtern keine Datei mehr liegt,
    /// ist in einer Leseansicht nur ein Dreieck, hinter dem nichts steht.
    public static func build(root: String, fileManager: FileManager = .default) -> [KBNode] {
        children(of: root, depth: 0, fileManager: fileManager)
    }

    private static func children(of directory: String, depth: Int,
                                 fileManager: FileManager) -> [KBNode] {
        guard depth < maxDepth,
              let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }

        var folders: [KBNode] = []
        var files: [KBNode] = []

        for name in names {
            if name.hasPrefix(".") || ignoredNames.contains(name) { continue }
            let path = (directory as NSString).appendingPathComponent(name)

            // Symlinks werden nicht verfolgt: ein Link zurück auf einen Vorfahren wäre eine
            // Endlosschleife, und ein Link nach draussen zeigt Dateien, die nicht zur KB gehören.
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { continue }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let sub = children(of: path, depth: depth + 1, fileManager: fileManager)
                guard !sub.isEmpty else { continue }
                folders.append(KBNode(path: path, name: name, isDirectory: true, children: sub))
            } else {
                files.append(KBNode(path: path, name: name, isDirectory: false))
            }
        }

        let byName: (KBNode, KBNode) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return folders.sorted(by: byName) + files.sorted(by: byName)
    }

    /// Die Ordner **auf dem Weg** zu einer Datei — ohne sie steht die Auswahl hinter zugeklappten
    /// Dreiecken und man sieht rechts einen Inhalt, dessen Zeile links nirgends zu finden ist.
    ///
    /// Bewusst nicht „alle Ordner aufklappen" wie im Commit-Dialog: der zeigt die Handvoll Dateien
    /// eines Commits, eine Knowledgebase 365 Dateien in 130 Ordnern. Vollständig ausgeklappt wäre
    /// die Liste eine Wand, durch die man scrollt, statt eines Baums, in dem man navigiert.
    public static func ancestorFolderIDs(of path: String, in nodes: [KBNode]) -> Set<String> {
        for node in nodes {
            if node.path == path { return [] }
            if node.isDirectory, path.hasPrefix(node.path + "/") {
                var ids: Set<String> = [node.id]
                ids.formUnion(ancestorFolderIDs(of: path, in: node.children))
                return ids
            }
        }
        return []
    }

    /// Die Datei, mit der die **Ansicht** aufgeht: `artefacts/index.html`, wenn es sie gibt.
    ///
    /// Das ist die gebaute Übersichtsseite der Knowledgebase — sie verweist auf die übrigen
    /// Artefakte und ist damit der Einstieg, den man ohne den Baum braucht (der steht jetzt
    /// standardmässig zu, siehe `KnowledgebaseView`). Getrennt von `landingFile`, weil das eine
    /// andere Frage beantwortet: dort geht es um den Einstieg **eines Ordners**, auf den ein Link
    /// zeigt — für den ist die Artefakt-Übersicht des ganzen Baums die falsche Antwort.
    ///
    /// Ohne Artefakt-Ordner gilt weiter `README`/`index` auf oberster Ebene.
    public static func entryFile(_ nodes: [KBNode]) -> KBNode? {
        let artefacts = nodes.first {
            $0.isDirectory && artefactFolderNames.contains($0.name.lowercased())
        }
        if let index = artefacts.flatMap({ indexFile($0.children) }) { return index }
        return landingFile(nodes)
    }

    /// Beide Schreibweisen desselben Wortes — der Ordnername gehört der Knowledgebase, nicht Kanban,
    /// und an einer Buchstabenwahl soll der Einstieg nicht hängen.
    static let artefactFolderNames: Set<String> = ["artefacts", "artifacts"]

    private static func indexFile(_ nodes: [KBNode]) -> KBNode? {
        nodes.first {
            !$0.isDirectory && $0.kind != .binary
                && ($0.name as NSString).deletingPathExtension.lowercased() == "index"
        }
    }

    /// Der Einstieg **eines Ordners**: eine `README`/`index` darin — eine Knowledgebase hat fast
    /// immer einen, und ein leeres rechtes Feld ist kein guter erster Eindruck. Wird für Links auf
    /// einen Ordner gebraucht (`../Common/`) und als Rückfall von `entryFile`.
    public static func landingFile(_ nodes: [KBNode]) -> KBNode? {
        let topLevelFiles = nodes.filter { !$0.isDirectory }
        let preferred = topLevelFiles.first {
            let stem = ($0.name as NSString).deletingPathExtension.lowercased()
            return (stem == "readme" || stem == "index") && $0.kind != .binary
        }
        return preferred ?? firstFile(nodes)
    }

    /// Erste Datei in Baum-Reihenfolge, die sich anzeigen lässt.
    public static func firstFile(_ nodes: [KBNode]) -> KBNode? {
        for node in nodes {
            if node.isDirectory {
                if let found = firstFile(node.children) { return found }
            } else if node.kind != .binary {
                return node
            }
        }
        return nil
    }

    /// Der Knoten zu einem Pfad — für die Auswahl, die als Pfad durch die Liste läuft.
    public static func node(at path: String, in nodes: [KBNode]) -> KBNode? {
        for node in nodes {
            if node.path == path { return node }
            if node.isDirectory, let found = self.node(at: path, in: node.children) { return found }
        }
        return nil
    }
}
