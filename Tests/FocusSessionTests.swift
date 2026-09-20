import XCTest
@testable import Stilltime

final class FocusSessionTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testCountdownUsesDatesAcrossRelaunch() throws {
        let session = FocusSession(intention: "Write", minutes: 25, blocksApps: false, now: start)
        let restored = try JSONDecoder().decode(FocusSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(600)), 900)
        XCTAssertEqual(restored.progress(at: start.addingTimeInterval(600)), 0.4, accuracy: 0.0001)
    }

    func testCompletionClampsToPlannedDuration() {
        let session = FocusSession(intention: "Read", minutes: 15, blocksApps: true, now: start)
        let finished = session.finished(.completed, at: start.addingTimeInterval(5000))
        XCTAssertEqual(finished.actualSeconds, 900)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(1000)), 0)
    }

    func testEarlyEndPreservesOnlyElapsedTime() {
        let session = FocusSession(intention: "Study", minutes: 25, blocksApps: true, now: start)
        XCTAssertEqual(session.finished(.endedEarly, at: start.addingTimeInterval(180)).actualSeconds, 180)
    }

    func testBackwardClockDoesNotCreateNegativeTime() {
        let session = FocusSession(intention: "", minutes: 25, blocksApps: false, now: start)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(-20)), 1500)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(-20)), 0)
        XCTAssertEqual(session.finished(.endedEarly, at: start.addingTimeInterval(-20)).actualSeconds, 0)
    }

    func testDifferentSessionsHaveDifferentMonitorNames() {
        let first = FocusSession(intention: "A", minutes: 25, blocksApps: true, now: start)
        let second = FocusSession(intention: "B", minutes: 25, blocksApps: true, now: start)
        XCTAssertNotEqual(first.monitorName, second.monitorName)
    }

    func testParentLockPinVerification() {
        XCTAssertTrue(ParentLock.setPin("1234"))
        XCTAssertTrue(ParentLock.verifyPin("1234"))
        XCTAssertFalse(ParentLock.verifyPin("9999"))
        XCTAssertTrue(ParentLock.removePin(currentPin: "1234"))
        XCTAssertFalse(ParentLock.hasPin)
    }

    func testFocusScheduleFormatting() {
        let schedule = FocusSchedule(title: "Study", startHour: 14, startMinute: 0, endHour: 16, endMinute: 30, daysOfWeek: [2, 3, 4, 5, 6], isEnabled: true, isDeepFocus: true)
        XCTAssertEqual(schedule.timeString, "14:00 – 16:30")
        XCTAssertEqual(schedule.daysString, "Weekdays")
    }

    private func date(weekday: Int, hour: Int, minute: Int) -> Date {
        // 2023-11-12 was a Sunday (weekday 1); offsetting by days lands on the target weekday
        // while keeping the calculation independent of whatever "today" happens to be.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let sunday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 12))!
        let day = calendar.date(byAdding: .day, value: weekday - 1, to: sunday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testScheduleIsActiveOnlyInsideItsSameDayWindowAndDays() {
        let schedule = FocusSchedule(title: "School", startHour: 15, startMinute: 30, endHour: 17, endMinute: 30, daysOfWeek: [2, 3, 4, 5, 6])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertTrue(schedule.isActiveAt(date(weekday: 4, hour: 16, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActiveAt(date(weekday: 4, hour: 15, minute: 30), calendar: calendar))
        XCTAssertFalse(schedule.isActiveAt(date(weekday: 4, hour: 15, minute: 29), calendar: calendar))
        XCTAssertFalse(schedule.isActiveAt(date(weekday: 4, hour: 17, minute: 30), calendar: calendar))
        XCTAssertFalse(schedule.isActiveAt(date(weekday: 7, hour: 16, minute: 0), calendar: calendar))
    }

    func testScheduleOvernightWindowCrossesMidnightCorrectly() {
        let bedtime = FocusSchedule(title: "Bedtime", startHour: 21, startMinute: 0, endHour: 7, endMinute: 0, daysOfWeek: [1, 2, 3, 4, 5, 6, 7])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertTrue(bedtime.isActiveAt(date(weekday: 2, hour: 23, minute: 0), calendar: calendar))
        XCTAssertTrue(bedtime.isActiveAt(date(weekday: 3, hour: 6, minute: 30), calendar: calendar))
        XCTAssertFalse(bedtime.isActiveAt(date(weekday: 3, hour: 8, minute: 0), calendar: calendar))
        XCTAssertFalse(bedtime.isActiveAt(date(weekday: 2, hour: 20, minute: 0), calendar: calendar))
    }

    func testScheduleOvernightWindowChecksDaysOnBothSidesOfMidnight() {
        // Friday-only curfew: the Saturday-morning tail only counts because Friday is selected,
        // not because Saturday is -- a same-days-only check would wrongly cut this off at midnight.
        let fridayOnly = FocusSchedule(title: "Curfew", startHour: 22, startMinute: 0, endHour: 6, endMinute: 0, daysOfWeek: [6])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertTrue(fridayOnly.isActiveAt(date(weekday: 6, hour: 23, minute: 0), calendar: calendar))
        XCTAssertTrue(fridayOnly.isActiveAt(date(weekday: 7, hour: 3, minute: 0), calendar: calendar))
        XCTAssertFalse(fridayOnly.isActiveAt(date(weekday: 7, hour: 23, minute: 0), calendar: calendar))
        XCTAssertFalse(fridayOnly.isActiveAt(date(weekday: 1, hour: 3, minute: 0), calendar: calendar))
    }

    func testSplitTimePhaseAndProgressCalculation() {
        let session = FocusSession(intention: "Pomodoro", minutes: 30, blocksApps: false, isSplitTime: true, focusMinutes: 25, restMinutes: 5, now: start)
        XCTAssertEqual(session.currentPhase(at: start), .focus)
        XCTAssertEqual(session.phaseRemaining(at: start), 1500)
        XCTAssertEqual(session.focusProgress(at: start), 0.0, accuracy: 0.0001)

        let t1 = start.addingTimeInterval(750)
        XCTAssertEqual(session.currentPhase(at: t1), .focus)
        XCTAssertEqual(session.phaseRemaining(at: t1), 750)
        XCTAssertEqual(session.focusProgress(at: t1), 0.5, accuracy: 0.0001)

        let t2 = start.addingTimeInterval(1560)
        XCTAssertEqual(session.currentPhase(at: t2), .rest)
        XCTAssertEqual(session.phaseRemaining(at: t2), 240)
        XCTAssertEqual(session.restProgress(at: t2), 0.2, accuracy: 0.0001)
    }
}
