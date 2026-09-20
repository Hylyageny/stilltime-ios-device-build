import Foundation
import FamilyControls

/// BLOCK_SELECTED shields only the chosen apps/categories/sites. ALLOW_ONLY shields
/// everything except the chosen apps ("allow these apps, shield everything else") --
/// the parent/deep-work case.
enum ShieldMode: String, Codable {
    case blockSelected
    case allowOnly
}

struct FocusSchedule: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var daysOfWeek: Set<Int> // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    var isEnabled: Bool
    var isDeepFocus: Bool
    var iconName: String
    var shieldMode: ShieldMode
    /// This routine's own app/category/website selection, independent of the manual
    /// Focus tab's selection, so each routine can shield (or allow) a different set.
    var selection: FamilyActivitySelection

    init(id: UUID = UUID(), title: String, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, daysOfWeek: Set<Int>, isEnabled: Bool = true, isDeepFocus: Bool = false, iconName: String = "clock.fill", shieldMode: ShieldMode = .blockSelected, selection: FamilyActivitySelection = FamilyActivitySelection()) {
        self.id = id
        self.title = title
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.daysOfWeek = daysOfWeek
        self.isEnabled = isEnabled
        self.isDeepFocus = isDeepFocus
        self.iconName = iconName
        self.shieldMode = shieldMode
        self.selection = selection
    }

    var timeString: String {
        let start = String(format: "%02d:%02d", startHour, startMinute)
        let end = String(format: "%02d:%02d", endHour, endMinute)
        return "\(start) – \(end)"
    }

    var daysString: String {
        if daysOfWeek.count == 7 { return "Every day" }
        if daysOfWeek == [2, 3, 4, 5, 6] { return "Weekdays" }
        if daysOfWeek == [1, 7] { return "Weekends" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = daysOfWeek.sorted()
        return sorted.map { names[$0 - 1] }.joined(separator: ", ")
    }

    var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    /// The DeviceActivityName this routine registers with DeviceActivityCenter, distinct
    /// from a manual FocusSession's monitor name so both can run at once.
    var monitorName: String { "stilltime.schedule.\(id.uuidString)" }

    /// True if this routine's scheduled window covers `date`, ignoring isEnabled and app
    /// selection so callers can layer those checks explicitly. Handles windows that cross
    /// midnight (e.g. a 21:00-07:00 bedtime routine) by checking yesterday's weekday too.
    func isActiveAt(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        let minutesNow = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let startM = startHour * 60 + startMinute
        let endM = endHour * 60 + endMinute
        guard startM != endM else { return false }
        if startM < endM {
            return daysOfWeek.contains(weekday) && (startM..<endM).contains(minutesNow)
        } else {
            let previousWeekday = weekday == 1 ? 7 : weekday - 1
            return (daysOfWeek.contains(weekday) && minutesNow >= startM) || (daysOfWeek.contains(previousWeekday) && minutesNow < endM)
        }
    }

    static var defaultPresets: [FocusSchedule] {
        [
            FocusSchedule(title: "School / Homework", startHour: 15, startMinute: 30, endHour: 17, endMinute: 30, daysOfWeek: [2, 3, 4, 5, 6], isEnabled: true, isDeepFocus: true, iconName: "book.fill"),
            FocusSchedule(title: "Family Dinner", startHour: 18, startMinute: 30, endHour: 19, endMinute: 30, daysOfWeek: [1, 2, 3, 4, 5, 6, 7], isEnabled: true, isDeepFocus: false, iconName: "fork.knife"),
            FocusSchedule(title: "Bedtime Routine", startHour: 21, startMinute: 0, endHour: 7, endMinute: 0, daysOfWeek: [1, 2, 3, 4, 5, 6, 7], isEnabled: true, isDeepFocus: true, iconName: "moon.fill")
        ]
    }
}
