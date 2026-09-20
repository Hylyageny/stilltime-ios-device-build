import SwiftUI

@main
struct StilltimeApp: App {
    @StateObject private var controller = FocusController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            StilltimeRoot()
                .environmentObject(controller)
                .preferredColorScheme(.dark)
                .tint(StilltimeStyle.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { controller.refresh() }
                }
        }
    }
}

enum StilltimeStyle {
    static let background = Color(red: 0.035, green: 0.065, blue: 0.085)
    static let surface = Color(red: 0.08, green: 0.12, blue: 0.15)
    static let accent = Color(red: 0.76, green: 0.97, blue: 0.30)
    static let accentRest = Color(red: 0.49, green: 0.83, blue: 0.99)
}
