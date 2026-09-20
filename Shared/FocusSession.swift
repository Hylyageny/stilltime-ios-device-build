import Foundation

struct FocusSession: Codable, Identifiable, Equatable {
    let id: UUID
    let intention: String
    let startedAt: Date
    let endsAt: Date
    let blocksApps: Bool
    let isDeepFocus: Bool
    let isParentLocked: Bool
    let isSplitTime: Bool
    let focusMinutes: Int
    let restMinutes: Int
    var finishedAt: Date?
    var outcome: Outcome?

    enum Outcome: String, Codable {
        case completed, endedEarly, permissionRemoved
    }

    enum SplitPhase: String, Codable {
        case focus, rest
    }

    init(intention: String, minutes: Int, blocksApps: Bool, isDeepFocus: Bool = false, isParentLocked: Bool = false, isSplitTime: Bool = false, focusMinutes: Int = 25, restMinutes: Int = 5, now: Date = Date()) {
        self.id = UUID()
        self.intention = intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Time to focus" : String(intention.prefix(160))
        self.startedAt = now
        self.endsAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        self.blocksApps = blocksApps
        self.isDeepFocus = isDeepFocus
        self.isParentLocked = isParentLocked
        self.isSplitTime = isSplitTime
        self.focusMinutes = max(1, focusMinutes)
        self.restMinutes = max(1, restMinutes)
    }

    var monitorName: String { "stilltime.\(id.uuidString)" }
    var plannedSeconds: TimeInterval { endsAt.timeIntervalSince(startedAt) }

    func remaining(at date: Date) -> TimeInterval {
        max(0, min(plannedSeconds, endsAt.timeIntervalSince(date)))
    }

    func progress(at date: Date) -> Double {
        guard plannedSeconds > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: date) / plannedSeconds))
    }

    var cycleSeconds: TimeInterval {
        TimeInterval((focusMinutes + restMinutes) * 60)
    }

    func currentPhase(at date: Date) -> SplitPhase {
        guard isSplitTime else { return .focus }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0 else { return .focus }
        let timeInCycle = elapsed.truncatingRemainder(dividingBy: cycleSeconds)
        let focusSecs = TimeInterval(focusMinutes * 60)
        return timeInCycle < focusSecs ? .focus : .rest
    }

    func phaseRemaining(at date: Date) -> TimeInterval {
        guard isSplitTime else { return remaining(at: date) }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0 else { return TimeInterval(focusMinutes * 60) }
        let timeInCycle = elapsed.truncatingRemainder(dividingBy: cycleSeconds)
        let focusSecs = TimeInterval(focusMinutes * 60)
        if timeInCycle < focusSecs {
            return focusSecs - timeInCycle
        } else {
            return cycleSeconds - timeInCycle
        }
    }

    func focusProgress(at date: Date) -> Double {
        guard isSplitTime else { return progress(at: date) }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0 else { return 0 }
        let timeInCycle = elapsed.truncatingRemainder(dividingBy: cycleSeconds)
        let focusSecs = TimeInterval(focusMinutes * 60)
        return min(1.0, max(0.0, timeInCycle / focusSecs))
    }

    func restProgress(at date: Date) -> Double {
        guard isSplitTime else { return 0 }
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0 else { return 0 }
        let timeInCycle = elapsed.truncatingRemainder(dividingBy: cycleSeconds)
        let focusSecs = TimeInterval(focusMinutes * 60)
        let restSecs = TimeInterval(restMinutes * 60)
        if timeInCycle < focusSecs { return 0.0 }
        return min(1.0, max(0.0, (timeInCycle - focusSecs) / restSecs))
    }

    var actualSeconds: TimeInterval {
        guard let finishedAt else { return 0 }
        return max(0, min(finishedAt, endsAt).timeIntervalSince(startedAt))
    }

    func finished(_ outcome: Outcome, at date: Date) -> FocusSession {
        var copy = self
        copy.outcome = outcome
        copy.finishedAt = max(startedAt, min(date, endsAt))
        return copy
    }
}
