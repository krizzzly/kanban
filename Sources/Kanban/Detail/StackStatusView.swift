import SwiftUI
import KanbanCore

/// The stack's derived state: one row per pipeline phase, then one row per container.
///
/// Replaces reading `iwf stack ps` as raw text. Two things were invisible there and are the point of
/// this view: a container that exited with a non-zero code (`keycloak Exited (134)`) looks like any
/// other line in that output, and a missing image — the usual aftermath of a failed build — could not
/// be seen at all, because the build failure happens long before `stack ps` has anything to say.
struct StackStatusView: View {
    let status: WorktreeStackStatus
    let isLoading: Bool
    /// Runs the repair a row offers. Nil disables the buttons (while a command is running).
    let onRepair: ((StackPhase.Repair) -> Void)?
    /// Seed-Aktionen brauchen erst eine Quelle (dev/qa/prod/Datei) — deshalb ein eigener Callback.
    /// `importNow` unterscheidet Direktimport von Bereitstellen.
    let onSeed: ((StackSeeder.Source?, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            phaseSection
            if !status.services.isEmpty { serviceSection }
        }
    }

    // MARK: - Phases

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Stack-Aufbau")
            ForEach(status.phases) { phase in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    icon(for: phase.state)
                    Text(phase.title)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 92, alignment: .leading)
                    Text(detail(for: phase.state))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(detail(for: phase.state))
                    Spacer(minLength: 4)
                    // Aktion direkt an der Zeile, die sie betrifft.
                    if let repair = phase.repair {
                        if repair.needsSource {
                            seedMenu(repair)
                        } else {
                            Button(repair.label) { onRepair?(repair) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(onRepair == nil)
                                .help("iwf \(repair.arguments.joined(separator: " ")) im Worktree")
                        }
                    }
                }
            }
        }
    }

    /// Quellenwahl für die beiden Seed-Aktionen: Remote-Umgebung oder lokale Datei.
    private func seedMenu(_ repair: StackPhase.Repair) -> some View {
        let importNow = repair == .seedImport
        return Menu {
            ForEach(["dev", "qa", "prod"], id: \.self) { env in
                Button("von \(env)") { onSeed?(.remote(env), importNow) }
            }
            Divider()
            Button("aus Datei…") { onSeed?(nil, importNow) }   // nil → Dateidialog beim Aufrufer
        } label: {
            Text(repair.label)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .disabled(onSeed == nil)
        .help(importNow
              ? "Dump direkt in die laufende DB importieren (Snapshot wird vorher angelegt)"
              : "Dump herunterladen und im Init-Ordner ablegen (Import beim nächsten Start)")
    }

    @ViewBuilder
    private func icon(for state: StackPhase.State) -> some View {
        switch state {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
        case .missing:
            Image(systemName: "circle.dashed").foregroundStyle(.orange).font(.system(size: 12))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 12))
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).font(.system(size: 12))
        }
    }

    private func detail(for state: StackPhase.State) -> String {
        switch state {
        case .ok(let text), .missing(let text), .warning(let text): return text
        case .unknown: return "unbekannt"
        }
    }

    // MARK: - Services

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Dienste (\(status.running.count)/\(status.services.count))")
            ForEach(status.services) { service in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: service))
                        .frame(width: 7, height: 7)
                    Text(service.name)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 118, alignment: .leading)
                        .lineLimit(1)
                    Text(service.status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let code = service.exitCode, code != 0 {
                        Text("Exit \(code)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.red.opacity(0.75), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .help(service.container)
            }
        }
    }

    /// Grey for a one-shot helper that finished cleanly, red for a real failure, orange for
    /// unhealthy, green for running.
    private func color(for service: StackService) -> Color {
        if service.isRunning { return service.health == .unhealthy ? .orange : .green }
        if service.isFailed { return service.isOneShot ? .orange : .red }
        return .secondary
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if isLoading { ProgressView().controlSize(.small) }
        }
    }
}

extension WorktreeStackStatus.Verdict {
    var label: String {
        switch self {
        case .notCreated: return "nicht erstellt"
        case .stopped: return "gestoppt"
        case .degraded: return "beeinträchtigt"
        case .running: return "läuft"
        }
    }

    var color: Color {
        switch self {
        case .notCreated: return .secondary
        case .stopped: return .orange
        case .degraded: return .red
        case .running: return .green
        }
    }
}
