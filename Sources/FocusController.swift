import AudioToolbox
import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

/// Named after the device's own default sounds, not a bundled custom chime/bell -- this app
/// ships no audio assets, it just plays one of iOS's built-in system sounds.
enum CompletionSound: String, CaseIterable {
    case notification, alert, none

    var label: String {
        switch self {
        case .notification: return "Default notification sound"
        case .alert: return "Default alert sound"
        case .none: return "None"
        }
    }

    func play() {
        switch self {
        case .notification: AudioServicesPlaySystemSound(1013)
        case .alert: AudioServicesPlaySystemSound(1005)
        case .none: break
        }
    }
}

@MainActor
final class FocusController: ObservableObject {
    @Published private(set) var active: FocusSession?
    @Published private(set) var history: [FocusSession] = []
    @Published private(set) var authorized = false
    @Published private(set) var requestingPermission = false
    @Published var errorMessage: String?
    @Published var selection = FamilyActivitySelection() {
        didSet { if FocusStorage.groupIsAvailable { FocusStorage.selection = selection } }
    }

    @Published var schedules: [FocusSchedule] = [] {
        didSet {
            if FocusStorage.groupIsAvailable { FocusStorage.schedules = schedules }
            syncSchedules()
        }
    }
    @Published var usageLimits: [AppUsageLimit] = [] {
        didSet {
            if FocusStorage.groupIsAvailable { FocusStorage.usageLimits = usageLimits }
            syncUsageLimits()
        }
    }
    @Published var parentPinEnabled: Bool = ParentLock.isEnabled
    @Published var parentPinSet: Bool = ParentLock.hasPin

    /// Seeds the Focus tab's length picker on open; does not retroactively change a running session.
    @Published var defaultMinutes: Int = 25 {
        didSet { defaults.set(defaultMinutes, forKey: defaultMinutesKey) }
    }
    @Published var completionSound: CompletionSound = .notification {
        didSet { defaults.set(completionSound.rawValue, forKey: completionSoundKey) }
    }

    private let center = DeviceActivityCenter()
    private let defaults = UserDefaults.standard
    private let historyKey = "sessionHistory.v1"
    private let timerKey = "timerOnlySession.v1"
    private let defaultMinutesKey = "defaultMinutes.v1"
    private let completionSoundKey = "completionSound.v1"

    init() {
        if let data = defaults.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([FocusSession].self, from: data) {
            history = saved
        }
        if let storedMinutes = defaults.object(forKey: defaultMinutesKey) as? Int {
            defaultMinutes = storedMinutes
        }
        completionSound = CompletionSound(rawValue: defaults.string(forKey: completionSoundKey) ?? "") ?? .notification
        if FocusStorage.groupIsAvailable {
            selection = FocusStorage.selection
            active = FocusStorage.active
            schedules = FocusStorage.schedules
            usageLimits = FocusStorage.usageLimits
        } else {
            schedules = FocusSchedule.defaultPresets
        }
        if active == nil, let data = defaults.data(forKey: timerKey) {
            active = try? JSONDecoder().decode(FocusSession.self, from: data)
        }
        refresh()
    }

    var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    func requestPermission() async {
        guard !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refresh()
        } catch {
            errorMessage = "Screen Time permission was not enabled. You can still use timer-only sessions. \(error.localizedDescription)"
        }
    }

    func setParentPin(_ pin: String) -> Bool {
        let success = ParentLock.setPin(pin)
        if success {
            parentPinEnabled = true
            parentPinSet = true
        }
        return success
    }

    func verifyParentPin(_ pin: String) -> Bool {
        ParentLock.verifyPin(pin)
    }

    func start(intention: String, minutes: Int, blocksApps: Bool, isDeepFocus: Bool = false, isParentLocked: Bool = false, isSplitTime: Bool = false, focusMinutes: Int = 25, restMinutes: Int = 5) {
        guard active == nil else { return }
        guard (5...180).contains(minutes) else {
            errorMessage = "Choose a session between 5 and 180 minutes."
            return
        }
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if blocksApps {
            guard authorized else { errorMessage = "Enable Screen Time permission first."; return }
            guard FocusStorage.groupIsAvailable else {
                errorMessage = "App blocking needs the shared app group configured in Xcode. Timer-only sessions remain available."
                return
            }
            guard selectionCount > 0 else { errorMessage = "Choose at least one app, category, or website to block."; return }
        }

        let now = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970))
        let session = FocusSession(intention: intention, minutes: minutes, blocksApps: blocksApps, isDeepFocus: isDeepFocus, isParentLocked: isParentLocked, isSplitTime: isSplitTime, focusMinutes: focusMinutes, restMinutes: restMinutes, now: now)
        if blocksApps {
            FocusStorage.selection = selection
            FocusStorage.active = session
            var calendar = Calendar.current
            calendar.timeZone = .current
            let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
            var start = calendar.dateComponents(components, from: session.startedAt)
            var end = calendar.dateComponents(components, from: session.endsAt)
            start.timeZone = calendar.timeZone
            end.timeZone = calendar.timeZone
            let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)
            do {
                try center.startMonitoring(DeviceActivityName(session.monitorName), during: schedule)
                FocusStorage.applyShields()
            } catch {
                FocusStorage.active = nil
                center.stopMonitoring([DeviceActivityName(session.monitorName)])
                FocusStorage.shieldStore.clearAllSettings()
                errorMessage = "Blocking could not start, so no session was started. \(error.localizedDescription)"
                return
            }
        } else {
            save(session, key: timerKey)
        }
        active = session
        scheduleCompletionNotification(for: session)
    }

    /// Local notification delivered by the OS at the session's end time, independent of whether
    /// Stilltime is open, backgrounded, or killed -- the completion *sound* (played from
    /// `refresh()`) only fires while the app happens to be running to observe the transition,
    /// but this is how the person actually finds out their session ended if they didn't sit and
    /// watch it. Requesting authorization here (not at first launch) matches this kit's existing
    /// pattern of asking for a permission only when the feature that needs it is first used.
    private let completionNotificationId = "stilltime.session.complete"

    private func scheduleCompletionNotification(for session: FocusSession) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Focus session complete"
        content.body = session.intention.isEmpty ? "Your Stilltime session has ended." : "\"\(session.intention)\" -- your session has ended."
        // UNNotificationSound only accepts .default or a custom bundled sound file, not an
        // arbitrary system sound ID, so both non-silent CompletionSound options collapse to the
        // same system default here (the foreground live path keeps the two sounds distinct).
        content.sound = completionSound == .none ? nil : .default
        let interval = max(1, session.endsAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: completionNotificationId, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [completionNotificationId])
        center.add(request)
    }

    private func cancelCompletionNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [completionNotificationId])
    }

    func refresh(now: Date = Date()) {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        // Re-check routines every time the app is in the foreground (this runs on a 1s timer
        // and on scenePhase becoming active), not just when `schedules` changes -- so a routine
        // whose window opens while its target app is already frontmost still gets shielded
        // right away, instead of waiting for the user to switch apps or the next OS callback.
        syncSchedules(now: now)
        syncUsageLimits()
        guard let session = active else { return }
        if now >= session.endsAt {
            finish(.completed, now: session.endsAt)
            // The scheduled local notification (see scheduleCompletionNotification) is what
            // tells the person their session ended if the app isn't open; this sound is a
            // bonus that only plays if Stilltime happens to be running right at this instant.
            completionSound.play()
        } else if session.blocksApps && !authorized {
            finish(.permissionRemoved, now: now)
        }
    }

    func endEarly(parentPin: String? = nil) {
        if let current = active, (current.isDeepFocus || current.isParentLocked || ParentLock.isEnabled) {
            if ParentLock.lockRemainingSeconds > 0 {
                errorMessage = "Too many attempts. Try again in \(ParentLock.lockRemainingSeconds)s."
                return
            }
            guard let pin = parentPin, verifyParentPin(pin) else {
                errorMessage = "Incorrect Parent PIN. Passcode required to end Deep Focus or locked sessions."
                return
            }
        }
        finish(.endedEarly, now: Date())
    }

    private func finish(_ outcome: FocusSession.Outcome, now: Date) {
        guard let session = active else { return }
        // Safe unconditionally: for a natural ".completed" finish the notification has already
        // been delivered (or is about to be, independently of this call) so removing an
        // already-delivered one-shot request is a no-op; for endedEarly/permissionRemoved it
        // prevents a stale "session complete" notification firing later for nothing.
        cancelCompletionNotification()
        if session.blocksApps {
            FocusStorage.active = nil
            center.stopMonitoring([DeviceActivityName(session.monitorName)])
            FocusStorage.shieldStore.clearAllSettings()
        }
        defaults.removeObject(forKey: timerKey)
        if !history.contains(where: { $0.id == session.id }) {
            history.insert(session.finished(outcome, at: now), at: 0)
            history = Array(history.prefix(365))
            save(history, key: historyKey)
        }
        active = nil
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: historyKey)
    }

    /// Clears a stuck shield. If a session is currently active and locked (Deep Focus, or a
    /// Parent PIN is set), this requires the same PIN as ending the session normally — recovery
    /// must not become a way to bypass Parent Lock. When there is no active session (the
    /// original "shield survived a crash" case this exists for), it still runs unconditionally.
    func releaseBlocks(parentPin: String? = nil) {
        if let current = active, (current.isDeepFocus || current.isParentLocked || ParentLock.isEnabled) {
            if ParentLock.lockRemainingSeconds > 0 {
                errorMessage = "Too many attempts. Try again in \(ParentLock.lockRemainingSeconds)s."
                return
            }
            guard let pin = parentPin, verifyParentPin(pin) else {
                errorMessage = "Incorrect Parent PIN. Passcode required to release a locked session's blocks."
                return
            }
        }
        finish(.endedEarly, now: Date())
        FocusStorage.active = nil
        // Only the manual-session activity names, e.g. "stilltime.<uuid>" -- not
        // "stilltime.schedule.*" or "stilltime.usage.*", which this recovery action has no
        // business touching. A plain "stilltime." prefix would match those too and silently
        // drop routine/usage-limit monitoring on every stuck-shield recovery.
        let ours = center.activities.filter {
            $0.rawValue.hasPrefix("stilltime.") &&
            !$0.rawValue.hasPrefix("stilltime.schedule.") &&
            !$0.rawValue.hasPrefix("stilltime.usage.")
        }
        center.stopMonitoring(ours)
        FocusStorage.shieldStore.clearAllSettings()
    }

    /// Registers OS-level recurring monitoring (repeats: true) for every routine that's
    /// enabled and has at least one app/site chosen, and stops monitoring ones that no longer
    /// qualify (disabled, deleted, or emptied out). Also immediately applies or clears shields
    /// for whichever routine's window covers `now`, so an edit made while a routine is already
    /// active -- or the app relaunching mid-window -- takes effect without waiting for the
    /// next daily boundary, the same way the DeviceActivityMonitor extension does in the
    /// background. Cheap to call repeatedly: starting/stopping is skipped when already correct.
    func syncSchedules(now: Date = Date()) {
        guard FocusStorage.groupIsAvailable else { return }
        let desired = schedules.filter { $0.isEnabled && $0.selectionCount > 0 }
        let desiredNames = Set(desired.map { DeviceActivityName($0.monitorName) })
        let monitoredScheduleNames = Set(center.activities.filter { $0.rawValue.hasPrefix("stilltime.schedule.") })

        let toStop = monitoredScheduleNames.subtracting(desiredNames)
        if !toStop.isEmpty { center.stopMonitoring(Array(toStop)) }

        let desiredIDs = Set(desired.map(\.id))
        for schedule in schedules where !desiredIDs.contains(schedule.id) {
            FocusStorage.clearScheduleShields(schedule)
        }

        for schedule in desired {
            let name = DeviceActivityName(schedule.monitorName)
            if !monitoredScheduleNames.contains(name) {
                var calendar = Calendar.current
                calendar.timeZone = .current
                var start = DateComponents()
                start.hour = schedule.startHour
                start.minute = schedule.startMinute
                start.second = 0
                var end = DateComponents()
                end.hour = schedule.endHour
                end.minute = schedule.endMinute
                end.second = 0
                let deviceSchedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
                try? center.startMonitoring(name, during: deviceSchedule)
            }
            if schedule.isActiveAt(now) {
                FocusStorage.applyScheduleShields(schedule)
            } else {
                FocusStorage.clearScheduleShields(schedule)
            }
        }
    }

    /// Registers OS-level daily usage-threshold monitoring for every enabled limit with at
    /// least one app/site chosen, and stops monitoring ones that no longer qualify. Unlike
    /// syncSchedules, there's no "apply shields now" step: the OS tracks actual cumulative
    /// foreground usage against the threshold itself and calls back via
    /// eventDidReachThreshold, so this only has to keep the registered set in sync with what's
    /// configured. Cheap to call repeatedly: registering is skipped when already monitored.
    func syncUsageLimits() {
        guard FocusStorage.groupIsAvailable else { return }
        let desired = usageLimits.filter { $0.isEnabled && $0.selectionCount > 0 }
        let desiredNames = Set(desired.map { DeviceActivityName($0.monitorName) })
        let monitoredUsageNames = Set(center.activities.filter { $0.rawValue.hasPrefix("stilltime.usage.") })

        let toStop = monitoredUsageNames.subtracting(desiredNames)
        if !toStop.isEmpty { center.stopMonitoring(Array(toStop)) }

        let desiredIDs = Set(desired.map(\.id))
        for limit in usageLimits where !desiredIDs.contains(limit.id) {
            FocusStorage.clearUsageShield(limit)
        }

        for limit in desired {
            let name = DeviceActivityName(limit.monitorName)
            guard !monitoredUsageNames.contains(name) else { continue }
            var start = DateComponents()
            start.hour = 0
            start.minute = 0
            start.second = 0
            var end = DateComponents()
            end.hour = 23
            end.minute = 59
            end.second = 59
            let deviceSchedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
            let event = DeviceActivityEvent(
                applications: limit.selection.applicationTokens,
                categories: limit.selection.categoryTokens,
                webDomains: limit.selection.webDomainTokens,
                threshold: DateComponents(minute: limit.dailyMinutes)
            )
            try? center.startMonitoring(name, during: deviceSchedule, events: [DeviceActivityEvent.Name(AppUsageLimit.eventName): event])
        }
    }

    func addUsageLimit(_ limit: AppUsageLimit) {
        usageLimits.append(limit)
    }

    func updateUsageLimit(_ limit: AppUsageLimit) {
        guard let index = usageLimits.firstIndex(where: { $0.id == limit.id }) else { return }
        usageLimits[index] = limit
    }

    func deleteUsageLimit(_ limit: AppUsageLimit) {
        usageLimits.removeAll { $0.id == limit.id }
    }

    /// Turning a limit off is PIN-gated the same way a routine's is, so it can't be silently
    /// switched off by whoever it's meant to cap.
    @discardableResult
    func setUsageLimitEnabled(_ limit: AppUsageLimit, enabled: Bool, parentPin: String? = nil) -> Bool {
        guard let index = usageLimits.firstIndex(where: { $0.id == limit.id }) else { return false }
        if usageLimits[index].isEnabled && !enabled && ParentLock.isEnabled {
            if ParentLock.lockRemainingSeconds > 0 {
                errorMessage = "Too many attempts. Try again in \(ParentLock.lockRemainingSeconds)s."
                return false
            }
            guard let pin = parentPin, verifyParentPin(pin) else {
                errorMessage = "Incorrect Parent PIN. Passcode required to turn off a daily limit."
                return false
            }
        }
        usageLimits[index].isEnabled = enabled
        return true
    }

    func addSchedule(_ schedule: FocusSchedule) {
        schedules.append(schedule)
    }

    func updateSchedule(_ schedule: FocusSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
    }

    func deleteSchedule(_ schedule: FocusSchedule) {
        schedules.removeAll { $0.id == schedule.id }
    }

    /// Turning a routine off is PIN-gated the same way ending a locked session is, so a routine
    /// can't be silently switched off by whoever it's meant to shield. Turning one on is free.
    @discardableResult
    func setScheduleEnabled(_ schedule: FocusSchedule, enabled: Bool, parentPin: String? = nil) -> Bool {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return false }
        if schedules[index].isEnabled && !enabled && ParentLock.isEnabled {
            if ParentLock.lockRemainingSeconds > 0 {
                errorMessage = "Too many attempts. Try again in \(ParentLock.lockRemainingSeconds)s."
                return false
            }
            guard let pin = parentPin, verifyParentPin(pin) else {
                errorMessage = "Incorrect Parent PIN. Passcode required to turn off a routine."
                return false
            }
        }
        schedules[index].isEnabled = enabled
        return true
    }

    var todayMinutes: Int {
        Int(history.filter { Calendar.current.isDateInToday($0.startedAt) }
            .reduce(0) { $0 + $1.actualSeconds } / 60)
    }

    /// Real focused minutes per day for the last `daysBack + 1` days (oldest first, today
    /// last), from actual session history -- the Activity tab used to show fixed placeholder
    /// numbers here regardless of real usage; this is what replaced them.
    func minutesByDay(daysBack: Int = 6, calendar: Calendar = .current) -> [(label: String, minutes: Int, isToday: Bool)] {
        (0...daysBack).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let minutes = Int(history.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.actualSeconds } / 60)
            let symbolIndex = calendar.component(.weekday, from: day) - 1
            let label = String(calendar.shortWeekdaySymbols[symbolIndex].prefix(1))
            return (label, minutes, offset == 0)
        }
    }

    var weekMinutes: Int {
        minutesByDay().reduce(0) { $0 + $1.minutes }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
