import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXExtensionTests {

    // MARK: - Core GPX extensions

    @Test
    func readTrackPointExtensions() async throws {
        let url = try #require(TestData.url(name: "extensions_gpxtpx.gpx"))
        let fc = try GPXCoder.read(from: url)

        let tracks = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "trk"
        }
        #expect(tracks.count == 1)

        let track = tracks[0]
        #expect(track.properties["name"] as? String == "Cycling Workout")
        #expect(track.gpxHeartRates == [120, 145, 160])
        #expect(track.gpxCadences == [85, 90, 95])
        #expect(track.gpxSpeeds == [nil, nil, 12.5])
        #expect(track.gpxAirTemperatures == [nil, 18.5, nil])

        let extensions = track.properties["extensions"] as? [String: Sendable]
        #expect(extensions == nil || extensions?.isEmpty == true,
                "Extensions should be on track points, not on the track")
    }

    @Test
    func readGpxxExtensions() async throws {
        let url = try #require(TestData.url(name: "extensions_gpxx.gpx"))
        let fc = try GPXCoder.read(from: url)

        let route = try #require(fc.gpxRoutes.first)
        #expect(route.gpxName == "Scenic Route")
        #expect(route.gpxIsAutoNamed == true)
        #expect(route.gpxDisplayColor == "Red")

        let waypoint = try #require(fc.gpxWaypoints.first)
        #expect(waypoint.gpxName == "Trailhead")
        #expect(waypoint.gpxDisplayMode == "SymbolAndName")

        let extensions = waypoint.properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]
        #expect(gpxx?["Temperature"] as? Double == 22.5)
    }

    // MARK: - Structured gpxx extensions

    @Test
    func readStructuredAddressExtension() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let waypoints = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        #expect(waypoints.count == 1)

        let extensions = waypoints[0].properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]
        #expect(gpxx != nil)

        let address = gpxx?["Address"] as? [String: Sendable]
        #expect(address?["City"] as? String == "Berlin")
        #expect(address?["Country"] as? String == "Germany")
        #expect(address?["PostalCode"] as? String == "10115")
        #expect(address?["State"] as? String == "Berlin")

        let streets = address?["StreetAddress"] as? [String]
        #expect(streets?.count == 2)
        #expect(streets?[0] == "123 Alpinestrasse")
        #expect(streets?[1] == "Floor 4")
    }

    @Test
    func readStructuredCategoriesExtension() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let waypoints = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        let extensions = waypoints[0].properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]

        let categories = gpxx?["Categories"] as? [String]
        #expect(categories != nil)
        #expect(categories?.contains("Office") == true)
        #expect(categories?.contains("Technology") == true)
        #expect(categories?.contains("Outdoor") == true)
    }

    @Test
    func readStructuredPhoneNumberExtension() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let waypoints = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        let extensions = waypoints[0].properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]

        let phoneNumbers = gpxx?["PhoneNumber"] as? [Sendable]
        #expect(phoneNumbers?.count == 2)

        let first = phoneNumbers?[0] as? [String: Sendable]
        #expect(first?["value"] as? String == "+49-30-555-1234")
        #expect(first?["category"] as? String == "Work")
    }

    @Test
    func readStructuredRptExtension() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let route = try #require(fc.gpxRoutes.first)
        let secondPointExtensions = try #require(
            route.gpxRouteExtensions?[1] ?? nil)
        let gpxx = try #require(secondPointExtensions["gpxx"])
        let points = try #require(gpxx["rpt"] as? [Sendable])
        #expect(points.count == 2)
        let first = try #require(points[0] as? [String: Double])
        #expect(first["lat"] == 52.519)
        #expect(first["lon"] == 13.378)
    }

    // MARK: - Type inference

    @Test
    func extensionTypeInference() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let tracks = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "trk"
        }
        let track = tracks[0]
        let extensions = track.properties["extensions"] as? [String: Sendable]
        #expect(extensions == nil || extensions?.isEmpty == true,
                "track-level extensions should be empty; gpxtpx data is on track points")
    }

    @Test
    func booleanExtensionTypeInference() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let routes = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "rte"
        }
        let extensions = routes[0].properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]

        let isAutoNamed = gpxx?["IsAutoNamed"]
        #expect(isAutoNamed is Bool)
        #expect(isAutoNamed as? Bool == true)

        let displayColor = gpxx?["DisplayColor"]
        #expect(displayColor as? String == "Blue")
    }

    // MARK: - Power meter

    @Test
    func readPowerMeterExtension() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)

        let track = try #require(fc.gpxTracks.first)
        #expect(track.gpxPowers == [150, 220])
        #expect(track.gpxHeartRates == [120, 145])
        let extensions = track.properties["extensions"] as? [String: Sendable]
        let gpxtpx = extensions?["gpxtpx"] as? [String: Sendable]
        #expect(gpxtpx == nil, "gpxtpx should not be on track-level extensions")
    }

}
