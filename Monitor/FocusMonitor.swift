import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

// The OS runs this extension when the app is backgrounded or closed.
// Compare monitor IDs so an old interval cannot unblock a newer session.
final class FocusMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if let session = FocusStorage.active, activity.rawValue == session.monitorName {
            guard session.blocksApps,
                  session.endsAt > Date(),
                  AuthorizationCenter.shared.authorizationStatus == .approved else { return }
            FocusStorage.applyShields()
            return
        }
        // Not a manual session: check whether a recurring routine owns this activity name.
        // The routine's window repeats daily at the OS level, so daysOfWeek (which the OS
        // schedule itself cannot express) is re-checked here on every occurrence.
        if let schedule = FocusStorage.schedules.first(where: { $0.monitorName == activity.rawValue }) {
            guard schedule.isEnabled,
                  schedule.selectionCount > 0,
                  schedule.isActiveAt(Date()),
                  AuthorizationCenter.shared.authorizationStatus == .approved else { return }
            FocusStorage.applyScheduleShields(schedule)
            return
        }
        // A usage limit's interval covers a full day and repeats daily; a fresh interval start
        // is therefore "a new day began" -- clear yesterday's threshold shield so today starts
        // unblocked. The event fires again independently once today's usage reaches the cap.
        if let limit = FocusStorage.usageLimits.first(where: { $0.monitorName == activity.rawValue }) {
            FocusStorage.clearUsageShield(limit)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if let session = FocusStorage.active, activity.rawValue == session.monitorName {
            FocusStorage.shieldStore.clearAllSettings()
            // The app archives its own history when reopened. The extension does not
            // compete with the app to rewrite session history or remove active state.
            return
        }
        if let schedule = FocusStorage.schedules.first(where: { $0.monitorName == activity.rawValue }) {
            FocusStorage.clearScheduleShields(schedule)
            return
        }
        if let limit = FocusStorage.usageLimits.first(where: { $0.monitorName == activity.rawValue }) {
            FocusStorage.clearUsageShield(limit)
        }
    }

    /// Fires once cumulative usage of a usage limit's selected apps/categories/sites reaches its
    /// daily threshold. This is the piece that makes the cap cumulative rather than a fixed
    /// window: the OS tracks actual foreground time against the threshold itself, not us polling.
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let limit = FocusStorage.usageLimits.first(where: { $0.monitorName == activity.rawValue }),
              limit.isEnabled,
              AuthorizationCenter.shared.authorizationStatus == .approved else { return }
        FocusStorage.applyUsageShield(limit)
    }
}
