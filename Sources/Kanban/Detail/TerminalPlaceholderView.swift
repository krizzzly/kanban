import SwiftUI

/// Shown in the terminal zone while the tmux session for a ticket is being resolved/created, or
/// when tmux is unavailable. Once `AppModel.activeTerminalSession` is set, the real terminal
/// (`TerminalContainerView`) replaces this.
struct TerminalPlaceholderView: View {
    let ticketKey: String?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 8) {
                if ticketKey != nil {
                    ProgressView().controlSize(.small)
                }
                Image(systemName: "terminal")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text(ticketKey == nil ? "Terminal-Zone" : "Terminal wird gestartet…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if ticketKey != nil {
                    Text("Falls dies bestehen bleibt: tmux nicht gefunden.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .overlay(alignment: .top) { Divider() }
    }
}
