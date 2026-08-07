import Foundation

/// A node of the changed-files tree: either a folder (with children) or a changed file (a leaf).
public struct FileTreeNode: Identifiable, Sendable, Hashable {
    public let id: String            // full path — unique within one tree
    public let name: String          // what the row shows
    public let file: GitChangedFile? // nil for folders
    public let children: [FileTreeNode]?

    public var isFolder: Bool { file == nil }

    public init(id: String, name: String, file: GitChangedFile?, children: [FileTreeNode]?) {
        self.id = id
        self.name = name
        self.file = file
        self.children = children
    }

    /// Number of changed files below this node (1 for a file).
    public var fileCount: Int {
        guard let children else { return 1 }
        return children.reduce(0) { $0 + $1.fileCount }
    }
}

/// Builds the folder tree the commit dialog shows when the flat list gets long.
public enum FileTreeBuilder {
    /// Folders first, then files, each alphabetically — the order a file browser uses.
    /// Single-child folder chains are collapsed into one row (`src/Controller/Api/Pendenz`), so deep
    /// PHP/JS paths do not cost four rows of indentation to say nothing.
    public static func build(_ files: [GitChangedFile]) -> [FileTreeNode] {
        guard !files.isEmpty else { return [] }
        return nodes(for: files.map { (segments: $0.path.split(separator: "/").map(String.init), file: $0) },
                     prefix: "")
    }

    private struct Entry {
        let segments: [String]
        let file: GitChangedFile
    }

    private static func nodes(for entries: [(segments: [String], file: GitChangedFile)],
                              prefix: String) -> [FileTreeNode] {
        var folders: [String: [(segments: [String], file: GitChangedFile)]] = [:]
        var folderOrder: [String] = []
        var leaves: [FileTreeNode] = []

        for entry in entries {
            guard let head = entry.segments.first else { continue }
            if entry.segments.count == 1 {
                leaves.append(FileTreeNode(id: entry.file.path, name: head,
                                           file: entry.file, children: nil))
            } else {
                if folders[head] == nil { folderOrder.append(head) }
                folders[head, default: []].append((Array(entry.segments.dropFirst()), entry.file))
            }
        }

        var result: [FileTreeNode] = folderOrder.sorted().map { name in
            let path = prefix.isEmpty ? name : prefix + "/" + name
            var displayName = name
            var children = nodes(for: folders[name] ?? [], prefix: path)
            // Collapse a chain of folders that each hold exactly one folder and nothing else.
            while children.count == 1, let only = children.first, only.isFolder {
                displayName += "/" + only.name
                children = only.children ?? []
            }
            return FileTreeNode(id: path, name: displayName, file: nil, children: children)
        }
        result.append(contentsOf: leaves.sorted { $0.name < $1.name })
        return result
    }

    /// Every folder id in the tree — the dialog expands all of them by default, so nothing is hidden.
    public static func folderIDs(_ nodes: [FileTreeNode]) -> Set<String> {
        var result: Set<String> = []
        for node in nodes where node.isFolder {
            result.insert(node.id)
            result.formUnion(folderIDs(node.children ?? []))
        }
        return result
    }
}
