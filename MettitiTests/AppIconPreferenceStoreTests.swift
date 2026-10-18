import Testing
@testable import Mettiti

@MainActor
struct AppIconPreferenceStoreTests {
    private func makeStore(
        iconChoice: ThemeIcon? = nil,
        onSave: @escaping (ThemeIcon?) -> Void = { _ in },
        installSource: InstallSource?,
        currentIcon: String?,
        onSet: @escaping (String?) -> Void
    ) -> AppIconPreferenceStore {
        AppIconPreferenceStore(
            loadIconChoice: { iconChoice },
            saveIconChoice: onSave,
            supportsAlternateIcons: { true },
            installSource: { installSource },
            currentAlternateIconName: { currentIcon },
            setAlternateIconName: { onSet($0) }
        )
    }

    @Test func testFlightLaunchSetsTheBetaIconWhenThePrimaryIconIsShowing() async {
        var setIcons: [String?] = []
        let store = makeStore(installSource: .testFlight, currentIcon: nil) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons == [AppIconPreferenceStore.betaIconName])
    }

    @Test func appStoreLaunchResetsToThePrimaryIconWhenTheBetaIconIsShowing() async {
        var setIcons: [String?] = []
        let store = makeStore(installSource: .appStore, currentIcon: AppIconPreferenceStore.betaIconName) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons == [nil])
    }

    @Test func devLaunchResetsToThePrimaryIconWhenTheBetaIconIsShowing() async {
        var setIcons: [String?] = []
        let store = makeStore(installSource: .dev, currentIcon: AppIconPreferenceStore.betaIconName) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons == [nil])
    }

    @Test func launchWhereTheDesiredIconIsAlreadyShowingSetsNothing() async {
        var setIcons: [String?] = []
        let store = makeStore(installSource: .testFlight, currentIcon: AppIconPreferenceStore.betaIconName) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons.isEmpty)
    }

    @Test func launchWithAnUnknownInstallSourceSetsNothing() async {
        var setIcons: [String?] = []
        let store = makeStore(installSource: nil, currentIcon: AppIconPreferenceStore.betaIconName) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons.isEmpty)
    }

    @Test func launchWithoutAlternateIconSupportAttemptsNothing() async {
        var setIcons: [String?] = []
        var askedForInstallSource = false
        let store = AppIconPreferenceStore(
            loadIconChoice: { nil },
            saveIconChoice: { _ in },
            supportsAlternateIcons: { false },
            installSource: { askedForInstallSource = true; return .testFlight },
            currentAlternateIconName: { nil },
            setAlternateIconName: { setIcons.append($0) }
        )

        await store.applyAtLaunch()

        #expect(setIcons.isEmpty)
        #expect(!askedForInstallSource)
    }

    @Test func testFlightLaunchWithAnIconChoiceSetsThatThemeIcon() async {
        var setIcons: [String?] = []
        let store = makeStore(iconChoice: .ocean, installSource: .testFlight, currentIcon: AppIconPreferenceStore.betaIconName) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons == [ThemeIcon.ocean.alternateIconName])
    }

    @Test func launchWithAnIconChoiceAlreadyShowingSetsNothing() async {
        var setIcons: [String?] = []
        let store = makeStore(iconChoice: .ocean, installSource: .testFlight, currentIcon: ThemeIcon.ocean.alternateIconName) { setIcons.append($0) }

        await store.applyAtLaunch()

        #expect(setIcons.isEmpty)
    }

    @Test func selectingAThemeIconSavesAndSetsIt() async {
        var savedChoices: [ThemeIcon?] = []
        var setIcons: [String?] = []
        let store = makeStore(onSave: { savedChoices.append($0) }, installSource: .appStore, currentIcon: nil) { setIcons.append($0) }

        await store.select(.theme(.ocean))

        #expect(savedChoices == [.ocean])
        #expect(setIcons == [ThemeIcon.ocean.alternateIconName])
        #expect(store.selection == .theme(.ocean))
    }

    @Test func selectingDefaultClearsTheChoiceAndSetsTheBuildIcon() async {
        var savedChoices: [ThemeIcon?] = []
        var setIcons: [String?] = []
        let store = makeStore(
            iconChoice: .ocean,
            onSave: { savedChoices.append($0) },
            installSource: .testFlight,
            currentIcon: ThemeIcon.ocean.alternateIconName
        ) { setIcons.append($0) }

        await store.select(.default)

        #expect(savedChoices == [nil])
        #expect(setIcons == [AppIconPreferenceStore.betaIconName])
        #expect(store.selection == .default)
    }

    @Test func selectingDefaultWithAnUnknownInstallSourceResetsToThePrimaryIcon() async {
        var setIcons: [String?] = []
        let store = makeStore(iconChoice: .ocean, installSource: nil, currentIcon: ThemeIcon.ocean.alternateIconName) { setIcons.append($0) }

        await store.select(.default)

        #expect(setIcons == [nil])
    }

    @Test func aLoadedIconChoiceIsTheSelectionWithoutSavingOrSettingAnything() {
        var savedChoices: [ThemeIcon?] = []
        var setIcons: [String?] = []
        let store = makeStore(iconChoice: .ocean, onSave: { savedChoices.append($0) }, installSource: .appStore, currentIcon: nil) { setIcons.append($0) }

        #expect(store.selection == .theme(.ocean))
        #expect(savedChoices.isEmpty)
        #expect(setIcons.isEmpty)
    }

    @Test func noLoadedIconChoiceSelectsDefault() {
        let store = makeStore(installSource: .appStore, currentIcon: nil) { _ in }

        #expect(store.selection == .default)
    }

    @Test func testFlightLaunchShowsTheBetaIconAsTheBuildIcon() async {
        let store = makeStore(iconChoice: .ocean, installSource: .testFlight, currentIcon: nil) { _ in }

        await store.applyAtLaunch()

        #expect(store.buildIcon == .beta)
    }

    /// Asset names must stay fixed even when the Theme's display label is translated.
    @Test func themeIconAssetNamesMatchTheAssetCatalogue() {
        #expect(ThemeIcon.allCases.map(\.alternateIconName) == ["AppIcon-Sunset", "AppIcon-Ocean", "AppIcon-Aurora", "AppIcon-Midnight"])
        #expect(ThemeIcon.allCases.map(\.thumbnailName) == ["IconThumbnail-Sunset", "IconThumbnail-Ocean", "IconThumbnail-Aurora", "IconThumbnail-Midnight"])
    }

    @Test func eachThemeExceptDefaultHasOneThemeIconInThemeOrder() {
        #expect(ThemeIcon.allCases.map(\.theme) == AppTheme.allCases.filter { $0 != .none })
    }
}
