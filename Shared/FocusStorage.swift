import Foundation
import FamilyControls
import ManagedSettings

enum FocusStorage {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.example.stilltime"
    }

    // Never fall back to standard defaults: the extension must see the same session.
    static var shared: UserDefaults? { UserDefaults(suiteName: groupID) }
    static var groupIsAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static let shieldStore = ManagedSettingsStore(named: .init("stilltime.session"))

    static var active: FocusSession? {
        get { decode(FocusSession.self, key: "activeSession.v1") }
        set { encode(newValue, key: "activeSession.v1") }
    }

    static var selection: FamilyActivitySelection {
        get { decode(FamilyActivitySelection.self, key: "selection.v1") ?? FamilyActivitySelection() }
        set { encode(newValue, key: "selection.v1") }
    }

    static var schedules: [FocusSchedule] {
        get { decode([FocusSchedule].self, key: "schedules.v1") ?? FocusSchedule.defaultPresets }
        set { encode(newValue, key: "schedules.v1") }
    }

    static func applyShields() {
        let selected = selection
        shieldStore.shield.applications = selected.applicationTokens.isEmpty ? nil : selected.applicationTokens
        shieldStore.shield.applicationCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
        shieldStore.shield.webDomains = selected.webDomainTokens.isEmpty ? nil : selected.webDomainTokens
        shieldStore.shield.webDomainCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
    }

    /// A named Managed Settings store scoped to one routine, so multiple routines (and the
    /// manual session store above) can each hold shields independently without clobbering
    /// each other when their windows overlap.
    static func scheduleStore(_ schedule: FocusSchedule) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init("stilltime.schedule.\(schedule.id.uuidString)"))
    }

    /// BLOCK_SELECTED shields exactly the routine's selection, same as a manual session.
    /// ALLOW_ONLY shields every app/site category except the routine's selection -- "allow
    /// these apps, shield everything else" -- using Managed Settings' own all-except-these
    /// policy rather than enumerating every installed app ourselves.
    ///
    /// KNOWN PLATFORM RISK (verify on a real device before relying on this mode): multiple
    /// independent developer reports (Apple Developer Forums threads 766766, 750988, 762287)
    /// describe ActivityCategoryPolicy.all(except:) still shielding apps that were passed in
    /// `except:`, with an Apple engineer acknowledging it as a known issue (open bug
    /// FB15500605, unresolved as of the last report we found). This is a platform bug
    /// candidate, not necessarily something wrong in this code -- but it means ALLOW_ONLY
    /// routines may not actually allow their chosen apps even when everything here is
    /// correct. Confirm this specific behavior on-device (DEVICE_TESTS.md's "Allow-only
    /// routine" case) before shipping the feature as reliable, and have a fallback plan
    /// (e.g. falling back to BLOCK_SELECTED with an enumerated deny-list) if it's still broken.
    static func applyScheduleShields(_ schedule: FocusSchedule) {
        let store = scheduleStore(schedule)
        let selected = schedule.selection
        switch schedule.shieldMode {
        case .blockSelected:
            store.shield.applications = selected.applicationTokens.isEmpty ? nil : selected.applicationTokens
            store.shield.applicationCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
            store.shield.webDomains = selected.webDomainTokens.isEmpty ? nil : selected.webDomainTokens
            store.shield.webDomainCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
        case .allowOnly:
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: selected.applicationTokens)
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: selected.webDomainTokens)
        }
    }

    static func clearScheduleShields(_ schedule: FocusSchedule) {
        scheduleStore(schedule).clearAllSettings()
    }

    static var usageLimits: [AppUsageLimit] {
        get { decode([AppUsageLimit].self, key: "usageLimits.v1") ?? [] }
        set { encode(newValue, key: "usageLimits.v1") }
    }

    /// A named Managed Settings store per usage limit, separate from scheduleStore(_:) and the
    /// manual-session store, so a cumulative daily cap can hold its own shield without
    /// clobbering (or being cleared by) a routine's or a manual session's.
    static func usageStore(_ limit: AppUsageLimit) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init("stilltime.usage.\(limit.id.uuidString)"))
    }

    static func applyUsageShield(_ limit: AppUsageLimit) {
        let store = usageStore(limit)
        let selected = limit.selection
        store.shield.applications = selected.applicationTokens.isEmpty ? nil : selected.applicationTokens
        store.shield.applicationCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
        store.shield.webDomains = selected.webDomainTokens.isEmpty ? nil : selected.webDomainTokens
        store.shield.webDomainCategories = selected.categoryTokens.isEmpty ? nil : .specific(selected.categoryTokens)
    }

    static func clearUsageShield(_ limit: AppUsageLimit) {
        usageStore(limit).clearAllSettings()
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = shared?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T?, key: String) {
        guard let value else { shared?.removeObject(forKey: key); return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        shared?.set(data, forKey: key)
    }
}
