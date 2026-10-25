import SwiftUI
import CoreLocation
import MapKit

struct SettingsView: View {
    let preference: LocationPreferenceStore
    @Bindable var temperaturePreference: TemperaturePreferenceStore
    @Bindable var cardPreference: CardPreferenceStore
    @Bindable var themePreference: ThemePreferenceStore
    @Bindable var providerPreference: WeatherProviderPreferenceStore
    @Bindable var planWindowPreference: PlanWindowPreferenceStore
    @Environment(AppIconPreferenceStore.self) private var appIconPreference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    NavigationLink {
                        LocationSettingsView(preference: preference)
                    } label: {
                        LabeledContent("Weather Location", value: locationName)
                    }
                }

                Section {
                    Picker("Weather Source", selection: $providerPreference.provider) {
                        ForEach(WeatherProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }

                    Picker("Plan Window", selection: $planWindowPreference.window) {
                        ForEach(PlanWindow.allCases) { window in
                            Text(window.name()).tag(window)
                        }
                    }

                    Picker("Temperature Unit", selection: $temperaturePreference.unit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } header: {
                    Text("Forecast")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plan Window is how far ahead from now the outfit advice covers. Rest of day runs until midnight, but at least 3 hours.")
                        Text("Apple Weather uses the same data as the Weather app. With either source, the hourly chart's shaded band shows the forecast spread from Open-Meteo's ensemble.")
                    }
                }

                Section {
                    ChoiceRow("Theme") {
                        ForEach(AppTheme.allCases) { theme in
                            let isSelected = themePreference.theme == theme
                            Button {
                                themePreference.theme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(theme.swatchGradient)
                                        .frame(width: 46, height: 46)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    Color.primary,
                                                    lineWidth: isSelected ? 3 : 0
                                                )
                                        )
                                        .overlay {
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    Text(theme.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(theme.label))
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }

                    Picker("Light/Dark", selection: $themePreference.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }

                    if appIconPreference.supportsAlternateIcons {
                        ChoiceRow("App Icon") {
                            appIconOption(.default, label: LocalizedStringResource("Default"), thumbnailName: appIconPreference.buildIcon.thumbnailName)
                            ForEach(ThemeIcon.allCases) { icon in
                                appIconOption(.theme(icon), label: icon.label, thumbnailName: icon.thumbnailName)
                            }
                        }
                    }

                    NavigationLink("Cards") {
                        CardSettingsView(cardPreference: cardPreference)
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("The theme color is used for the main screen's background. Cards sets which cards the main screen shows, and in what order.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
    }

    private static let iconThumbnailSize: CGFloat = 52
    /// The exported thumbnails are masked with a continuous corner of about 25.8% of their width.
    private static let iconThumbnailCornerRadius = iconThumbnailSize * 0.258
    private static let iconSelectionGap: CGFloat = 4

    private func appIconOption(_ option: AppIconSelection, label: LocalizedStringResource, thumbnailName: String) -> some View {
        let isSelected = appIconPreference.selection == option
        return Button {
            Task { await appIconPreference.select(option) }
        } label: {
            VStack(spacing: 6) {
                Image(thumbnailName)
                    .resizable()
                    .frame(width: Self.iconThumbnailSize, height: Self.iconThumbnailSize)
                    .overlay(
                        // Concentric with the icon: the ring sits outside it, so its radius grows by the gap.
                        RoundedRectangle(cornerRadius: Self.iconThumbnailCornerRadius + Self.iconSelectionGap, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: isSelected ? 3 : 0)
                            .padding(-Self.iconSelectionGap)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body.bold())
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.primary)
                                .offset(x: 6, y: 6)
                        }
                    }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(Self.iconSelectionGap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var locationName: String {
        switch preference.selection {
        case .currentLocation: return String(localized: "Current Location")
        case .custom(let name, _, _, _): return name
        }
    }
}

/// A titled, horizontally scrolling row of visual choices, such as the theme swatches.
private struct ChoiceRow<Options: View>: View {
    let title: LocalizedStringKey
    let options: Options

    init(_ title: LocalizedStringKey, @ViewBuilder options: () -> Options) {
        self.title = title
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    options
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// Picks the weather location: the current location, or a city found by searching. Picking one
/// goes back to Settings.
private struct LocationSettingsView: View {
    let preference: LocationPreferenceStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    preference.selection = .currentLocation
                    dismiss()
                } label: {
                    locationRow(Label("Current Location", systemImage: "location.fill"), isSelected: preference.selection == .currentLocation)
                }
                .foregroundStyle(.primary)

                if case .custom(let name, _, _, _) = preference.selection {
                    locationRow(Label(name, systemImage: "mappin.and.ellipse"), isSelected: true)
                }
            } footer: {
                Text("Search for a city to see its weather instead of your current location.")
            }

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Weather Location")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("City name"))
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { search() }
    }

    private func locationRow(_ label: some View, isSelected: Bool) -> some View {
        HStack {
            label
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                guard let request = MKGeocodingRequest(addressString: query) else {
                    throw GeocodeError.notFound
                }
                guard let mapItem = try await request.mapItems.first else {
                    throw GeocodeError.notFound
                }
                let location = mapItem.location
                let displayName = mapItem.address?.shortAddress ?? query
                preference.selection = .custom(
                    name: displayName,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timeZone: mapItem.timeZone
                )
                isSearching = false
                dismiss()
            } catch {
                isSearching = false
                errorMessage = String(localized: "Couldn't find that location. Try a different search.")
            }
        }
    }
}

/// Orders the main screen's cards and turns them on or off.
private struct CardSettingsView: View {
    @Bindable var cardPreference: CardPreferenceStore

    var body: some View {
        List {
            Section {
                ForEach($cardPreference.cards) { $config in
                    HStack {
                        Image(systemName: config.type.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(config.type.title)
                        Spacer()
                        Toggle(isOn: $config.isVisible) { Text(config.type.title) }
                            .labelsHidden()
                    }
                }
                .onMove { indices, newOffset in
                    cardPreference.cards.move(fromOffsets: indices, toOffset: newOffset)
                }
            } footer: {
                Text("Drag to reorder. Turn off a card to hide it from the main screen.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum GeocodeError: Error {
    case notFound
}

#Preview {
    SettingsView(
        preference: LocationPreferenceStore(),
        temperaturePreference: TemperaturePreferenceStore(),
        cardPreference: CardPreferenceStore(),
        themePreference: ThemePreferenceStore(),
        providerPreference: WeatherProviderPreferenceStore(),
        planWindowPreference: PlanWindowPreferenceStore()
    )
    .environment(AppIconPreferenceStore())
}
