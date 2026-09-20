import Combine
import FamilyControls
import SwiftUI

struct StilltimeRoot: View {
    @EnvironmentObject private var controller: FocusController
    var body: some View {
        TabView {
            FocusView().tabItem { Label("Focus", systemImage: "timer") }
            SchedulesView().tabItem { Label("Routines", systemImage: "calendar.badge.clock") }
            ActivityView().tabItem { Label("Activity", systemImage: "chart.bar.fill") }
            FocusSettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(StilltimeStyle.accent)
        .alert("Stilltime", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        ), actions: { Button("OK") { controller.errorMessage = nil } },
           message: { Text(controller.errorMessage ?? "") })
    }
}

private struct FocusView: View {
    @EnvironmentObject private var controller: FocusController
    @State private var intention = ""
    @State private var minutes = 25
    @State private var blocksApps = true
    @State private var isDeepFocus = false
    @State private var isParentLocked = false
    @State private var isSplitTime = false
    @State private var focusMinutes = 25
    @State private var restMinutes = 5
    @State private var pickerPresented = false
    @State private var endingSession = false
    @State private var pinPromptPresented = false
    @State private var inputPin = ""
    @State private var didSyncDefaultMinutes = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Header Status Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("STILLTIME / FOCUS")
                            .font(.caption.bold())
                            .foregroundStyle(StilltimeStyle.accent)
                        Text("Make room for\nwhat matters.")
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .lineSpacing(2)

                        HStack {
                            Text("Focused today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(controller.todayMinutes) min")
                                .font(.title3.bold())
                                .foregroundStyle(StilltimeStyle.accent)
                        }
                        .padding(16)
                        .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }

                    if let session = controller.active {
                        activeView(session)
                    } else {
                        setupView
                    }
                }
                .padding(20)
            }
            .background(StilltimeStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .familyActivityPicker(isPresented: $pickerPresented, selection: $controller.selection)
            .confirmationDialog("End active focus session?", isPresented: $endingSession, titleVisibility: .visible) {
                Button("End session and unblock", role: .destructive) {
                    if let active = controller.active, (active.isDeepFocus || active.isParentLocked || controller.parentPinEnabled) {
                        pinPromptPresented = true
                    } else {
                        controller.endEarly()
                    }
                }
                Button("Keep focusing", role: .cancel) {}
            } message: {
                Text("Your completed focus time will be saved in your activity history.")
            }
            .sheet(isPresented: $pinPromptPresented) {
                PinUnlockSheet(inputPin: $inputPin) {
                    controller.endEarly(parentPin: inputPin)
                    inputPin = ""
                }
            }
            .onReceive(timer) { controller.refresh(now: $0) }
            .onAppear {
                guard !didSyncDefaultMinutes else { return }
                didSyncDefaultMinutes = true
                if controller.active == nil { minutes = controller.defaultMinutes }
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Intention Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Intention")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("What are you focusing on?", text: $intention)
                    .padding(16)
                    .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            }

            // Presets Header & 3 Horizontal Cards (Matching Mockup)
            VStack(alignment: .leading, spacing: 10) {
                Text("Presets")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    MockupPresetCard(emoji: "🍵", title: "Reset", duration: "15 min", isSelected: minutes == 15) {
                        minutes = 15
                        isDeepFocus = false
                    }
                    MockupPresetCard(emoji: "🌱", title: "Deep work", duration: "25 min", isSelected: minutes == 25) {
                        minutes = 25
                        isDeepFocus = true
                    }
                    MockupPresetCard(emoji: "🌙", title: "Evening", duration: "45 min", isSelected: minutes == 45) {
                        minutes = 45
                        isDeepFocus = false
                    }
                }
            }

            // Pick a length pill row (Matching Mockup: 10, 25, 30, 60, 90)
            VStack(alignment: .leading, spacing: 10) {
                Text("Or pick a length")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach([10, 25, 30, 60, 90], id: \.self) { val in
                        Button {
                            minutes = val
                        } label: {
                            Text("\(val)")
                                .font(.subheadline.bold())
                                .frame(width: 44, height: 44)
                                .background(minutes == val ? StilltimeStyle.accent.opacity(0.25) : StilltimeStyle.surface, in: Circle())
                                .overlay(Circle().stroke(minutes == val ? StilltimeStyle.accent : Color.clear, lineWidth: 2))
                                .foregroundStyle(minutes == val ? StilltimeStyle.accent : .white)
                        }
                    }
                }
            }

            // Split Time Mode Switch & Ratio Selection
            VStack(alignment: .leading, spacing: 14) {
                Toggle("⚡ Split Time Mode (Pomodoro)", isOn: $isSplitTime)
                    .font(.headline)
                    .foregroundStyle(isSplitTime ? StilltimeStyle.accent : .white)

                if isSplitTime {
                    Text("Select Work / Rest Ratio")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        RatioChip(title: "25 / 5", sub: "Standard", isSelected: focusMinutes == 25 && restMinutes == 5) {
                            focusMinutes = 25
                            restMinutes = 5
                            minutes = 30
                        }
                        RatioChip(title: "50 / 10", sub: "Deep Work", isSelected: focusMinutes == 50 && restMinutes == 10) {
                            focusMinutes = 50
                            restMinutes = 10
                            minutes = 60
                        }
                        RatioChip(title: "15 / 3", sub: "Sprint", isSelected: focusMinutes == 15 && restMinutes == 3) {
                            focusMinutes = 15
                            restMinutes = 3
                            minutes = 18
                        }
                    }
                }
            }
            .padding(18)
            .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 20))

            // Shielding Card (Matching Mockup)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $blocksApps) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shielding")
                            .font(.headline.bold())
                        Text("Silence notifications during the session")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(StilltimeStyle.accent)

                if blocksApps {
                    if controller.authorized {
                        Button {
                            pickerPresented = true
                        } label: {
                            HStack {
                                Label("Select Apps & Categories", systemImage: "app.badge.checkmark")
                                Spacer()
                                Text("\(controller.selectionCount) selected")
                                    .foregroundStyle(StilltimeStyle.accent)
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        Button {
                            Task { await controller.requestPermission() }
                        } label: {
                            Label("Enable Screen Time Authorization", systemImage: "shield.dashed")
                                .font(.caption.bold())
                                .foregroundStyle(StilltimeStyle.accent)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(18)
            .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 20))

            // Large Full-Width Lime Green Start Button (Matching Mockup)
            Button {
                controller.start(
                    intention: intention,
                    minutes: minutes,
                    blocksApps: blocksApps,
                    isDeepFocus: isDeepFocus,
                    isParentLocked: controller.parentPinEnabled,
                    isSplitTime: isSplitTime,
                    focusMinutes: focusMinutes,
                    restMinutes: restMinutes
                )
            } label: {
                Text("Start")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(StilltimeStyle.accent, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
            }
            .disabled(blocksApps && (!controller.authorized || controller.selectionCount == 0))
        }
    }

    private func activeView(_ session: FocusSession) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(session.intention.isEmpty ? "Draft the proposal intro" : session.intention)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("One session. A quieter phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if session.isDeepFocus {
                    Label("Deep Focus Locked", systemImage: "lock.shield.fill")
                        .font(.caption.bold())
                        .foregroundStyle(StilltimeStyle.accent)
                        .padding(.top, 4)
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let totalRemaining = Int(ceil(session.remaining(at: timeline.date)))
                let phaseRemaining = Int(ceil(session.phaseRemaining(at: timeline.date)))
                let currentPhase = session.currentPhase(at: timeline.date)

                if session.isSplitTime {
                    // Split Time Active Mode: Dual Ring Timer
                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Text(currentPhase == .focus ? "🔥 FOCUS PHASE" : "☕ REST BREAK PHASE")
                                .font(.caption.bold())
                                .foregroundStyle(currentPhase == .focus ? StilltimeStyle.accent : StilltimeStyle.accentRest)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(currentPhase == .focus ? StilltimeStyle.accent.opacity(0.15) : StilltimeStyle.accentRest.opacity(0.15), in: Capsule())
                        }

                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 16)
                            Circle()
                                .trim(from: 0, to: session.focusProgress(at: timeline.date))
                                .stroke(StilltimeStyle.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .shadow(color: StilltimeStyle.accent.opacity(0.4), radius: 8)

                            Circle()
                                .inset(by: 22)
                                .stroke(Color.white.opacity(0.05), lineWidth: 10)
                            Circle()
                                .inset(by: 22)
                                .trim(from: 0, to: session.restProgress(at: timeline.date))
                                .stroke(StilltimeStyle.accentRest, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: 4) {
                                Text(String(format: "%02d:%02d", phaseRemaining / 60, phaseRemaining % 60))
                                    .font(.system(size: 50, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(currentPhase == .focus ? StilltimeStyle.accent : StilltimeStyle.accentRest)
                                Text("TIME REMAINING")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: 290)
                    }
                } else {
                    // Standard Timer Ring (Matching Mockup)
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: session.progress(at: timeline.date))
                            .stroke(StilltimeStyle.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: StilltimeStyle.accent.opacity(0.5), radius: 10)
                        VStack(spacing: 6) {
                            Text(String(format: "%02d:%02d", totalRemaining / 60, totalRemaining % 60))
                                .font(.system(size: 58, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("TIME REMAINING")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .tracking(1)
                        }
                    }
                    .frame(maxWidth: 290)
                    .padding(10)
                }
            }

            Button("End Session Early") {
                endingSession = true
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1.5))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct MockupPresetCard: View {
    let emoji: String
    let title: String
    let duration: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(isSelected ? Color.black : .white)
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.black.opacity(0.7) : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? StilltimeStyle.accent : StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct RatioChip: View {
    let title: String
    let sub: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.black.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? StilltimeStyle.accent : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isSelected ? Color.black : .white)
        }
    }
}

private struct SchedulesView: View {
    @EnvironmentObject private var controller: FocusController
    @State private var editingSchedule: FocusSchedule?
    @State private var creatingNew = false
    @State private var pinPromptSchedule: FocusSchedule?
    @State private var inputPin = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Status Card (Matching Mockup)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STILLTIME / ROUTINES")
                            .font(.caption.bold())
                            .foregroundStyle(StilltimeStyle.accent)
                        Text("Routines")
                            .font(.system(size: 32, weight: .bold))
                        Text("A routine shields its apps automatically at the scheduled time, even while Stilltime is closed. Add apps and turn a routine on to activate it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if controller.schedules.isEmpty {
                        Text("No routines yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This week")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        VStack(spacing: 12) {
                            ForEach(controller.schedules) { schedule in
                                RoutineRow(schedule: schedule) { enabled in
                                    if !enabled && controller.parentPinEnabled {
                                        pinPromptSchedule = schedule
                                    } else {
                                        controller.setScheduleEnabled(schedule, enabled: enabled)
                                    }
                                } onTap: {
                                    editingSchedule = schedule
                                }
                            }
                        }
                    }

                    Button {
                        creatingNew = true
                    } label: {
                        Text("New routine")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(StilltimeStyle.accent, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.black)
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }
            .background(StilltimeStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingSchedule) { schedule in
                RoutineEditorSheet(existing: schedule)
            }
            .sheet(isPresented: $creatingNew) {
                RoutineEditorSheet(existing: nil)
            }
            .sheet(item: $pinPromptSchedule) { schedule in
                PinUnlockSheet(
                    inputPin: $inputPin,
                    message: "Passcode required to turn off this routine.",
                    confirmLabel: "Unlock & Turn Off"
                ) {
                    controller.setScheduleEnabled(schedule, enabled: false, parentPin: inputPin)
                    inputPin = ""
                }
            }
        }
    }
}

private struct RoutineRow: View {
    let schedule: FocusSchedule
    let onToggle: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: schedule.iconName)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { schedule.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(StilltimeStyle.accent)
        }
        .padding(16)
        .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .opacity(schedule.isEnabled ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var metaText: String {
        guard schedule.selectionCount > 0 else {
            return "\(schedule.daysString) • \(schedule.timeString) • no apps chosen yet"
        }
        let modeLabel = schedule.shieldMode == .allowOnly ? "Allow \(schedule.selectionCount)" : "Shield \(schedule.selectionCount)"
        return "\(schedule.daysString) • \(schedule.timeString) • \(modeLabel)"
    }
}

private struct RoutineEditorSheet: View {
    @EnvironmentObject private var controller: FocusController
    @Environment(\.dismiss) private var dismiss
    let existing: FocusSchedule?

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var days: Set<Int>
    @State private var isDeepFocus: Bool
    @State private var shieldMode: ShieldMode
    @State private var selection: FamilyActivitySelection
    @State private var pickerPresented = false
    @State private var validationMessage: String?

    private static let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    init(existing: FocusSchedule?) {
        self.existing = existing
        func date(hour: Int, minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        _title = State(initialValue: existing?.title ?? "")
        _start = State(initialValue: date(hour: existing?.startHour ?? 9, minute: existing?.startMinute ?? 0))
        _end = State(initialValue: date(hour: existing?.endHour ?? 10, minute: existing?.endMinute ?? 0))
        _days = State(initialValue: existing?.daysOfWeek ?? [2, 3, 4, 5, 6])
        _isDeepFocus = State(initialValue: existing?.isDeepFocus ?? false)
        _shieldMode = State(initialValue: existing?.shieldMode ?? .blockSelected)
        _selection = State(initialValue: existing?.selection ?? FamilyActivitySelection())
    }

    private var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine name", text: $title)
                }
                Section("Mode") {
                    Picker("Mode", selection: $shieldMode) {
                        Text("Shield selected apps").tag(ShieldMode.blockSelected)
                        Text("Allow only these apps").tag(ShieldMode.allowOnly)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Time") {
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section("Days") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                if days.contains(day) { days.remove(day) } else { days.insert(day) }
                            } label: {
                                Text(Self.dayLabels[day - 1])
                                    .font(.caption.bold())
                                    .frame(width: 32, height: 32)
                                    .background(days.contains(day) ? StilltimeStyle.accent : Color.white.opacity(0.08), in: Circle())
                                    .foregroundStyle(days.contains(day) ? Color.black : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section(shieldMode == .allowOnly ? "Allowed apps" : "Shielded apps") {
                    Button {
                        pickerPresented = true
                    } label: {
                        HStack {
                            Text(shieldMode == .allowOnly ? "Choose the only apps allowed" : "Choose apps to shield")
                            Spacer()
                            Text("\(selectionCount) selected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Deep Focus (PIN required to turn off)", isOn: $isDeepFocus)
                }
                if existing != nil {
                    Section {
                        Button("Delete routine", role: .destructive) {
                            controller.deleteSchedule(existing!)
                            dismiss()
                        }
                    }
                }
            }
            .familyActivityPicker(isPresented: $pickerPresented, selection: $selection)
            .navigationTitle(existing == nil ? "New Routine" : "Edit Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || days.isEmpty)
                }
            }
            .alert("Stilltime", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK") { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }

    private func save() {
        guard selectionCount > 0 else {
            validationMessage = shieldMode == .allowOnly ? "Choose at least one app to allow." : "Choose at least one app to shield."
            return
        }
        let startComponents = Calendar.current.dateComponents([.hour, .minute], from: start)
        let endComponents = Calendar.current.dateComponents([.hour, .minute], from: end)
        guard startComponents.hour != endComponents.hour || startComponents.minute != endComponents.minute else {
            validationMessage = "Start and end time can't be the same."
            return
        }
        var schedule = existing ?? FocusSchedule(
            title: title,
            startHour: startComponents.hour ?? 9,
            startMinute: startComponents.minute ?? 0,
            endHour: endComponents.hour ?? 10,
            endMinute: endComponents.minute ?? 0,
            daysOfWeek: days
        )
        schedule.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.startHour = startComponents.hour ?? 9
        schedule.startMinute = startComponents.minute ?? 0
        schedule.endHour = endComponents.hour ?? 10
        schedule.endMinute = endComponents.minute ?? 0
        schedule.daysOfWeek = days
        schedule.isDeepFocus = isDeepFocus
        schedule.shieldMode = shieldMode
        schedule.selection = selection

        if existing != nil {
            controller.updateSchedule(schedule)
        } else {
            controller.addSchedule(schedule)
        }
        dismiss()
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var controller: FocusController

    private func formattedDuration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Status Card (Matching Mockup)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STILLTIME / ACTIVITY")
                            .font(.caption.bold())
                            .foregroundStyle(StilltimeStyle.accent)
                        Text("Activity")
                            .font(.system(size: 32, weight: .bold))
                    }

                    // Focused this week summary card -- real total from session history, not a
                    // fixed placeholder.
                    HStack {
                        Text("Focused this week")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formattedDuration(controller.weekMinutes))
                            .font(.title2.bold())
                            .foregroundStyle(StilltimeStyle.accent)
                    }
                    .padding(18)
                    .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 18))

                    // Last 7 days Bar Chart -- real per-day minutes, today highlighted.
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Last 7 days")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        let days = controller.minutesByDay()
                        let maxMinutes = max(1, days.map(\.minutes).max() ?? 1)
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                let barHeight: CGFloat = day.minutes > 0
                                    ? max(8, CGFloat(day.minutes) / CGFloat(maxMinutes) * 90)
                                    : 4
                                BarColumn(day: day.label, height: barHeight, isHighlighted: day.isToday)
                            }
                        }
                        .frame(height: 120)
                        .padding(.vertical, 8)
                    }
                    .padding(18)
                    .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 20))

                    // Sessions Completed Card -- the real count, no invented floor.
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sessions completed")
                                .font(.headline.bold())
                            Text("Just the count. Nothing to prove.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(controller.history.count)")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(18)
                    .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(20)
            }
            .background(StilltimeStyle.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct BarColumn: View {
    let day: String
    let height: CGFloat
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? StilltimeStyle.accent : Color.white.opacity(0.12))
                .frame(height: height)
            Text(day)
                .font(.caption2.bold())
                .foregroundStyle(isHighlighted ? StilltimeStyle.accent : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FocusSettingsView: View {
    @EnvironmentObject private var controller: FocusController
    @State private var settingPin = false
    @State private var newPin = ""
    @State private var editingLimit: AppUsageLimit?
    @State private var creatingNewLimit = false
    @State private var pinPromptLimit: AppUsageLimit?
    @State private var limitInputPin = ""
    @State private var showingDurationPicker = false
    @State private var showingSoundPicker = false
    @State private var showingAboutStreaks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Status Card (Matching Mockup)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STILLTIME / SETTINGS")
                            .font(.caption.bold())
                            .foregroundStyle(StilltimeStyle.accent)
                        Text("Settings")
                            .font(.system(size: 32, weight: .bold))
                        Text("Control, without commentary.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Section: Session
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Session")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Button { showingDurationPicker = true } label: {
                            SettingsRow(title: "Default duration", detail: "\(controller.defaultMinutes) min · used when you open the Focus tab")
                        }
                        .buttonStyle(.plain)

                        Button { showingSoundPicker = true } label: {
                            SettingsRow(title: "Completion sound", detail: "\(controller.completionSound.label) · plays only while Stilltime is open")
                        }
                        .buttonStyle(.plain)
                    }

                    // Section: Daily Limits
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Daily Limits")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text("A cumulative cap: once total time in these apps reaches the minutes chosen today, they shield until tomorrow -- regardless of when that time happens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if controller.usageLimits.isEmpty {
                            Text("No daily limits yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(controller.usageLimits) { limit in
                                    UsageLimitRow(limit: limit) { enabled in
                                        if !enabled && controller.parentPinEnabled {
                                            pinPromptLimit = limit
                                        } else {
                                            controller.setUsageLimitEnabled(limit, enabled: enabled)
                                        }
                                    } onTap: {
                                        editingLimit = limit
                                    }
                                }
                            }
                        }

                        Button {
                            creatingNewLimit = true
                        } label: {
                            Text("New daily limit")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(StilltimeStyle.accent)
                        }
                    }

                    // Section: Parent Lock
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Parent Lock")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Parent Passcode PIN")
                                    .font(.subheadline.bold())
                                Text("Require 4-digit PIN to end Deep Focus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(controller.parentPinSet ? "Change PIN" : "Set PIN") {
                                settingPin = true
                            }
                            .font(.caption.bold())
                            .foregroundStyle(StilltimeStyle.accent)
                        }
                        .padding(16)
                        .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }

                    // Section: About
                    VStack(alignment: .leading, spacing: 14) {
                        Text("About")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Button { showingAboutStreaks = true } label: {
                            SettingsRow(title: "Why no streaks", detail: "A note on how Stilltime measures things")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(StilltimeStyle.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $settingPin) {
                PinSetupSheet(newPin: $newPin) {
                    _ = controller.setParentPin(newPin)
                    newPin = ""
                    settingPin = false
                }
            }
            .sheet(item: $editingLimit) { limit in
                UsageLimitEditorSheet(existing: limit)
            }
            .sheet(isPresented: $creatingNewLimit) {
                UsageLimitEditorSheet(existing: nil)
            }
            .sheet(item: $pinPromptLimit) { limit in
                PinUnlockSheet(
                    inputPin: $limitInputPin,
                    message: "Passcode required to turn off this daily limit.",
                    confirmLabel: "Unlock & Turn Off"
                ) {
                    controller.setUsageLimitEnabled(limit, enabled: false, parentPin: limitInputPin)
                    limitInputPin = ""
                }
            }
            .confirmationDialog("Default duration", isPresented: $showingDurationPicker, titleVisibility: .visible) {
                ForEach([10, 15, 25, 30, 45, 60, 90], id: \.self) { value in
                    Button("\(value) minutes") { controller.defaultMinutes = value }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Completion sound", isPresented: $showingSoundPicker, titleVisibility: .visible) {
                ForEach(CompletionSound.allCases, id: \.self) { option in
                    Button(option.label) { controller.completionSound = option }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Why no streaks", isPresented: $showingAboutStreaks) {
                Button("OK") {}
            } message: {
                Text("Stilltime doesn't track streaks, badges, or daily goals. A missed day isn't a broken streak to mourn, and a long one isn't a number to protect by opening the app out of guilt. Activity here is just a plain record of the sessions you actually ran -- nothing is invented to make a day look better or worse than it was.")
            }
        }
    }
}

private struct UsageLimitRow: View {
    let limit: AppUsageLimit
    let onToggle: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(limit.title)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { limit.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(StilltimeStyle.accent)
        }
        .padding(16)
        .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .opacity(limit.isEnabled ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var metaText: String {
        guard limit.selectionCount > 0 else { return "\(limit.dailyMinutes) min/day • no apps chosen yet" }
        return "\(limit.dailyMinutes) min/day • \(limit.selectionCount) selected"
    }
}

private struct UsageLimitEditorSheet: View {
    @EnvironmentObject private var controller: FocusController
    @Environment(\.dismiss) private var dismiss
    let existing: AppUsageLimit?

    @State private var title: String
    @State private var dailyMinutes: Int
    @State private var selection: FamilyActivitySelection
    @State private var pickerPresented = false
    @State private var validationMessage: String?

    init(existing: AppUsageLimit?) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _dailyMinutes = State(initialValue: existing?.dailyMinutes ?? 45)
        _selection = State(initialValue: existing?.selection ?? FamilyActivitySelection())
    }

    private var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Instagram", text: $title)
                }
                Section("Daily budget") {
                    Stepper("\(dailyMinutes) minutes / day", value: $dailyMinutes, in: 5...480, step: 5)
                }
                Section {
                    Button {
                        pickerPresented = true
                    } label: {
                        HStack {
                            Text("Choose apps to cap")
                            Spacer()
                            Text("\(selectionCount) selected")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Apps")
                } footer: {
                    Text("Once total time in these apps reaches \(dailyMinutes) minutes today, they shield until tomorrow.")
                }
                if existing != nil {
                    Section {
                        Button("Delete daily limit", role: .destructive) {
                            controller.deleteUsageLimit(existing!)
                            dismiss()
                        }
                    }
                }
            }
            .familyActivityPicker(isPresented: $pickerPresented, selection: $selection)
            .navigationTitle(existing == nil ? "New Daily Limit" : "Edit Daily Limit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Stilltime", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK") { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }

    private func save() {
        guard selectionCount > 0 else {
            validationMessage = "Choose at least one app to cap."
            return
        }
        var limit = existing ?? AppUsageLimit(title: title, dailyMinutes: dailyMinutes)
        limit.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        limit.dailyMinutes = dailyMinutes
        limit.selection = selection

        if existing != nil {
            controller.updateUsageLimit(limit)
        } else {
            controller.addUsageLimit(limit)
        }
        dismiss()
    }
}

private struct SettingsRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(StilltimeStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PinUnlockSheet: View {
    @Binding var inputPin: String
    var message: String = "Passcode required to end this locked focus session."
    var confirmLabel: String = "Unlock & End"
    let onUnlock: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Parent PIN")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("4-digit PIN", text: $inputPin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.bold())
                .padding(16)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            Button(confirmLabel) {
                onUnlock()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(StilltimeStyle.accent)
            .foregroundStyle(.black)
        }
        .padding(24)
        .presentationDetents([.height(280)])
    }
}

private struct PinSetupSheet: View {
    @Binding var newPin: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Set Parent Passcode PIN")
                .font(.title2.bold())
            Text("Enter a 4-digit passcode for parent controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("4-digit PIN", text: $newPin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.bold())
                .padding(16)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            Button("Save PIN") {
                onSave()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(StilltimeStyle.accent)
            .foregroundStyle(.black)
            .disabled(newPin.count != 4)
        }
        .padding(24)
        .presentationDetents([.height(280)])
    }
}
