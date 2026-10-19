import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var locationPreference = LocationPreferenceStore()
    @StateObject private var temperaturePreference = TemperaturePreferenceStore()
    @StateObject private var cardPreference = CardPreferenceStore()
    @StateObject private var themePreference = ThemePreferenceStore()
    @StateObject private var providerPreference: WeatherProviderPreferenceStore
    @StateObject private var viewModel: DayPlanViewModel
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let manager = LocationManager()
        let preference = LocationPreferenceStore()
        let providerPreference = WeatherProviderPreferenceStore()
        _locationManager = StateObject(wrappedValue: manager)
        _locationPreference = StateObject(wrappedValue: preference)
        _providerPreference = StateObject(wrappedValue: providerPreference)
        _viewModel = StateObject(wrappedValue: DayPlanViewModel(locationManager: manager, locationPreference: preference, providerPreference: providerPreference))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mettiti")
                    .font(.largeTitle.bold())
                    .shadow(color: .black.opacity(themePreference.theme == .none ? 0 : 0.25), radius: 4, y: 1)
                    .environment(\.colorScheme, themePreference.theme.overlayColorScheme ?? colorScheme)
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundStyle(headerIconColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh")

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(headerIconColor)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                content
                    .padding()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(themeBackground)
        .environmentObject(temperaturePreference)
        .environmentObject(cardPreference)
        .tint(themePreference.theme.accentColor)
        .onChange(of: themePreference.appearance, initial: true) { _, appearance in
            applyAppearance(appearance)
        }
        .onAppear { viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.appDidBecomeActive() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                preference: locationPreference,
                temperaturePreference: temperaturePreference,
                cardPreference: cardPreference,
                themePreference: themePreference,
                providerPreference: providerPreference
            )
        }
    }

    private var themeBackground: some View {
        LinearGradient(colors: themePreference.theme.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }

    /// Plain black or white icons so the theme's accent tint doesn't color them.
    private var headerIconColor: Color {
        colorScheme == .dark ? .white : .black
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

    private var isRefreshing: Bool {
        switch viewModel.state {
        case .loadingWeather:
            return true
        case .loaded(_, _, _, let recommendation):
            return recommendation.isInProgress || viewModel.isUpdatingSavedPlan
        case .idle, .failed:
            return false
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
        case .loaded(let weather, let hourly, let provider, let recommendation):
            VStack(spacing: 12) {
                if let message = viewModel.refreshFailureMessage {
                    RefreshFailureNotice(message: message)
                } else if viewModel.isUpdatingSavedPlan {
                    ProgressCaption("Updating…")
                }
                DayPlanView(weather: weather, recommendation: recommendation, hourly: hourly, provider: provider) {
                    viewModel.retryRecommendation()
                }
            }
        case .failed(let message):
            ErrorStateView(message: message) {
                viewModel.retry()
            }
            .padding(.top, 60)
        }
    }
}

#Preview {
    ContentView()
}
