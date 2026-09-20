import Foundation
import FamilyControls

/// A cumulative daily cap ("45 minutes of Instagram, total, per day") as distinct from
/// FocusSchedule's time-window routines ("blocked from 15:30-17:30"). Enforced via
/// DeviceActivityEvent threshold monitoring rather than a fixed interval.
struct AppUsageLimit: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var dailyMinutes: Int
    var isEnabled: Bool
    var selection: FamilyActivitySelection

    init(id: UUID = UUID(), title: String, dailyMinutes: Int, isEnabled: Bool = true, selection: FamilyActivitySelection = FamilyActivitySelection()) {
        self.id = id
        self.title = title
        self.dailyMinutes = max(1, dailyMinutes)
        self.isEnabled = isEnabled
        self.selection = selection
    }

    var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    /// Distinct prefix from FocusSchedule's "stilltime.schedule." so FocusMonitor can tell a
    /// daily usage-threshold activity apart from a recurring time-window routine without the
    /// two features' callbacks having to reason about each other's activity names.
    var monitorName: String { "stilltime.usage.\(id.uuidString)" }

    /// The single threshold event registered against `monitorName`'s activity.
    static let eventName = "reachedLimit"
}
