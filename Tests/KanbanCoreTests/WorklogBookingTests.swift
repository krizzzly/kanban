import XCTest
@testable import KanbanCore

final class WorklogBookingTests: XCTestCase {
    private let q: TimeInterval = 15 * 60   // one quantum

    // MARK: - Rounding up to 15 min

    func testRoundsUpToTheNext15Minutes() {
        XCTAssertEqual(WorklogBooking.roundedUp(0), 0)
        XCTAssertEqual(WorklogBooking.roundedUp(7 * 60), q)          // 7m → 15m
        XCTAssertEqual(WorklogBooking.roundedUp(15 * 60), q)         // exactly 15m stays 15m
        XCTAssertEqual(WorklogBooking.roundedUp(16 * 60), 2 * q)     // 16m → 30m
        XCTAssertEqual(WorklogBooking.roundedUp(44 * 60), 3 * q)     // 44m → 45m
        XCTAssertEqual(WorklogBooking.roundedUp(45 * 60), 3 * q)
    }

    func testSubSecondOvershootDoesNotCostAWholeQuantum() {
        // A cumulative sum of millisecond durations can land a hair over a boundary.
        XCTAssertEqual(WorklogBooking.roundedUp(15 * 60 + 0.3), q, "15m 00.3s must stay 15m")
        // But a real extra second still rounds up.
        XCTAssertEqual(WorklogBooking.roundedUp(15 * 60 + 5), 2 * q)
    }

    // MARK: - Delta booking (the no-double-booking guarantee)

    func testFirstBookingRoundsTheCumulativeUp() {
        XCTAssertEqual(WorklogBooking.secondsToBook(measured: 7 * 60, alreadyBooked: 0), q)
    }

    func testNothingNewWorkedBooksZero() {
        // Booked 15m already; measured has not passed the next boundary → nothing to book.
        XCTAssertEqual(WorklogBooking.secondsToBook(measured: 14 * 60, alreadyBooked: q), 0)
        XCTAssertEqual(WorklogBooking.secondsToBook(measured: 15 * 60, alreadyBooked: q), 0)
    }

    func testSecondDayBooksOnlyTheNewDelta() {
        // Day 1: 7m worked → booked 15m. Day 2: cumulative 22m → target 30m → book the missing 15m.
        XCTAssertEqual(WorklogBooking.secondsToBook(measured: 22 * 60, alreadyBooked: q), q)
    }

    func testBookingIsAlwaysAWholeQuantum() {
        for measured in stride(from: 0.0, through: 3 * 3600, by: 137) {
            for bookedSteps in 0...12 {
                let toBook = WorklogBooking.secondsToBook(
                    measured: measured, alreadyBooked: TimeInterval(bookedSteps) * q)
                XCTAssertGreaterThanOrEqual(toBook, 0)
                XCTAssertEqual(toBook.truncatingRemainder(dividingBy: q), 0, accuracy: 0.001,
                               "every booking must be a multiple of 15 min")
            }
        }
    }

    func testRepeatedBookingConvergesAndNeverDoubleBooks() {
        // Simulate booking the same measured value twice in a row: the second time books nothing.
        var booked: TimeInterval = 0
        let measured: TimeInterval = 20 * 60
        let first = WorklogBooking.secondsToBook(measured: measured, alreadyBooked: booked)
        booked += first
        let second = WorklogBooking.secondsToBook(measured: measured, alreadyBooked: booked)
        XCTAssertEqual(first, 2 * q)   // 20m → 30m
        XCTAssertEqual(second, 0, "re-booking the same measured time must add nothing")
    }

    func testGrowingMeasurementNeverAsksToBookNegative() {
        // Even if the ledger somehow holds more than the rounded cumulative, we never "un-book".
        XCTAssertEqual(WorklogBooking.secondsToBook(measured: 5 * 60, alreadyBooked: 4 * q), 0)
    }

    // MARK: Tageweise buchen

    /// Fester Kalender (UTC), damit die Tagesgrenzen im Test nicht von der Zeitzone abhängen.
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func turn(_ index: Int, day: String, hour: Int, minutes: Double) -> ClaudeTurn {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let start = formatter.date(from: "\(day) \(String(format: "%02d", hour)):00")!
        return ClaudeTurn(index: index, promptId: "p\(index)", start: start,
                          end: start.addingTimeInterval(minutes * 60),
                          reportedSeconds: minutes * 60, estimatedSeconds: minutes * 60,
                          prompt: "p\(index)")
    }

    /// Der Fall, um den es geht: drei Tage gearbeitet, nichts gebucht. Es entstehen **drei**
    /// Buchungen auf ihre Tage — nicht eine auf heute.
    func testForgottenDaysBookOnTheirOwnDays() {
        let turns = [
            turn(0, day: "2026-08-17", hour: 9, minutes: 20),
            turn(1, day: "2026-08-17", hour: 14, minutes: 10),
            turn(2, day: "2026-08-18", hour: 10, minutes: 40),
            turn(3, day: "2026-08-20", hour: 8, minutes: 5),
        ]
        let bookings = WorklogBooking.dailyBookings(turns: turns, calendar: utc)
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-17", "2026-08-18", "2026-08-20"])
        // 30 min → 30, 40 min → 45, 5 min → 15 (je Tag aufgerundet)
        XCTAssertEqual(bookings.map(\.seconds), [30 * 60.0, 45 * 60.0, 15 * 60.0])
        // `started` ist der erste Turn des Tages, nicht Mitternacht und nicht jetzt.
        XCTAssertEqual(bookings[0].startedAt, turns[0].start)
        XCTAssertEqual(bookings[1].startedAt, turns[2].start)
    }

    /// Ein zweites Buchen am selben Tag bucht nichts nach — die Sperre gilt jetzt je Tag.
    func testAlreadyBookedDaysAreSkipped() {
        let turns = [turn(0, day: "2026-08-17", hour: 9, minutes: 20),
                     turn(1, day: "2026-08-18", hour: 9, minutes: 20)]
        let bookings = WorklogBooking.dailyBookings(
            turns: turns, bookedByDay: ["2026-08-17": 30 * 60.0], calendar: utc)
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-18"])
    }

    /// Wird an einem schon gebuchten Tag weitergearbeitet, kommt nur die Differenz dazu.
    func testMoreWorkOnABookedDayBooksOnlyTheDelta() {
        let turns = [turn(0, day: "2026-08-17", hour: 9, minutes: 20),
                     turn(1, day: "2026-08-17", hour: 16, minutes: 20)]   // 40 min → 45
        let bookings = WorklogBooking.dailyBookings(
            turns: turns, bookedByDay: ["2026-08-17": 30 * 60.0], calendar: utc)
        XCTAssertEqual(bookings.map(\.seconds), [15 * 60.0])
    }

    /// Alt-Ledger ohne Tageszuordnung: das Gebuchte wird von alt nach neu angerechnet, statt die
    /// Historie ein zweites Mal zu buchen.
    func testLegacyBookedTotalIsCreditedOldestFirst() {
        let turns = [turn(0, day: "2026-08-17", hour: 9, minutes: 20),    // → 30 min
                     turn(1, day: "2026-08-18", hour: 9, minutes: 40),    // → 45 min
                     turn(2, day: "2026-08-19", hour: 9, minutes: 10)]    // → 15 min
        // Früher gebucht: 75 min = die ersten beiden Tage.
        let bookings = WorklogBooking.dailyBookings(turns: turns, unattributedBooked: 75 * 60.0,
                                                    calendar: utc)
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-19"])
        XCTAssertEqual(bookings.map(\.seconds), [15 * 60.0])
    }

    /// Teilweise angerechnet: 45 der 75 min deckt Tag 1 und die Hälfte von Tag 2.
    func testLegacyCreditCanCoverADayPartially() {
        let turns = [turn(0, day: "2026-08-17", hour: 9, minutes: 20),    // → 30
                     turn(1, day: "2026-08-18", hour: 9, minutes: 40)]    // → 45
        let bookings = WorklogBooking.dailyBookings(turns: turns, unattributedBooked: 45 * 60.0,
                                                    calendar: utc)
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-18"])
        XCTAssertEqual(bookings.map(\.seconds), [30 * 60.0])   // 45 gemessen − 15 angerechnet
    }

    /// Ein Turn über Mitternacht zählt ganz auf seinen Starttag — der Prompt wurde dort geschrieben.
    func testTurnAcrossMidnightCountsOnItsStartDay() {
        let bookings = WorklogBooking.dailyBookings(
            turns: [turn(0, day: "2026-08-17", hour: 23, minutes: 90)], calendar: utc)
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-17"])
        XCTAssertEqual(bookings.map(\.seconds), [90 * 60.0])
    }

    func testNoTurnsMeansNothingToBook() {
        XCTAssertTrue(WorklogBooking.dailyBookings(turns: [], calendar: utc).isEmpty)
    }

    func testDayKeyIsZeroPadded() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let date = formatter.date(from: "2026-01-05 08:00")!
        XCTAssertEqual(WorklogBooking.dayKey(date, calendar: utc), "2026-01-05")
    }

    /// Der Umstieg selbst: früher wurde auf die **Summe** aufgerundet, jetzt je Tag. Tage **vor**
    /// dem letzten Buchungstag gehen dadurch nicht wieder auf — der letzte Buchungstag schon, denn
    /// dort kann nach der Buchung weitergearbeitet worden sein. Preis: einmalig höchstens ein
    /// 15-min-Schritt je Ticket, und zwar auf einem Tag, an dem wirklich gearbeitet wurde.
    func testSwitchingGranularityKeepsEarlierDaysSettled() {
        let turns = [turn(0, day: "2026-08-15", hour: 9, minutes: 20),
                     turn(1, day: "2026-08-16", hour: 9, minutes: 20),
                     turn(2, day: "2026-08-18", hour: 9, minutes: 20)]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lastBooked = formatter.date(from: "2026-08-18 18:00")!

        // Alt gebucht: aufgerundet auf die Summe (60 min), am 18.08.
        let bookings = WorklogBooking.dailyBookings(turns: turns, unattributedBooked: 60 * 60.0,
                                                   settledThrough: lastBooked, calendar: utc)
        // 15. und 16. bleiben zu; nur der Buchungstag selbst kann noch etwas offen haben.
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-18"])
        XCTAssertEqual(bookings.map(\.seconds), [30 * 60.0])   // 30 gemessen-gerundet, Guthaben weg
    }

    /// Am letzten Buchungstag selbst darf nachgebucht werden — dort wurde nach der Buchung
    /// weitergearbeitet.
    func testWorkAfterTheLastBookingOnThatDayStaysOpen() {
        let turns = [turn(0, day: "2026-08-17", hour: 9, minutes: 20),
                     turn(1, day: "2026-08-18", hour: 9, minutes: 20),
                     turn(2, day: "2026-08-18", hour: 20, minutes: 30)]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let bookings = WorklogBooking.dailyBookings(
            turns: turns, unattributedBooked: 45 * 60.0,
            settledThrough: formatter.date(from: "2026-08-18 18:00")!, calendar: utc)
        XCTAssertEqual(bookings.map(\.dayKey), ["2026-08-18"])
        // 50 min am 18. → 60 min, minus die 15 min Restguthaben (45 − 30 für den 17.).
        XCTAssertEqual(bookings.map(\.seconds), [45 * 60.0])
    }
}
