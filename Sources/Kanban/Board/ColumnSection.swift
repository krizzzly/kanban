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
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
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
