import Foundation

/// Ein Tagesposten: was an **einem** Kalendertag noch zu buchen ist.
public struct DailyBooking: Sendable, Hashable, Identifiable {
    /// Mitternacht des Tages, auf den gebucht wird — der Schlüssel der Buchung.
    public let day: Date
    /// `yyyy-MM-dd` — die Form, in der das Ledger den Tag merkt.
    public let dayKey: String
    /// Zu buchende Sekunden, immer ein 15-min-Vielfaches > 0.
    public let seconds: TimeInterval
    /// Der Zeitpunkt, den Jira als `started` bekommt: der **erste Turn dieses Tages**. Ein echter
    /// Zeitpunkt aus der Messung, nicht Mitternacht — Jira zeigt ihn in der Worklog-Historie an.
    public let startedAt: Date
    /// Was an diesem Tag gemessen wurde (vor dem Aufrunden) — für die Anzeige.
    public let measuredSeconds: TimeInterval

    public var id: String { dayKey }

    public init(day: Date, dayKey: String, seconds: TimeInterval, startedAt: Date,
                measuredSeconds: TimeInterval) {
        self.day = day
        self.dayKey = dayKey
        self.seconds = seconds
        self.startedAt = startedAt
        self.measuredSeconds = measuredSeconds
    }
}

/// Turns a ticket's derived ⏱ time into the amounts to book to Jira — **je Kalendertag**.
///
/// Gebucht wird auf den Tag, an dem gearbeitet wurde, nicht auf heute. Das war vorher falsch: eine
/// vergessene Woche landete komplett am Tag des Nachbuchens, und Jiras Tages- und Wochenauswertungen
/// zeigten Arbeit, die dort nie stattfand.
///
/// Die Zuordnung kommt aus den Turns selbst (`ClaudeTurn.start`, lokaler Kalendertag) — dieselbe
/// abgeleitete Quelle wie die Zeit. Ein Turn über Mitternacht zählt ganz auf seinen **Starttag**:
/// aufteilen liesse sich nur schätzen, und der Prompt ist am Starttag geschrieben worden.
///
/// Aufgerundet wird **je Tag** auf 15 Minuten. Das ist die 15-min-Regel, konsequent angewandt: jeder
/// Tag ist eine eigene Buchung und kann nicht kleiner als ein Schritt sein. Preis: fünf Tage mit je
/// 3 min ergeben 5 × 15 min statt einmal 15 min. Der Aufschlag ist sichtbar (Tagesliste im Popover),
/// und das Ledger merkt sich das Gebuchte **je Tag**, sodass auch hier nichts zweimal gebucht wird.
public enum WorklogBooking {
    /// The smallest booking step. Bookings are always whole multiples of this.
    public static let quantum: TimeInterval = 15 * 60

    /// Sub-second slop tolerated before a value counts as "over the boundary". Turn durations are
    /// summed millisecond values, so a total can land a hair above a 15-minute mark; without this,
    /// 15m 00.3s would round to 30m. Real work of a second or more still rounds up as intended.
    private static let tolerance: TimeInterval = 1

    /// Rounds *up* to the next 15-minute step; 0 (and anything within `tolerance` of 0) stays 0.
    public static func roundedUp(_ seconds: TimeInterval) -> TimeInterval {
        let net = seconds - tolerance
        guard net > 0 else { return 0 }
        return (net / quantum).rounded(.up) * quantum
    }

    /// The seconds still to book: the rounded-up cumulative minus what was already booked, never
    /// negative. Both sides are 15-minute multiples, so the result is one too — and it is 0 as soon
    /// as no new time was worked, which is what makes a double booking impossible.
    public static func secondsToBook(measured: TimeInterval, alreadyBooked: TimeInterval) -> TimeInterval {
        max(0, roundedUp(measured) - alreadyBooked)
    }

    /// `yyyy-MM-dd` im lokalen Kalender — der Tagesschlüssel des Ledgers.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Die offenen Tagesposten eines Tickets, chronologisch.
    ///
    /// - `turns`: alle gemessenen Turns der Session(s) des Tickets.
    /// - `bookedByDay`: was das Ledger je Tag schon gebucht hat.
    /// - `unattributedBooked`: Alt-Buchungen ohne Tageszuordnung (Ledger vor dieser Änderung). Sie
    ///   werden **von alt nach neu** aufgezehrt — so wurde damals ja auch gebucht. Ohne das würde
    ///   die erste Buchung nach dem Update die ganze Historie erneut buchen.
    /// - `settledThrough`: Tage **vor** diesem Tag gelten als abgerechnet. Nötig, weil die alte
    ///   Rundung auf die *Summe* ging und die neue je Tag: ohne diese Grenze würden zwei Tage mit je
    ///   20 min (früher einmal 45 min gebucht) jetzt 2 × 30 min ergeben und 15 min auf einem
    ///   längst gebuchten Tag nachfordern. Der letzte Buchungstag selbst bleibt offen — dort kann
    ///   nach der Buchung weitergearbeitet worden sein.
    public static func dailyBookings(turns: [ClaudeTurn],
                                     bookedByDay: [String: TimeInterval] = [:],
                                     unattributedBooked: TimeInterval = 0,
                                     settledThrough: Date? = nil,
                                     calendar: Calendar = .current) -> [DailyBooking] {
        struct Day {
            var day: Date
            var measured: TimeInterval = 0
            var firstTurnStart: Date
        }
        var days: [String: Day] = [:]
        for turn in turns where turn.seconds > 0 {
            let key = dayKey(turn.start, calendar: calendar)
            let midnight = calendar.startOfDay(for: turn.start)
            var entry = days[key] ?? Day(day: midnight, firstTurnStart: turn.start)
            entry.measured += turn.seconds
            if turn.start < entry.firstTurnStart { entry.firstTurnStart = turn.start }
            days[key] = entry
        }

        // Grenze für Alt-Buchungen: alles vor dem letzten Buchungstag ist abgerechnet.
        let settledBefore = settledThrough.map { calendar.startOfDay(for: $0) }

        var credit = unattributedBooked
        var result: [DailyBooking] = []
        for key in days.keys.sorted() {
            guard let entry = days[key] else { continue }
            if let settledBefore, entry.day < settledBefore, bookedByDay[key] == nil {
                credit = max(0, credit - roundedUp(entry.measured))   // zählt als gebucht
                continue
            }
            var booked = bookedByDay[key] ?? 0
            // Alt-Guthaben zuerst auf die ältesten Tage anrechnen.
            if credit > 0 {
                let used = min(credit, max(0, roundedUp(entry.measured) - booked))
                booked += used
                credit -= used
            }
            let open = max(0, roundedUp(entry.measured) - booked)
            guard open > 0 else { continue }
            result.append(DailyBooking(day: entry.day, dayKey: key, seconds: open,
                                       startedAt: entry.firstTurnStart,
                                       measuredSeconds: entry.measured))
        }
        return result
    }
}
