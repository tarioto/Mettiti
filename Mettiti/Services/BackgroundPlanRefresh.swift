import BackgroundTasks
import CoreLocation
import OSLog

/// Wires `BackgroundPlanRefresher` to BackgroundTasks so the widgets get today's plan
/// without the app being opened. Scheduling is best effort: iOS decides when (and whether) it runs.
@MainActor
enum BackgroundPlanRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    static let taskIdentifier = "com.timarioto.Mettiti.planRefresh"

    private static let logger = Logger(subsystem: "com.timarioto.Mettiti", category: "BackgroundPlanRefresh")

    /// Runs one background refresh, then asks for the next one.
    static func run() async {
        let refresher = makeRefresher()
        let outcome = await refresher.refreshIfStale()
        logger.info("Background plan refresh finished: \(String(describing: outcome), privacy: .public)")
        schedule(using: refresher)
    }

    /// Submits (or replaces) the pending refresh request. Synchronous, so it's submitted
    /// before the app is suspended when called on the `.background` scene-phase change.
    static func schedule() {
        schedule(using: makeRefresher())
    }

    private static func schedule(using refresher: BackgroundPlanRefresher) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = refresher.nextRequestDate(availability: DayPlanFetcher.currentAvailability())
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected on the Simulator and when Background App Refresh is off.
            logger.error("Couldn't schedule background plan refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makeRefresher() -> BackgroundPlanRefresher {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return BackgroundPlanRefresher(
            fetcher: DayPlanFetcher(),
            calendar: calendar,
            now: { .now },
            loadSnapshot: { SharedStore.load() },
            publish: { DayPlanViewModel.saveAndReloadWidgets($0) },
            selection: { LocationPreferenceStore().selection },
            lastKnownGPSCoordinate: { lastKnownGPSCoordinate() },
            provider: { WeatherProviderPreferenceStore().provider }
        )
    }

    /// The system's cached fix, if the user already granted location access. A background
    /// `requestLocation()` isn't reliable with When In Use access, and we don't ask for more.
    private static func lastKnownGPSCoordinate() -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return manager.location?.coordinate
        default:
            return nil
        }
    }
}
