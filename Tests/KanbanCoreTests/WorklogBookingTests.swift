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
}
