import SwiftUI

struct ContentView: View {
    let viewModel: DayPlanViewModel
    let locationPreference: LocationPreferenceStore
    let temperaturePreference: TemperaturePreferenceStore
    let cardPreference: CardPreferenceStore
    let themePreference: ThemePreferenceStore
    let providerPreference: WeatherProviderPreferenceStore
    let planWindowPreference: PlanWindowPreferenceStore
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .background(themeBackground)
            .toolbarColorScheme(themePreference.theme.overlayColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PlanWindowControl(window: viewModel.activePlanWindow) { window in
                        viewModel.selectPlanWindow(window)
                    }
                    // Plain black or white so the theme's accent doesn't color the bar's controls.
                    .tint(.primary)
                }
                // Bare words like the Invites app's title menu, rather than a glass button.
                .sharedBackgroundVisibility(.hidden)
                // In the Wide layout, Settings moves to the bottom-right corner, away from the
                // header's Plan Window control.
                if horizontalSizeClass == .regular {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        settingsButton
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        settingsButton
                    }
                }
            }
        }
        .environment(temperaturePreference)
        .environment(cardPreference)
        .tint(themePreference.theme.accentColor)
        .onChange(of: themePreference.appearance, initial: true) { _, appearance in
            applyAppearance(appearance)
        }
        .onAppear { viewModel.start() }
        .onChange(of: locationPreference.selection) {
            viewModel.locationSelectionDidChange()
        }
        .onChange(of: providerPreference.provider) {
            viewModel.providerDidChange()
        }
        .onChange(of: planWindowPreference.window) {
            viewModel.planWindowDidChange()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshIfStale() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                preference: locationPreference,
                temperaturePreference: temperaturePreference,
                cardPreference: cardPreference,
                themePreference: themePreference,
                providerPreference: providerPreference,
                planWindowPreference: planWindowPreference
            )
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape.fill")
        }
        .tint(.primary)
    }

    private var themeBackground: some View {
        LinearGradient(colors: themePreference.theme.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }

    /// Overrides the window's style rather than using preferredColorScheme, which
    /// doesn't update an open sheet and doesn't reliably revert to the system setting.
    private func applyAppearance(_ appearance: AppAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = appearance.userInterfaceStyle
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loadingWeather:
            VStack(spacing: 12) {
                ProgressCaption("Checking today's weather…")
                SkeletonLoadingView()
            }
        case .loaded(let weather, let hourly, let span, let provider, let recommendation):
            VStack(spacing: 12) {
                if let message = viewModel.refreshFailureMessage {
                    RefreshFailureNotice(message: message)
                } else if viewModel.isUpdatingSavedPlan {
                    ProgressCaption("Updating…")
                }
                DayPlanView(weather: weather, recommendation: recommendation, hourly: hourly, span: span, provider: provider) {
                    viewModel.retryRecommendation()
                }
            }
        case .failed(let message):
            ErrorStateView(message: message) {
                viewModel.retry()
            }
            .readableColumn()
            .padding(.top, 60)
        }
    }
}

#Preview {
    let locationPreference = LocationPreferenceStore()
    let providerPreference = WeatherProviderPreferenceStore()
    let planWindowPreference = PlanWindowPreferenceStore()
    ContentView(
        viewModel: DayPlanViewModel(locationManager: LocationManager(), locationPreference: locationPreference, providerPreference: providerPreference, planWindowPreference: planWindowPreference),
        locationPreference: locationPreference,
        temperaturePreference: TemperaturePreferenceStore(),
        cardPreference: CardPreferenceStore(),
        themePreference: ThemePreferenceStore(),
        providerPreference: providerPreference,
        planWindowPreference: planWindowPreference
    )
    .environment(AppIconPreferenceStore())
}
