import SwiftUI
import KanbanCore

/// One changed file, shared by the flat list and the tree.
struct ChangedFileRow: View {
    let file: GitChangedFile
    /// The folder line under the name — off in the tree, where the folder is already the parent row.
    var showPath = true
    /// Haken „geht in den Commit". **nil = kein Haken** — im Reiter „Diff" wird nur gelesen, dort
    /// wäre ein Kästchen, das nichts bewirkt, schlimmer als keins.
    var included: Binding<Bool>?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let included {
                Toggle("", isOn: included)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(included.wrappedValue
                          ? "Wird mitcommittet — abwählen lässt sie draussen"
                          : "Bleibt draussen: die Änderung bleibt im Arbeitsverzeichnis stehen")
            }
            Text(file.marker)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text((file.path as NSString).lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                let dir = showPath ? (file.path as NSString).deletingLastPathComponent : ""
                if !dir.isEmpty {
                    Text(dir)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(included?.wrappedValue == false ? 0.45 : 1)
        .help(file.path)
    }

    private var markerColor: Color {
        switch file.marker {
        case "A", "?": return .green
        case "D": return .red
        case "R": return .purple
        default: return .orange
        }
    }
}

/// The changed files as a folder tree, fully expanded.
///
/// `List(children:)` would be shorter but gives no control over the disclosure state — it opens
/// collapsed. `DisclosureGroup` with an explicit expansion set lets every folder start open, which is
/// what you want in a commit dialog: nothing hidden behind a triangle.
struct FileTreeView: View {
    let files: [GitChangedFile]
    @Binding var selection: String?
    /// Pfad → „geht in den Commit". nil im reinen Leseblick (Reiter „Diff").
    var inclusion: ((String) -> Binding<Bool>)?
    @State private var expanded: Set<String> = []

    private var tree: [FileTreeNode] { FileTreeBuilder.build(files) }

    var body: some View {
        List(selection: $selection) {
            FileTreeRows(nodes: tree, expanded: $expanded, inclusion: inclusion)
        }
        .listStyle(.sidebar)
        .onAppear { expandAll() }
        .onChange(of: files) { _, _ in expandAll() }
    }

    private func expandAll() {
        expanded = FileTreeBuilder.folderIDs(tree)
    }
}

/// Recursive rows. A separate view because a `@ViewBuilder` function cannot call itself — the return
/// type would be infinitely nested; a `View` struct can.
private struct FileTreeRows: View {
    let nodes: [FileTreeNode]
    @Binding var expanded: Set<String>
    let inclusion: ((String) -> Binding<Bool>)?

    var body: some View {
        ForEach(nodes) { node in
            if let file = node.file {
                ChangedFileRow(file: file, showPath: false, included: inclusion?(file.path))
                    .tag(file.path)
            } else {
                DisclosureGroup(isExpanded: binding(for: node.id)) {
                    FileTreeRows(nodes: node.children ?? [], expanded: $expanded, inclusion: inclusion)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(node.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text("\(node.fileCount)")
                            .font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            })
    }
}
