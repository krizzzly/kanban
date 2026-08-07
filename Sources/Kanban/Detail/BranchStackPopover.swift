import SwiftUI
import KanbanCore

/// Kleines abgeleitetes Schaubild: jeder Worktree-Branch unter seinem Parent, bis hinunter zur
/// langlebigen Basis (develop/main). Chips wie in der Link-Bar; Klick öffnet den Branch auf GitLab.
struct BranchStackPopover: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                Text("BRANCH-HIERARCHIE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
                if model.branchStackLoading { ProgressView().controlSize(.mini) }
            }
            if let tree = model.branchStack {
                let ancestors = currentPath(in: tree)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(flatten(tree), id: \.node.id) { row in
                        HStack(spacing: 4) {
                            if row.depth > 0 {
                                Text(String(repeating: "   ", count: row.depth - 1) + "└─")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            chip(row.node, depth: row.depth, ancestors: ancestors)
                            if row.node.ahead > 0 {
                                Text("+\(row.node.ahead)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .help("\(row.node.ahead) eigene Commits gegenüber dem Parent")
                            }
                        }
                    }
                }
            } else if model.branchStackLoading {
                Text("Hierarchie wird aus der Git-Historie abgeleitet…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Keine Basis (develop/main) gefunden.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 320, maxWidth: 520, alignment: .leading)
        .task { await model.loadBranchStack() }
    }

    // MARK: Baum → Zeilen

    private func flatten(_ node: BranchStackNode, depth: Int = 0) -> [(node: BranchStackNode, depth: Int)] {
        [(node, depth)] + node.children.flatMap { flatten($0, depth: depth + 1) }
    }

    /// Namen auf dem Pfad Wurzel → aktueller Branch, für die Hervorhebung der eigenen Kette.
    private func currentPath(in tree: BranchStackNode) -> Set<String> {
        guard let current = model.currentWorktree?.branch,
              let path = tree.path(to: current) else { return [] }
        return Set(path.map(\.name))
    }

    // MARK: Chip

    private func chip(_ node: BranchStackNode, depth: Int, ancestors: Set<String>) -> some View {
        let isCurrent = node.name == model.currentWorktree?.branch
        let tint: Color = isCurrent ? .purple
            : depth == 0 ? .secondary
            : ancestors.contains(node.name) ? .orange
            : .gray
        return Button {
            if let url = model.branchURL(for: node.name) { StatusLinkOpener.open(url) }
        } label: {
            Text(shortName(node.name))
                .font(.system(size: 11, weight: isCurrent ? .semibold : .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(tint.opacity(isCurrent ? 0.22 : 0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(isCurrent ? 0.6 : 0.35), lineWidth: 1))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help("Auf GitLab öffnen: \(node.name)")
    }

    /// `feature/EVEN-3518_show_…` → `EVEN-3518_show_…` — das Präfix trägt im Schaubild nichts.
    private func shortName(_ name: String) -> String {
        name.hasPrefix("feature/") ? String(name.dropFirst("feature/".count)) : name
    }
}
