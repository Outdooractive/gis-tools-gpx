import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXAPIConsistencyTests {

    // MARK: - Coder API

    @Test
    func writeAPIMatchesConvenienceAPI() throws {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.gpxName = "API"
        let fc = FeatureCollection([waypoint])

        let data = try GPXCoder.write(fc)
        #expect(try fc.gpxData() == data)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("api_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: url) }

        try GPXCoder.write(fc, to: url)
        let reloaded = try #require(FeatureCollection(gpx: url))
        #expect(reloaded.gpxWaypoints.first?.gpxName == "API")
    }

    @Test
    func parserStringEntryPointIsEquivalent() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
              <wpt lat="52.5" lon="13.4"><name>String</name></wpt>
            </gpx>
            """

        let file = try GPXParser.parse(string: xml)
        #expect(file.waypoints.count == 1)
        #expect(file.waypoints.first?.name == "String")

        let dataFile = try GPXParser.parse(data: Data(xml.utf8))
        #expect(dataFile.waypoints.count == 1)
    }

    // MARK: - Waypoint properties

    @Test
    func waypointSettersRoundTripAllScalarFields() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        feature.gpxType = .waypoint
        feature.gpxName = "All fields"
        feature.gpxComment = "comment"
        feature.gpxDescription = "description"
        feature.gpxSource = "source"
        feature.gpxSymbol = "Flag"
        feature.gpxTypeName = "type"
        feature.gpxFix = .dgps
        feature.gpxSatellites = 9
        feature.gpxHDOP = 1.1
        feature.gpxVDOP = 1.2
        feature.gpxPDOP = 1.3
        feature.gpxMagneticVariation = 2.5
        feature.gpxGeoidHeight = 47.0
        feature.gpxAgeOfDGPSData = 0.5
        feature.gpxDGPSID = 42
        feature.gpxCourse10 = 90.0
        feature.gpxSpeed10 = 3.5
        feature.gpxElevation = 123.0
        feature.gpxLinks = [
            GPXLink(href: "https://example.com", text: "Example", type: "text/html"),
        ]

        let reloaded = try GPXCoder.read(from: try GPXCoder.write(
            FeatureCollection([feature])))
        let waypoint = try #require(reloaded.gpxWaypoints.first)

        #expect(waypoint.gpxName == "All fields")
        #expect(waypoint.gpxComment == "comment")
        #expect(waypoint.gpxDescription == "description")
        #expect(waypoint.gpxSource == "source")
        #expect(waypoint.gpxSymbol == "Flag")
        #expect(waypoint.gpxTypeName == "type")
        #expect(waypoint.gpxFix == .dgps)
        #expect(waypoint.gpxSatellites == 9)
        #expect(waypoint.gpxHDOP == 1.1)
        #expect(waypoint.gpxVDOP == 1.2)
        #expect(waypoint.gpxPDOP == 1.3)
        #expect(waypoint.gpxMagneticVariation == 2.5)
        #expect(waypoint.gpxGeoidHeight == 47.0)
        #expect(waypoint.gpxAgeOfDGPSData == 0.5)
        #expect(waypoint.gpxDGPSID == 42)
        #expect(waypoint.gpxCourse == 90.0)
        #expect(waypoint.gpxSpeed == 3.5)
        #expect(waypoint.gpxElevation == 123.0)
        #expect(waypoint.gpxLinks.first?.type == "text/html")
    }

    @Test
    func gpxElevationUpdatesGeometryAndCanBeCleared() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        #expect(feature.gpxElevation == nil)

        feature.gpxElevation = 42.0
        #expect(feature.gpxElevation == 42.0)
        let point = try #require(feature.geometry as? Point)
        #expect(point.coordinate.altitude == 42.0)

        feature.gpxElevation = nil
        #expect(feature.gpxElevation == nil)
    }

    @Test
    func gpxLinksSupportSingleDictionaryStorage() throws {
        let feature = Feature(
            Point(Coordinate3D(latitude: 52.5, longitude: 13.4)),
            properties: ["link": ["href": "https://single.example", "text": "Single"] as [String: String]])
        #expect(feature.gpxLinks.map(\.href) == ["https://single.example"])
        #expect(feature.gpxLinks.first?.text == "Single")

        var cleared = feature
        cleared.gpxLinks = []
        #expect(cleared.gpxLinks.isEmpty)
        #expect(cleared.properties["link"] == nil)
    }

    // MARK: - gpxtpx setters

    @Test
    func gpxtpxSettersAndDeletion() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        feature.gpxHeartRate = 140
        feature.gpxCadence = 88
        feature.gpxPower = 210
        feature.gpxSpeed = 11.5
        feature.gpxCourse = 180.0
        feature.gpxBearing = 179.0
        feature.gpxAirTemperature = 19.0
        feature.gpxWaterTemperature = 16.0
        feature.gpxDepth = 2.5

        #expect(feature.gpxHeartRate == 140)
        #expect(feature.gpxCadence == 88)
        #expect(feature.gpxPower == 210)
        #expect(feature.gpxSpeed == 11.5)
        #expect(feature.gpxCourse == 180.0)
        #expect(feature.gpxBearing == 179.0)
        #expect(feature.gpxAirTemperature == 19.0)
        #expect(feature.gpxWaterTemperature == 16.0)
        #expect(feature.gpxDepth == 2.5)

        feature.gpxHeartRate = nil
        #expect(feature.gpxHeartRate == nil)
        #expect(feature.gpxCadence == 88)

        feature.gpxCadence = nil
        feature.gpxPower = nil
        feature.gpxSpeed = nil
        feature.gpxCourse = nil
        feature.gpxBearing = nil
        feature.gpxAirTemperature = nil
        feature.gpxWaterTemperature = nil
        feature.gpxDepth = nil
        #expect(feature.properties["extensions"] == nil)
    }

    // MARK: - gpxx setters

    @Test
    func gpxxSettersAndDeletion() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        feature.gpxProximity = 10.0
        feature.gpxDisplayMode = "SymbolAndName"
        feature.gpxDisplayColor = "Cyan"
        feature.gpxIsAutoNamed = true
        feature.gpxCategories = ["A", "B"]
        feature.gpxPhoneNumbers = [
            GPXPhoneNumber(value: "123", category: "Home"),
        ]
        feature.gpxAddress = GPXAddress(
            streetAddresses: ["Street 1"],
            city: "Berlin",
            state: "Berlin",
            country: "Germany",
            postalCode: "10115")

        #expect(feature.gpxProximity == 10.0)
        #expect(feature.gpxDisplayMode == "SymbolAndName")
        #expect(feature.gpxDisplayColor == "Cyan")
        #expect(feature.gpxIsAutoNamed == true)
        #expect(feature.gpxCategories == ["A", "B"])
        #expect(feature.gpxPhoneNumbers == [GPXPhoneNumber(value: "123", category: "Home")])
        #expect(feature.gpxAddress?.postalCode == "10115")

        feature.gpxProximity = nil
        feature.gpxDisplayMode = nil
        feature.gpxDisplayColor = nil
        feature.gpxIsAutoNamed = nil
        feature.gpxCategories = []
        feature.gpxPhoneNumbers = []
        feature.gpxAddress = nil
        #expect(feature.properties["extensions"] == nil)
    }

    @Test
    func gpxxAccessorsHandleLegacyShapes() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        feature.properties["extensions"] = [
            "gpxx": [
                "Categories": "Single",
                "PhoneNumber": ["plain"] as [Sendable],
                "IsAutoNamed": "false",
                "Address": ["StreetAddress": "One street"] as [String: Sendable],
            ] as [String: Sendable],
        ] as [String: Sendable]

        #expect(feature.gpxCategories == ["Single"])
        #expect(feature.gpxPhoneNumbers == [GPXPhoneNumber(value: "plain")])
        #expect(feature.gpxIsAutoNamed == false)
        #expect(feature.gpxAddress?.streetAddresses == ["One street"])
    }

    // MARK: - Per-point array setters

    @Test
    func trackArraySettersRoundTrip() throws {
        var feature = Feature(MultiLineString(unchecked: [
            LineString(unchecked: [
                Coordinate3D(latitude: 52.5, longitude: 13.4),
                Coordinate3D(latitude: 52.6, longitude: 13.5),
            ]),
        ]))
        feature.gpxType = .track
        let base = Date(timeIntervalSince1970: 1_700_000_000.0)
        feature.gpxTimes = [base, nil]
        feature.gpxHeartRates = [100, nil]
        feature.gpxCadences = [80, nil]
        feature.gpxPowers = [200, nil]
        feature.gpxSpeeds = [10.0, nil]
        feature.gpxCourses = [45.0, nil]
        feature.gpxAirTemperatures = [18.0, nil]
        feature.gpxWaterTemperatures = [15.0, nil]
        feature.gpxDepths = [2.0, nil]
        feature.gpxBearings = [90.0, nil]
        feature.gpxElevations = [100.0, 101.0]
        feature.gpxTrackNames = ["First", nil]
        feature.gpxTrackComments = ["Comment", nil]
        feature.gpxTrackDescriptions = ["Description", nil]
        feature.gpxTrackSources = ["Source", nil]
        feature.gpxTrackSymbols = ["Flag", nil]
        feature.gpxTrackTypes = ["Type", nil]
        feature.gpxTrackLinks = [
            [GPXLink(href: "https://point.example", text: "Point")],
            nil,
        ]
        feature.gpxTrackPointExtensions = [
            ["gpxx": ["VendorField": "kept"]],
            nil,
        ]

        #expect(feature.gpxTimes == [base, nil])
        #expect(feature.gpxHeartRates == [100, nil])
        #expect(feature.gpxCadences == [80, nil])
        #expect(feature.gpxPowers == [200, nil])
        #expect(feature.gpxSpeeds == [10.0, nil])
        #expect(feature.gpxCourses == [45.0, nil])
        #expect(feature.gpxAirTemperatures == [18.0, nil])
        #expect(feature.gpxWaterTemperatures == [15.0, nil])
        #expect(feature.gpxDepths == [2.0, nil])
        #expect(feature.gpxBearings == [90.0, nil])
        #expect(feature.gpxElevations == [100.0, 101.0])
        #expect(feature.gpxTrackNames == ["First", nil])
        #expect(feature.gpxTrackComments == ["Comment", nil])
        #expect(feature.gpxTrackDescriptions == ["Description", nil])
        #expect(feature.gpxTrackSources == ["Source", nil])
        #expect(feature.gpxTrackSymbols == ["Flag", nil])
        #expect(feature.gpxTrackTypes == ["Type", nil])
        #expect(feature.gpxTrackLinks?[0]?.first?.href == "https://point.example")
        let trackVendor = feature.gpxTrackPointExtensions?[0]?["gpxx"]?["VendorField"]
        #expect(trackVendor as? String == "kept")

        let points = feature.gpxPointFeatures()
        #expect(points.features[1].gpxTime == nil)
        #expect(points.features[1].gpxHeartRate == nil)
        #expect(points.features[1].gpxName == nil)
        #expect(points.features[1].gpxLinks.isEmpty)

        let reloaded = try GPXCoder.read(from: try GPXCoder.write(
            FeatureCollection([feature])))
        let track = try #require(reloaded.gpxTracks.first)
        #expect(track.gpxTimes == [base, nil])
        #expect(track.gpxHeartRates == [100, nil])
        #expect(track.gpxWaterTemperatures == [15.0, nil])
        #expect(track.gpxTrackNames == ["First", nil])
        #expect(track.gpxTrackLinks?[0]?.first?.href == "https://point.example")
        let vendor = track.gpxTrackPointExtensions?[0]?["gpxx"]?["VendorField"]
        #expect(vendor as? String == "kept")
    }

    @Test
    func routeArraySettersRoundTrip() throws {
        var feature = Feature(LineString(unchecked: [
            Coordinate3D(latitude: 52.5, longitude: 13.4),
            Coordinate3D(latitude: 52.6, longitude: 13.5),
        ]))
        feature.gpxType = .route
        let base = Date(timeIntervalSince1970: 1_700_000_000.0)
        feature.gpxRouteTimes = [base, nil]
        feature.gpxRouteNames = ["First", nil]
        feature.gpxRouteComments = ["Comment", nil]
        feature.gpxRouteDescriptions = ["Description", nil]
        feature.gpxRouteSources = ["Source", nil]
        feature.gpxRouteSymbols = ["Flag", nil]
        feature.gpxRouteTypes = ["Type", nil]
        feature.gpxRouteLinks = [
            [GPXLink(href: "https://rtept.example", text: "Point")],
            nil,
        ]
        feature.gpxRouteExtensions = [
            ["gpxx": ["VendorField": "kept"]],
            nil,
        ]

        #expect(feature.gpxRouteTimes == [base, nil])
        #expect(feature.gpxRouteNames == ["First", nil])
        #expect(feature.gpxRouteComments == ["Comment", nil])
        #expect(feature.gpxRouteDescriptions == ["Description", nil])
        #expect(feature.gpxRouteSources == ["Source", nil])
        #expect(feature.gpxRouteSymbols == ["Flag", nil])
        #expect(feature.gpxRouteTypes == ["Type", nil])
        #expect(feature.gpxRouteLinks?[0]?.first?.href == "https://rtept.example")
        let routeVendor = feature.gpxRouteExtensions?[0]?["gpxx"]?["VendorField"]
        #expect(routeVendor as? String == "kept")

        let reloaded = try GPXCoder.read(from: try GPXCoder.write(
            FeatureCollection([feature])))
        let route = try #require(reloaded.gpxRoutes.first)
        #expect(route.gpxRouteTimes == [base, nil])
        #expect(route.gpxRouteNames == ["First", nil])
        #expect(route.gpxRouteDescriptions == ["Description", nil])
        #expect(route.gpxRouteLinks?[0]?.first?.href == "https://rtept.example")
        let reloadedVendor = route.gpxRouteExtensions?[0]?["gpxx"]?["VendorField"]
        #expect(reloadedVendor as? String == "kept")
    }

    // MARK: - Metadata

    @Test
    func metadataSettersRoundTripIncludingLinksAndNilValues() throws {
        var fc = FeatureCollection()
        fc.gpxMetadataName = "Metadata"
        fc.gpxMetadataDescription = "Description"
        fc.gpxMetadataKeywords = "a, b"
        fc.gpxMetadataTime = Date(timeIntervalSince1970: 1_700_000_000.0)
        fc.gpxMetadataAuthor = GPXPerson(
            name: "Author",
            email: "author@example.com",
            link: GPXLink(href: "https://author.example", text: "Author site"))
        fc.gpxMetadataCopyright = GPXCopyright(
            author: "Holder",
            year: 2024,
            license: "MIT")
        fc.gpxMetadataLinks = [
            GPXLink(href: "https://one.example", text: "One"),
            GPXLink(href: "https://two.example"),
        ]
        fc.gpxMetadataBounds = BoundingBox(
            southWest: Coordinate3D(latitude: 52.0, longitude: 13.0),
            northEast: Coordinate3D(latitude: 53.0, longitude: 14.0))

        let reloaded = try GPXCoder.read(from: try GPXCoder.write(fc))

        #expect(reloaded.gpxMetadataName == "Metadata")
        #expect(reloaded.gpxMetadataDescription == "Description")
        #expect(reloaded.gpxMetadataKeywords == "a, b")
        #expect(reloaded.gpxMetadataTime == fc.gpxMetadataTime)
        #expect(reloaded.gpxMetadataAuthor?.name == "Author")
        #expect(reloaded.gpxMetadataAuthor?.email == "author@example.com")
        #expect(reloaded.gpxMetadataAuthor?.link?.href == "https://author.example")
        #expect(reloaded.gpxMetadataCopyright?.year == 2024)
        #expect(reloaded.gpxMetadataLinks.map(\.href)
            == ["https://one.example", "https://two.example"])
        #expect(reloaded.gpxMetadataBounds?.northEast.latitude == 53.0)
    }

    @Test
    func unrelatedForeignMembersDoNotCreateMetadata() throws {
        var fc = FeatureCollection()
        fc.foreignMembers["unrelated"] = "value"

        let data = try GPXCoder.write(fc)
        let xml = String(decoding: data, as: UTF8.self)
        #expect(!xml.contains("<metadata>"))
    }

    @Test
    func metadataLinksReadSingleDictionaryStorage() {
        var fc = FeatureCollection()
        fc.foreignMembers["gpx_link"] = [
            "href": "https://single.example",
            "text": "Single",
        ] as [String: String]
        #expect(fc.gpxMetadataLinks.first?.href == "https://single.example")
        #expect(fc.gpxMetadataLinks.first?.text == "Single")

        fc.gpxMetadataLinks = []
        #expect(fc.foreignMembers["gpx_link"] == nil)
    }

    // MARK: - Errors

    @Test
    func missingFileThrowsFileReadError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing_\(UUID().uuidString).gpx")

        do {
            _ = try GPXCoder.read(from: url)
            Issue.record("Expected missing file to throw")
        }
        catch let error as GPXError {
            guard case .fileReadError = error else {
                Issue.record("Expected .fileReadError, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func errorDescriptionsCoverEveryCase() {
        let errors: [GPXError] = [
            .fileReadError(detail: "read"),
            .fileWriteError(detail: "write"),
            .invalidXML(detail: "xml"),
            .invalidEncoding,
            .invalidGPX(detail: "gpx"),
            .unsupportedVersion(version: "2.0"),
            .invalidCoordinate(detail: "coordinate"),
        ]

        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(GPXError.unsupportedVersion(version: "2.0").errorDescription?
            .contains("2.0") == true)
    }

    // MARK: - Extension namespace helpers

    @Test
    func extensionNamespaceHelpers() throws {
        #expect(GPXExtensionNamespace.namespace(
            forURI: "http://www.garmin.com/xmlschemas/TrackPointExtension/v2") == .gpxtpx)
        #expect(GPXExtensionNamespace.namespace(
            forURI: "http://www.garmin.com/xmlschemas/GpxExtensions/v3") == .gpxx)
        #expect(GPXExtensionNamespace.namespace(forURI: "https://example.com") == nil)
        #expect(GPXExtensionNamespace.namespace(forPrefix: "GPXTPX") == .gpxtpx)
        #expect(GPXExtensionNamespace.namespace(forPrefix: "nope") == nil)
        #expect(GPXExtensionNamespace.namespace(for: "gpxx") == .gpxx)
        #expect(GPXExtensionNamespace.gpxtpx.prefix == "gpxtpx")
        #expect(GPXExtensionNamespace.gpxx.prefix == "gpxx")
        #expect(GPXExtensionNamespace.children(for: "gpxtpx").contains("hr"))
        #expect(GPXExtensionNamespace.children(for: "nope").isEmpty)
        #expect(GPXExtensionNamespace.gpxtpx.allowedIn == [.trackPoint])
        #expect(GPXExtensionNamespace.gpxx.allowedIn.contains(.waypoint))
        #expect(GPXExtensionNamespace.gpxx.allowedIn.contains(.route))
        #expect(GPXExtensionNamespace.gpxx.allowedIn.contains(.track))
        #expect(GPXExtensionNamespace.gpxx.allowedIn.contains(.routePoint))
    }

    @Test
    func linkURLIsDerivedFromHref() {
        #expect(GPXLink(href: "https://example.com").url?.host == "example.com")
        #expect(GPXLink(href: "").url == nil)
    }

}
