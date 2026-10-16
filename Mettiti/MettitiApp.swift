import SwiftUI

@main
struct MettitiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appIconPreference = AppIconPreferenceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appIconPreference)
                .task { await appIconPreference.applyAtLaunch() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundPlanRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh(BackgroundPlanRefresh.taskIdentifier)) {
            await BackgroundPlanRefresh.run()
        }
    }
}
