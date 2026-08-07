import Foundation

/// Turns a ticket's derived, cumulative ⏱ time into the amount to book to Jira.
///
/// The measured time only grows and is cumulative across every day, so booking it as-is would re-log
/// what a previous day already booked. The caller keeps a per-ticket ledger of what has been booked
/// (`alreadyBooked`) and books only the difference. Everything is quantised to 15-minute steps,
/// always rounded **up** — as required — and the rounding is applied to the cumulative total (not to
/// each day's delta), so the booked total tracks `roundedUp(measured)` and never drifts.
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
}
