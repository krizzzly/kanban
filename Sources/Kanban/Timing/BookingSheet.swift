import SwiftUI
import KanbanCore

/// End-of-day batch booking: lists every ticket with open (unbooked) ⏱ time, the amount each would
/// book (je Arbeitstag auf 15 min aufgerundet), den Zeitraum und die Summe — then books them all on
/// confirm. Shown from the toolbar's "Zeit buchen" button. Nothing is written until the user confirms
/// here.
///
/// Gebucht wird **je Tag ein eigener Worklog** auf den Tag, an dem gearbeitet wurde: eine vergessene
/// Woche verteilt sich also auf ihre Tage, statt komplett auf heute zu landen.
struct BookingSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var done = false

    private var bookings: [AppModel.OpenBooking] { model.openBookings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if bookings.isEmpty {
                empty
            } else {
                list
                Divider()
                footer
            }
        }
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark").foregroundStyle(.secondary)
            Text("Zeit buchen").font(.app(.headline))
            Spacer()
            Button {
                dismiss()
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(.green)
            Text("Alles gebucht").font(.app(.headline))
            Text("Kein Ticket im Sprint hat offene, noch nicht gebuchte Claude-Zeit.")
                .font(.app(.callout)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(bookings) { booking in
                    HStack(spacing: 10) {
                        Text(booking.key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 110, alignment: .leading)
                        Text(booking.summary)
                            .font(.app(.callout)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 8)
                        // Auf welche Tage gebucht wird — bei mehreren Tagen entstehen mehrere
                        // Worklog-Einträge, einer je Tag.
                        Text(booking.days.count > 1
                             ? "\(booking.dayLabel) · \(booking.days.count) Tage"
                             : booking.dayLabel)
                            .font(.app(.caption)).foregroundStyle(.tertiary)
                        Text(TimeFormatting.compact(booking.seconds))
                            .font(.app(.callout, weight: .semibold)).monospacedDigit()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = model.bookingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption)).foregroundStyle(.orange).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("\(bookings.count) Tickets · Σ \(TimeFormatting.compact(model.totalOpenToBookSeconds))")
                    .font(.app(.callout)).foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button {
                    Task {
                        await model.bookAllOpenTime()
                        done = true
                        if model.bookingError == nil { dismiss() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if model.bookingBusy { ProgressView().controlSize(.small) }
                        Text("Alle buchen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.bookingBusy)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
