import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXTypedAPITests {

    // MARK: - Waypoint properties via typed API

    @Test
    func typedAPIWaypointProperties() async throws {
        let url = try #require(TestData.url(name: "waypoints.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        let wp = fc.features[0]
        #expect(wp.gpxType == .waypoint)
        #expect(wp.gpxName == "Reichstag (Berlin)")
        #expect(wp.gpxSymbol == "City")
        #expect(wp.gpxFix == .threeDimensional)
        #expect(wp.gpxSatellites == 12)
        #expect(wp.gpxHDOP == 1.5)
    }

    @Test
    func typedAPIRouteProperties() async throws {
        let url = try #require(TestData.url(name: "routes.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        let route = fc.features.first!
        #expect(route.gpxType == .route)
        #expect(route.gpxName == "Berlin City Walk")
        #expect(route.gpxTypeName == "Walking")
    }

    @Test
    func typedAPITrackProperties() async throws {
        let url = try #require(TestData.url(name: "tracks.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        let track = fc.features.first!
        #expect(track.gpxType == .track)
        #expect(track.gpxName == "Morning Run")
        #expect(track.gpxTypeName == "Running")
    }

    // MARK: - Metadata via typed API

    @Test
    func typedAPIMetadata() async throws {
        let url = try #require(TestData.url(name: "metadata.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        #expect(fc.gpxMetadataName == "Test GPX File")
        #expect(fc.gpxMetadataDescription == "A GPX file with full metadata for testing")
        #expect(fc.gpxMetadataKeywords == "test, fixture, metadata")

        let author = fc.gpxMetadataAuthor
        #expect(author?.name == "Test Author")
        #expect(author?.email == "test@example.com")

        let cr = fc.gpxMetadataCopyright
        #expect(cr?.year == 2024)
        #expect(cr?.license == "ODbL")
    }

    // MARK: - gpxx extensions via typed API

    @Test
    func typedAPIGpxxExtensions() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        let wp = fc.features.filter { $0.gpxType == .waypoint }.first!
        let address = wp.gpxAddress
        #expect(address?.city == "Berlin")
        #expect(address?.country == "Germany")
        #expect(address?.streetAddresses.count == 2)

        let phoneNumbers = wp.gpxPhoneNumbers
        #expect(phoneNumbers.count == 2)
        #expect(phoneNumbers[0].value == "+49-30-555-1234")
        #expect(phoneNumbers[0].category == "Work")
        #expect(phoneNumbers[1].value == "+49-170-555-5678")
        #expect(phoneNumbers[1].category == "Mobile")

        let categories = wp.gpxCategories
        #expect(categories.contains("Office"))
        #expect(categories.contains("Technology"))
        #expect(categories.contains("Outdoor"))
    }

    @Test
    func typedAPIGpxtpxExtensions() async throws {
        let url = try #require(TestData.url(name: "extensions_gpxtpx.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        let track = fc.features.filter { $0.gpxType == .track }.first!
        #expect(track.gpxHeartRate == nil)
        #expect(track.gpxPower == nil)
    }

    // MARK: - Typed setter round-trips

    @Test
    func typedAPISetters() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typed_setters_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var pointFeature = Feature(Point(Coordinate3D(latitude: 50.0, longitude: 8.0)))
        pointFeature.gpxType = .waypoint
        pointFeature.gpxName = "Custom Point"
        pointFeature.gpxSymbol = "Flag"
        pointFeature.gpxHeartRate = 130
        pointFeature.gpxPower = 200
        pointFeature.gpxSpeed = 10.5

        let fc = FeatureCollection([pointFeature])
        try fc.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let wp = reloaded.features.first!
        #expect(wp.gpxType == .waypoint)
        #expect(wp.gpxName == "Custom Point")
        #expect(wp.gpxSymbol == "Flag")
        #expect(wp.gpxHeartRate == 130)
        #expect(wp.gpxPower == 200)
        #expect(wp.gpxSpeed == 10.5)
    }

    @Test
    func typedAPIMetadataSetters() async throws {
        var fc = FeatureCollection()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typed_meta_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        fc.gpxMetadataName = "Test File"
        fc.gpxMetadataKeywords = "test, typed"
        fc.gpxMetadataAuthor = GPXPerson(name: "Test Author", email: "test@example.com")
        fc.gpxMetadataCopyright = GPXCopyright(author: "Test Co", year: 2024, license: "MIT")
        fc.gpxMetadataBounds = BoundingBox(
            southWest: Coordinate3D(latitude: 40.0, longitude: 10.0),
            northEast: Coordinate3D(latitude: 50.0, longitude: 20.0))

        try fc.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        #expect(reloaded.gpxMetadataName == "Test File")
        #expect(reloaded.gpxMetadataKeywords == "test, typed")
        #expect(reloaded.gpxMetadataAuthor?.name == "Test Author")
        #expect(reloaded.gpxMetadataCopyright?.year == 2024)
        #expect(reloaded.gpxMetadataBounds?.southWest.latitude == 40.0)
    }

    @Test
    func typedAPIAddressSetter() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typed_addr_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var pointFeature = Feature(Point(Coordinate3D(latitude: 50.0, longitude: 8.0)))
        pointFeature.gpxType = .waypoint
        pointFeature.gpxName = "Office"
        pointFeature.gpxAddress = GPXAddress(
            streetAddresses: ["123 Main St"],
            city: "Berlin",
            country: "Germany",
            postalCode: "10115")

        let fc = FeatureCollection([pointFeature])
        try fc.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let wp = reloaded.features.first!
        #expect(wp.gpxName == "Office")
        let addr = wp.gpxAddress
        #expect(addr?.city == "Berlin")
        #expect(addr?.country == "Germany")
        #expect(addr?.postalCode == "10115")
        #expect(addr?.streetAddresses.first == "123 Main St")
    }

    // MARK: - GPX 1.0 via typed API

    @Test
    func typedAPIGPX10() async throws {
        let url = try #require(TestData.url(name: "gpx10.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        let track = fc.features.filter { $0.gpxType == .track }.first!
        #expect(track.gpxCourse10 == nil)

        let waypoint = fc.features.filter { $0.gpxType == .waypoint }.first!
        #expect(waypoint.gpxLinks.isEmpty == false)
        #expect(waypoint.gpxLinks[0].href == "https://www.bundestag.de")
        #expect(waypoint.gpxLinks[0].text == "Bundestag website")
    }

}
