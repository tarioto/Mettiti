import StoreKit
import UIKit

/// Where the running copy of the app came from.
enum InstallSource {
    case dev
    case testFlight
    case appStore
}

/// The home screen icon that marks the Install Source.
enum BuildIcon {
    case dev
    case beta
    case standard

    /// The alternate icon name, or nil for the primary icon.
    /// Debug builds' primary icon is already the Dev Icon via ASSETCATALOG_COMPILER_APPICON_NAME.
    var alternateIconName: String? {
        switch self {
        case .beta: AppIconPreferenceStore.betaIconName
        case .dev, .standard: nil
        }
    }

    /// Alternate icons can't be loaded as images, so the picker shows exported thumbnails from the asset catalogue.
    var thumbnailName: String {
        switch self {
        case .dev: "IconThumbnail-Dev"
        case .beta: "IconThumbnail-Beta"
        case .standard: "IconThumbnail-Standard"
        }
    }
}

/// An alternate home screen icon matching one Theme. The raw value is the persisted Icon Choice.
enum ThemeIcon: String, CaseIterable, Identifiable {
    case sunset
    case ocean
    case aurora
    case midnight

    var id: String { rawValue }

    var theme: AppTheme {
        switch self {
        case .sunset: .sunset
        case .ocean: .ocean
        case .aurora: .aurora
        case .midnight: .midnight
        }
    }

    var label: String { theme.label }

    var alternateIconName: String { "AppIcon-\(theme.label)" }

    var thumbnailName: String { "IconThumbnail-\(theme.label)" }
}

/// The picker's selection: Default (no Icon Choice, so the Build Icon) or a Theme Icon.
enum AppIconSelection: Hashable {
    case `default`
    case theme(ThemeIcon)
}

/// Decides which home screen icon to show: the Icon Choice if there is one, otherwise the Build Icon for the Install Source.
@MainActor
final class AppIconPreferenceStore: ObservableObject {
    nonisolated static let betaIconName = "AppIcon-Beta"

    @Published private(set) var selection: AppIconSelection
    /// What Default shows. Assumes the primary icon until the Install Source is known.
    @Published private(set) var buildIcon: BuildIcon = AppIconPreferenceStore.primaryBuildIcon

    private let saveIconChoice: (ThemeIcon?) -> Void
    private let supportsAlternateIconsProvider: () -> Bool
    private let installSource: () async -> InstallSource?
    private let currentAlternateIconName: () -> String?
    private let setAlternateIconName: (String?) async -> Void

    init(
        loadIconChoice: () -> ThemeIcon? = AppIconPreferenceStore.loadStoredIconChoice,
        saveIconChoice: @escaping (ThemeIcon?) -> Void = AppIconPreferenceStore.storeIconChoice,
        supportsAlternateIcons: @escaping () -> Bool = { UIApplication.shared.supportsAlternateIcons },
        installSource: @escaping () async -> InstallSource? = AppIconPreferenceStore.verifiedInstallSource,
        currentAlternateIconName: @escaping () -> String? = { UIApplication.shared.alternateIconName },
        setAlternateIconName: @escaping (String?) async -> Void = { try? await UIApplication.shared.setAlternateIconName($0) }
    ) {
        self.saveIconChoice = saveIconChoice
        self.supportsAlternateIconsProvider = supportsAlternateIcons
        self.installSource = installSource
        self.currentAlternateIconName = currentAlternateIconName
        self.setAlternateIconName = setAlternateIconName
        selection = loadIconChoice().map(AppIconSelection.theme) ?? .default
    }

    var supportsAlternateIcons: Bool { supportsAlternateIconsProvider() }

    /// Shows the Icon Choice or the Build Icon, leaving the icon alone when there's no choice and the Install Source is unknown.
    func applyAtLaunch() async {
        guard supportsAlternateIcons else { return }
        let source = await resolveInstallSource()
        switch selection {
        case .theme(let icon):
            await show(icon.alternateIconName)
        case .default:
            guard let source else { return }
            await show(Self.buildIcon(for: source).alternateIconName)
        }
    }

    /// Picking a Theme Icon saves it as the Icon Choice; picking Default clears it so the Build Icon shows.
    func select(_ newSelection: AppIconSelection) async {
        selection = newSelection
        let source = await resolveInstallSource()
        switch newSelection {
        case .theme(let icon):
            saveIconChoice(icon)
            await show(icon.alternateIconName)
        case .default:
            saveIconChoice(nil)
            // A Theme Icon mustn't stay after picking Default, so an unknown Install Source falls back to the primary icon.
            await show(source.flatMap { Self.buildIcon(for: $0).alternateIconName })
        }
    }

    private func resolveInstallSource() async -> InstallSource? {
        let source = await installSource()
        if let source { buildIcon = Self.buildIcon(for: source) }
        return source
    }

    private func show(_ alternateIconName: String?) async {
        guard currentAlternateIconName() != alternateIconName else { return }
        await setAlternateIconName(alternateIconName)
    }

    private static func buildIcon(for source: InstallSource) -> BuildIcon {
        switch source {
        case .testFlight: .beta
        case .appStore, .dev: primaryBuildIcon
        }
    }

    /// The Build Icon compiled in as the primary icon for this configuration.
    private static var primaryBuildIcon: BuildIcon {
        #if DEBUG
        .dev
        #else
        .standard
        #endif
    }

    nonisolated private static let iconChoiceKey = "appIconChoice"

    /// Default Icon Choice loader. The widgets don't use it, so it lives in standard defaults rather than the App Group.
    nonisolated static func loadStoredIconChoice() -> ThemeIcon? {
        UserDefaults.standard.string(forKey: iconChoiceKey).flatMap(ThemeIcon.init(rawValue:))
    }

    nonisolated static func storeIconChoice(_ choice: ThemeIcon?) {
        UserDefaults.standard.set(choice?.rawValue, forKey: iconChoiceKey)
    }

    /// Default Install Source: the verified App Transaction's environment, or nil when it can't be verified.
    nonisolated static func verifiedInstallSource() async -> InstallSource? {
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return nil }
        switch transaction.environment {
        case .xcode: return .dev
        case .sandbox: return .testFlight
        case .production: return .appStore
        default: return nil
        }
    }
}
