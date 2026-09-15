import AppKit
import SwiftUI
import KanbanCore

extension Color {
    /// The running-turn green. Darker than the system green, which washes out on the light card
    /// background; lifted again in dark mode, where a deep green would sink into the background.
    static let claudeRunning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.34, green: 0.74, blue: 0.45, alpha: 1)
            : NSColor(srgbRed: 0.05, green: 0.44, blue: 0.20, alpha: 1)
    })
}

/// Cumulated Claude time on a board card: ⏱ + the total. While a turn runs it turns green and ticks,
/// so a busy console is recognisable from the board without opening the ticket.
struct ClaudeTimeBadge: View {
    /// Cumulated total as of the last model refresh.
    let seconds: TimeInterval
    /// The same total without the running turn — the live counter ticks on top of this.
    let baseSeconds: TimeInterval
    let runningSince: Date?
    /// True once every measured second is booked to Jira — shown as a small ✓ next to the time.
    var fullyBooked: Bool = false

    var body: some View {
        if let runningSince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(for: baseSeconds + max(0, context.date.timeIntervalSince(runningSince)), running: true)
            }
        } else {
            label(for: seconds, running: false)
        }
    }

    private func label(for value: TimeInterval, running: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: running ? "timer" : "clock")
            Text(TimeFormatting.compact(value))
            // ✓ only when settled and fully booked — never competes with the live green counter.
            if fullyBooked && !running {
                Image(systemName: "checkmark").font(.app(.caption2)).foregroundStyle(.green)
            }
        }
        .font(.app(.caption2))
        .foregroundStyle(running ? Color.claudeRunning : Color.secondary)
        .help(running ? "Claude arbeitet — kumulierte Zeit dieses Tickets"
                      : fullyBooked ? "Kumulierte Claude-Zeit — vollständig in Jira gebucht"
                                    : "Kumulierte Claude-Zeit (Prompt → Antwort) dieses Tickets")
    }
}

/// Detail-header chip: cumulated time of the open ticket, the live turn clock while Claude answers,
/// and — on click — the per-turn breakdown plus the booking sub-section.
struct ClaudeTimeChip: View {
    @Bindable var model: AppModel
    let ticketKey: String
    let timing: ClaudeSessionTiming
    let runningSince: Date?
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            label.font(.app(.subheadline))
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Kumulierte Claude-Zeit: \(timing.turnCount) Turns, ⌀ \(TimeFormatting.compact(timing.average ?? 0)) — klicken für die Turn-Liste")
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            ClaudeTimeDetails(model: model, ticketKey: ticketKey, timing: timing, runningSince: runningSince)
        }
    }

    /// Cumulated total, plus the running turn's own clock in green. While a turn runs both move: the
    /// total counts it up live, the clock says how long *this* answer has been going.
    @ViewBuilder
    private var label: some View {
        if let runningSince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                    Text(TimeFormatting.compact(timing.total(runningSince: runningSince, now: context.date)))
                    Text("·").foregroundStyle(.tertiary)
                    Text(TimeFormatting.clock(max(0, context.date.timeIntervalSince(runningSince))))
                        .monospacedDigit().foregroundStyle(Color.claudeRunning)
                }
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(TimeFormatting.compact(timing.total))
            }
        }
    }
}

/// Popover content: the session's totals, the booking sub-section, and every measured turn.
struct ClaudeTimeDetails: View {
    @Bindable var model: AppModel
    let ticketKey: String
    let timing: ClaudeSessionTiming
    let runningSince: Date?

    /// „Mi 19.08." — kurz, aber mit Wochentag: beim Nachbuchen will man sehen, welcher Tag das war.
    static let dayLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "EE dd.MM."
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM. HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            summary
            Divider()
            bookingSection
            Divider()
            turnList
        }
        .frame(width: 420)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(.secondary)
            Text("Claude-Zeit").font(.app(.headline))
            Spacer()
            if let runningSince {
                HStack(spacing: 5) {
                    Circle().fill(Color.claudeRunning).frame(width: 7, height: 7)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("läuft · \(TimeFormatting.clock(max(0, context.date.timeIntervalSince(runningSince))))")
                            .monospacedDigit()
                    }
                }
                .font(.app(.caption)).foregroundStyle(Color.claudeRunning)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Gesamt (Prompt → Antwort)",
                TimeFormatting.compact(timing.total(runningSince: runningSince)), bold: true)
            row("Turns", "\(timing.turnCount)")
            if let average = timing.average { row("⌀ pro Turn", TimeFormatting.compact(average)) }
            if let longest = timing.longest {
                row("Längster Turn", TimeFormatting.compact(longest.seconds))
            }
            if timing.wallTotal - timing.total > 60 {
                row("Inkl. Wartezeit auf dich", TimeFormatting.compact(timing.wallTotal))
            }
            if let last = timing.lastActivity {
                row("Letzte Aktivität", Self.time.string(from: last))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// "Gebuchte Zeit": what is already booked, what is still open, and the button that books it.
    /// Aufgerundet wird je **Tag** auf 15 min, und gebucht wird auf den Arbeitstag — deshalb steht
    /// hier die Tagesliste und nicht nur eine Summe. Ist nichts Neues gearbeitet, bleibt der Knopf
    /// aus; dieselbe Zeit kann nicht zweimal gebucht werden.
    private var bookingSection: some View {
        let booked = model.bookedSeconds(ticketKey: ticketKey)
        let days = model.dailyBookings(ticketKey: ticketKey)
        let open = days.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gebuchte Zeit").font(.app(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let last = model.lastBookedAt(ticketKey: ticketKey) {
                    Text("zuletzt \(Self.time.string(from: last))")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
            row("Gebucht", TimeFormatting.compact(booked))
            row("Offen zum Buchen", open > 0 ? TimeFormatting.compact(open) : "—")

            // Auf welche Tage gebucht wird — je Zeile ein eigener Worklog-Eintrag in Jira.
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(days) { day in
                        HStack(spacing: 6) {
                            Text(Self.dayLabel.string(from: day.day))
                                .font(.app(.caption)).foregroundStyle(.secondary)
                                .frame(width: 74, alignment: .leading)
                            Text(TimeFormatting.compact(day.seconds))
                                .font(.app(.caption)).monospacedDigit()
                            if day.seconds > day.measuredSeconds {
                                Text("(gemessen \(TimeFormatting.compact(day.measuredSeconds)))")
                                    .font(.app(.caption2)).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.leading, 2)
            }

            Button {
                Task { await model.bookTime(ticketKey: ticketKey) }
            } label: {
                HStack(spacing: 6) {
                    if model.bookingBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: open > 0 ? "clock.badge.checkmark" : "checkmark.circle")
                    }
                    Text(open > 0 ? "\(TimeFormatting.compact(open)) auf \(ticketKey) buchen"
                                  : "Alles gebucht")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(open <= 0 || model.bookingBusy)
            .help("Bucht die offene Zeit als Jira-Worklog — ein Eintrag je Arbeitstag, "
                + "je Tag auf 15 min aufgerundet")

            if let error = model.bookingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption)).foregroundStyle(.orange).lineLimit(3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.app(.callout)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.app(.callout, weight: bold ? .semibold : .regular))
                .monospacedDigit()
        }
    }

    private var turnList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Turns (neueste zuerst)")
                .font(.app(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(timing.turns.reversed()) { turn in
                        turnRow(turn)
                        Divider().opacity(0.4)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func turnRow(_ turn: ClaudeTurn) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.time.string(from: turn.start))
                .font(.app(.caption)).monospacedDigit().foregroundStyle(.secondary)
            Text(turn.prompt.isEmpty ? "—" : turn.prompt)
                .font(.app(.caption)).lineLimit(2).foregroundStyle(.primary)
            Spacer(minLength: 8)
            // "≈" marks a turn Claude never wrote a duration for (interrupted, or an older Claude
            // version) — its time is the span between the prompt and the last entry of the answer.
            Text((turn.isExact ? "" : "≈") + TimeFormatting.compact(turn.seconds))
                .font(.app(.caption)).monospacedDigit()
                .foregroundStyle(turn.id == timing.openTurn?.id && runningSince != nil
                                 ? Color.claudeRunning : Color.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .help(turn.isExact ? "" : "Geschätzt: Claude hat für diesen Turn keine Dauer aufgezeichnet")
    }
}
