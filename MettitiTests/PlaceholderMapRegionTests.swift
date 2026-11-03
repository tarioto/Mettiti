import CoreLocation
import MapKit
import Testing
@testable import Mettiti

struct PlaceholderMapRegionTests {
    private let fix = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
    private let saved = LocationSelection.custom(name: "Paris", latitude: 48.85, longitude: 2.35)
    private let country = MKCoordinateRegion(center: .init(latitude: 46, longitude: 2), latitudinalMeters: 1_000_000, longitudinalMeters: 1_000_000)

    @Test func lastFixWinsAtCityScale() async {
        let country = country
        let region = await PlaceholderMapRegion.resolve(lastFix: fix, savedPlan: saved, countryCode: "FR") { _ in country }
        #expect(region?.center.latitude == 51.5)
        #expect(region?.span.latitudeDelta == PlaceholderMapRegion.cityScale(around: fix).span.latitudeDelta)
    }

    @Test func savedPlanCityIsNextAtTheSameScale() async {
        let country = country
        let region = await PlaceholderMapRegion.resolve(lastFix: nil, savedPlan: saved, countryCode: "FR") { _ in country }
        #expect(region?.center.latitude == 48.85)
        #expect(region?.center.longitude == 2.35)
    }

    @Test func savedCurrentLocationHasNoCoordinateSoCountryIsUsed() async {
        let country = country
        let region = await PlaceholderMapRegion.resolve(lastFix: nil, savedPlan: .currentLocation, countryCode: "FR") { _ in country }
        #expect(region?.center.latitude == 46)
    }

    @Test func countryIsLast() async {
        let country = country
        let region = await PlaceholderMapRegion.resolve(lastFix: nil, savedPlan: nil, countryCode: "FR") { code in
            code == "FR" ? country : nil
        }
        #expect(region?.center.longitude == 2)
    }

    @Test func nothingKnownGivesNoRegion() async {
        let country = country
        let region = await PlaceholderMapRegion.resolve(lastFix: nil, savedPlan: nil, countryCode: nil) { _ in country }
        #expect(region == nil)
    }
}

@MainActor
struct PlaceholderMapRegionCacheTests {
    private let region = MKCoordinateRegion(center: .init(latitude: 51.5, longitude: -0.1), latitudinalMeters: 50_000, longitudinalMeters: 50_000)

    @Test func aSecondCardGetsTheRegionWithoutASecondLookup() async {
        var lookups = 0
        let region = region
        let cache = PlaceholderMapRegionCache {
            lookups += 1
            return region
        }

        #expect(cache.region == nil)
        await cache.load()
        #expect(cache.region?.center.latitude == 51.5)

        // A new Location card after the crossfade reads the cache: it already has the region.
        #expect(cache.region?.center.latitude == 51.5)
        await cache.load()
        #expect(lookups == 1)
    }

    @Test func cardsLoadingAtOnceShareOneLookup() async {
        var lookups = 0
        let region = region
        let cache = PlaceholderMapRegionCache {
            lookups += 1
            await Task.yield()
            return region
        }

        async let first: Void = cache.load()
        async let second: Void = cache.load()
        _ = await (first, second)

        #expect(lookups == 1)
        #expect(cache.region?.center.longitude == -0.1)
    }

    @Test func nothingKnownIsNotLookedUpAgain() async {
        var lookups = 0
        let cache = PlaceholderMapRegionCache {
            lookups += 1
            return nil
        }

        await cache.load()
        await cache.load()

        #expect(cache.region == nil)
        #expect(lookups == 1)
    }
}
