import SwiftUI

@main
struct MettitiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // Created once here rather than in `ContentView`, which is re-initialised whenever this body
    // runs (e.g. on every scene phase change); @State there would build and discard new ones each time.
    @State private var appIconPreference = AppIconPreferenceStore()
    @State private var temperaturePreference = TemperaturePreferenceStore()
    @State private var cardPreference = CardPreferenceStore()
    @State private var themePreference = ThemePreferenceStore()
    @State private var locationPreference: LocationPreferenceStore
    @State private var providerPreference: WeatherProviderPreferenceStore
    @State private var viewModel: DayPlanViewModel

    init() {
        let locationPreference = LocationPreferenceStore()
        let providerPreference = WeatherProviderPreferenceStore()
        _locationPreference = State(initialValue: locationPreference)
        _providerPreference = State(initialValue: providerPreference)
        _viewModel = State(initialValue: DayPlanViewModel(locationManager: LocationManager(), locationPreference: locationPreference, providerPreference: providerPreference))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: viewModel,
                locationPreference: locationPreference,
                temperaturePreference: temperaturePreference,
                cardPreference: cardPreference,
                themePreference: themePreference,
                providerPreference: providerPreference
            )
            .environment(appIconPreference)
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
