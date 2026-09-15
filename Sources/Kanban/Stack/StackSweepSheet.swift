import SwiftUI
import KanbanCore

/// „Stacks stoppen": listet jeden laufenden Worktree-Stack des Projekts samt der Spalte seines
/// Tickets und stoppt die gewählten per `iwf worktree stop <NR>`.
///
/// Bewusst **eine Bestätigung mit Liste** statt einer stillen Automatik beim Spaltenwechsel: in
/// Review wird nachgebessert, und ein Stack, der unter einem laufenden Test verschwindet, kostet
/// mehr als er spart. Was hier passiert, ist dafür harmlos und umkehrbar — Container und Netzwerk
/// gehen runter, Worktree, Branch, Image und DB-Volume bleiben stehen.
struct StackSweepSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Zweite Bestätigung, sobald Volumes/Images mitgelöscht werden — stoppen ist reversibel,
    /// löschen nicht (nur über den bereitgestellten Dump).
    @State private var confirmDeep = false

    private var plan: StackSweepPlan { model.stackSweep }
    private var finished: [StackSweepCandidate] { plan.candidates.filter(\.isFinished) }
    private var others: [StackSweepCandidate] { plan.candidates.filter { !$0.isFinished } }
    private var selectedCount: Int { model.stackSweepSelection.count }
    /// Tief abzuräumende Stacks — immer eine Teilmenge der Auswahl.
    private var deepTargets: [StackSweepCandidate] {
        plan.candidates.filter {
            model.stackSweepSelection.contains($0.stackName) && model.stackSweepDeep.contains($0.stackName)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if plan.candidates.isEmpty {
                empty
            } else {
                list
            }
            if !model.stackSweepOutput.isEmpty {
                Divider()
                outputBox
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 620)
        .task { await model.loadStackSweep() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.down.right").foregroundStyle(.secondary)
                Text("Stacks stoppen").font(.app(.headline))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Text("`iwf worktree stop` fährt Container und Netzwerk runter; Worktree und Branch "
                 + "bleiben, `iwf worktree start <NR>` bringt den Stack zurück. **Tief** löscht "
                 + "zusätzlich die Volumes und Image-Tags des Stacks — das ist der Teil, der Platte "
                 + "freigibt, und er geht nur mit bereitgestelltem DB-Dump.")
                .font(.app(.caption)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.fill").font(.system(size: 34)).foregroundStyle(.green)
            Text("Kein Stack läuft").font(.app(.headline))
            Text("Zu keinem Worktree dieses Projekts läuft gerade ein Container.")
                .font(.app(.callout)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !finished.isEmpty {
                    sectionTitle("FERTIG — REVIEW UND DONE")
                    ForEach(finished) { row($0) }
                }
                if !others.isEmpty {
                    // Nicht vorgewählt, aber sichtbar: der eigentliche Grund, warum die Maschine
                    // voll ist, sind oft Stacks, deren Ticket gar nicht auf dem Board liegt.
                    sectionTitle("NOCH IN ARBEIT ODER NICHT AUF DEM BOARD")
                    ForEach(others) { row($0) }
                }
                if !plan.orphanStacks.isEmpty {
                    sectionTitle("OHNE WORKTREE — NICHT ÜBER IWF ERREICHBAR")
                    Text(plan.orphanStacks.joined(separator: ", "))
                        .font(.app(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                    Text("Diese Container laufen ohne zugehörigen Worktree. `iwf worktree stop` "
                         + "greift dort nicht — von Hand über `docker` stoppen.")
                        .font(.app(.caption)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
    }

    private func row(_ candidate: StackSweepCandidate) -> some View {
        let selected = model.stackSweepSelection.contains(candidate.stackName)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected },
                set: { on in
                    if on {
                        model.stackSweepSelection.insert(candidate.stackName)
                    } else {
                        // Abwählen nimmt die Tiefen-Markierung mit: ein „tief" auf einer nicht
                        // gewählten Zeile wäre ein Häkchen ohne Wirkung.
                        model.stackSweepSelection.remove(candidate.stackName)
                        model.stackSweepDeep.remove(candidate.stackName)
                    }
                }))
                .labelsHidden()
                .disabled(model.stackSweepBusy)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.stackName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                HStack(spacing: 6) {
                    Text(candidate.ticketKey ?? "keine Karte auf dem Board")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                    if let column = candidate.column {
                        Text(column.rawValue)
                            .font(.app(.caption))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(columnTint(column).opacity(0.18), in: Capsule())
                            .foregroundStyle(columnTint(column))
                    }
                    if candidate.isWorking {
                        Label("Turn läuft", systemImage: "circle.fill")
                            .font(.app(.caption)).foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                            .help("Die Claude-Console dieses Tickets arbeitet gerade — deshalb nicht vorgewählt.")
                    }
                }
            }
            Spacer(minLength: 8)
            Text("\(candidate.runningContainers) Container")
                .font(.app(.caption)).foregroundStyle(.tertiary).monospacedDigit()
            deepToggle(candidate, rowSelected: selected)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    /// Der Tief-Schalter je Zeile. Ohne bereitgestellten Dump bleibt er aus und sagt warum — die
    /// DB käme sonst nicht zurück. Ohne gewählte Zeile ebenfalls: tief abräumen ohne stoppen gibt es
    /// nicht, Docker gibt ein Volume mit Containern daran nicht her.
    @ViewBuilder
    private func deepToggle(_ candidate: StackSweepCandidate, rowSelected: Bool) -> some View {
        let on = model.stackSweepDeep.contains(candidate.stackName)
        HStack(spacing: 4) {
            Toggle("", isOn: Binding(
                get: { on },
                set: { value in
                    if value { model.stackSweepDeep.insert(candidate.stackName) }
                    else { model.stackSweepDeep.remove(candidate.stackName) }
                }))
                .labelsHidden()
                .disabled(!candidate.canDeepClean || !rowSelected || model.stackSweepBusy)
            Text("tief")
                .font(.app(.caption))
                .foregroundStyle(candidate.canDeepClean && rowSelected ? .secondary : .tertiary)
        }
        .frame(width: 62, alignment: .trailing)
        .help(candidate.canDeepClean
              ? "\(candidate.volumes.count) Volumes + \(candidate.imageTags.count) Image-Tags löschen. "
                + "DB kommt beim nächsten Start aus \(candidate.stagedDump ?? "") zurück."
              : "Kein DB-Dump im Worktree bereitgestellt — ein gelöschtes Volume käme nicht zurück. "
                + "Erst im Worktree-Panel einen Dump bereitstellen.")
    }

    private func columnTint(_ column: KanbanColumn) -> Color {
        switch column {
        case .done: return .green
        case .review: return .blue
        case .inBearbeitung: return .orange
        default: return .secondary
        }
    }

    /// Dieselbe Log-Ansicht wie im Stack-Panel — der Sweep streamt genauso (siehe `LogTextView`).
    private var outputBox: some View {
        LogTextView(text: model.stackSweepOutput)
            .frame(height: 160)
            .background(CodeTheme.background)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.stackSweepBusy {
                ProgressView().controlSize(.small)
                Text("Stoppe…").font(.app(.caption)).foregroundStyle(.secondary)
            } else if !plan.candidates.isEmpty {
                Button("Alle fertigen") {
                    model.stackSweepSelection = plan.preselected
                    model.stackSweepDeep.formIntersection(plan.preselected)
                }
                .buttonStyle(.link)
                .disabled(plan.preselected.isEmpty)
                Button("Keine") { model.stackSweepSelection = []; model.stackSweepDeep = [] }
                    .buttonStyle(.link)
                    .disabled(selectedCount == 0)
            }
            Spacer()
            Button("Schliessen") { dismiss() }
            Button(actionLabel) {
                if deepTargets.isEmpty { model.runStackSweep() } else { confirmDeep = true }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0 || model.stackSweepBusy)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .confirmationDialog("\(deepTargets.count) Stack(s) tief abräumen?",
                            isPresented: $confirmDeep, titleVisibility: .visible) {
            Button("Volumes + Images löschen", role: .destructive) { model.runStackSweep() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text(deepMessage)
        }
    }

    private var actionLabel: String {
        let stop = selectedCount == 1 ? "1 Stack stoppen" : "\(selectedCount) Stacks stoppen"
        return deepTargets.isEmpty ? stop : "\(stop) · \(deepTargets.count)× tief"
    }

    /// Nennt die Artefakte namentlich — bei einer Löschung gehört auf den Bildschirm, was weg ist,
    /// nicht nur wie viele es sind.
    private var deepMessage: String {
        let volumes = deepTargets.flatMap(\.volumes)
        let images = deepTargets.flatMap(\.imageTags)
        return """
        Gelöscht werden \(volumes.count) Volumes und \(images.count) Image-Tags:
        \(volumes.joined(separator: ", "))
        \(images.joined(separator: ", "))

        Die Datenbank kommt beim nächsten Start aus dem bereitgestellten Dump zurück, das Image über         `iwf stack build`. Worktree und Branch bleiben unangetastet.
        """
    }
}
