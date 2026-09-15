import SwiftUI
import KanbanCore

/// A collapsible lane, styled after kanban-code's `ListSectionHeader` + `ColumnView`:
/// a floating ultraThinMaterial header pill (accent dot · name · count · rotating chevron)
/// over a stack of cards.
struct ColumnSection: View {
    let column: KanbanColumn
    let cards: [CardVM]
    let isCollapsed: Bool
    let selectedKey: String?
    let onToggle: () -> Void
    let onSelect: (String) -> Void
    // Right-click menu: the ticket workflow commands; Review cards additionally offer
    // `/review-merge !<iid>` (the card's opened MR).
    let commands: [ClaudeCommand]
    /// `/` bei Claude, `$` bei Codex — die Karte zeigt, was sie tatsächlich tippt.
    let commandPrefix: String
    let onCommand: (CardVM, ClaudeCommand) -> Void
    let onReviewMerge: (CardVM, Int) -> Void
    /// Karte ohne Ticketnummer → „Task erstellen" mit Titel und Branch vorbelegt.
    let onCreateTask: (CardVM) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                if cards.isEmpty {
                    Text("Keine Tickets")
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(cards) { card in
                            TicketCard(card: card, isSelected: selectedKey == card.ticket.key)
                                .onTapGesture { onSelect(card.ticket.key) }
                                .contextMenu { contextMenu(for: card) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    /// Same entries as the detail header's Commands menu — selecting one types
    /// `<präfix>command <TICKET>` into the card's console (Enter is left to the user).
    @ViewBuilder
    private func contextMenu(for card: CardVM) -> some View {
        // Eine Karte ohne Nummer hat kein Ticket, auf das ein Workflow-Command zeigen könnte —
        // `/solve-task !139` gäbe es nirgends. Das eine, was hier zu tun ist, steht deshalb oben und
        // allein: aus dieser Arbeit einen richtigen Task machen.
        if card.ticket.isBranchOnly {
            Button {
                onCreateTask(card)
            } label: {
                Text("Task erstellen …")
                Text("Titel und Branch dieses Merge-Requests sind vorbelegt")
            }
            if card.openMergeRequestIid != nil { Divider() }
        } else {
            ForEach(commands) { command in
                Button {
                    onCommand(card, command)
                } label: {
                    Text("\(commandPrefix)\(command.name)")
                    if let description = command.description { Text(description) }
                }
            }
        }
        if let iid = card.openMergeRequestIid {
            if !commands.isEmpty && !card.ticket.isBranchOnly { Divider() }
            Button {
                onReviewMerge(card, iid)
            } label: {
                Text("\(commandPrefix)review-merge !\(iid)")
                Text("Code-Review des Merge-Requests — Nummer wird eingetragen")
            }
        }
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Circle()
                    .fill(column.accent)
                    .frame(width: 8, height: 8)

                Text(column.rawValue)
                    .font(.app(.headline))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(cards.count)")
                    .font(.app(.caption))
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.app(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
