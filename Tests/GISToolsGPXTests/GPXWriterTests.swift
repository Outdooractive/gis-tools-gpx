import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXWriterTests {

    private func xml(for fc: FeatureCollection) throws -> String {
        String(decoding: try GPXCoder.write(fc), as: UTF8.self)
    }

    private func reload(_ fc: FeatureCollection) throws -> FeatureCollection {
        try GPXCoder.read(from: try GPXCoder.write(fc))
    }

    @Test
    func routeExtensionsPrecedeRoutePoints() throws {
        var route = Feature(LineString(unchecked: [
            Coordinate3D(latitude: 52.5, longitude: 13.4),
            Coordinate3D(latitude: 52.6, longitude: 13.5),
        ]))
        route.gpxType = .route
        route.gpxName = "Route"
        route.gpxIsAutoNamed = true

        let xml = try xml(for: FeatureCollection([route]))
        let extensions = try #require(xml.range(of: "<extensions>"))
        let routePoint = try #require(xml.range(of: "<rtept "))

        #expect(extensions.lowerBound < routePoint.lowerBound)
        #expect(xml.contains("<gpxx:RouteExtension>"))
    }

    @Test
    func trackExtensionsPrecedeTrackSegments() throws {
        var track = Feature(MultiLineString(unchecked: [
            LineString(unchecked: [
                Coordinate3D(latitude: 52.5, longitude: 13.4),
                Coordinate3D(latitude: 52.6, longitude: 13.5),
            ]),
        ]))
        track.gpxType = .track
        track.gpxName = "Track"
        track.gpxDisplayColor = "Red"

        let xml = try xml(for: FeatureCollection([track]))
        let extensions = try #require(xml.range(of: "<extensions>"))
        let segment = try #require(xml.range(of: "<trkseg>"))

        #expect(extensions.lowerBound < segment.lowerBound)
        #expect(xml.contains("<gpxx:TrackExtension>"))
    }

    @Test
    func garminWrappersUseContextSpecificNames() throws {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.gpxAddress = GPXAddress(city: "Berlin")
        waypoint.gpxProximity = 25.0

        var route = Feature(LineString(unchecked: [
            Coordinate3D(latitude: 52.5, longitude: 13.4),
            Coordinate3D(latitude: 52.6, longitude: 13.5),
        ]))
        route.gpxType = .route
        route.gpxIsAutoNamed = false

        var track = Feature(MultiLineString(unchecked: [
            LineString(unchecked: [
                Coordinate3D(latitude: 52.5, longitude: 13.4),
                Coordinate3D(latitude: 52.6, longitude: 13.5),
            ]),
        ]))
        track.gpxType = .track
        track.gpxDisplayColor = "Blue"

        var point = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        point.gpxType = .waypoint
        point.gpxHeartRate = 120

        let xml = try xml(for: FeatureCollection([waypoint, route, track, point]))

        #expect(xml.contains("<gpxx:WaypointExtension>"))
        #expect(xml.contains("<gpxx:RouteExtension>"))
        #expect(xml.contains("<gpxx:TrackExtension>"))
        #expect(xml.contains("<gpxtpx:TrackPointExtension>"))
        #expect(!xml.contains("<gpxx:Extension>"))
    }

    @Test
    func gpx10CourseSpeedDeclaresGpxtpxNamespace() throws {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.gpxCourse10 = 90.0
        waypoint.gpxSpeed10 = 3.5

        let xml = try xml(for: FeatureCollection([waypoint]))
        #expect(xml.contains("xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v2\""))
        #expect(xml.contains("<gpxtpx:course>90</gpxtpx:course>"))
        #expect(xml.contains("<gpxtpx:speed>3.5</gpxtpx:speed>"))
    }

    @Test
    func specialCharactersRoundTrip() throws {
        let tricky = "A & B <C> \"D\" 'E'\nSecond line"
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.gpxName = tricky
        waypoint.gpxComment = "<comment> & more"
        waypoint.gpxLinks = [GPXLink(
            href: "https://example.com/?a=1&b=2",
            text: "A & B")]

        let xml = try xml(for: FeatureCollection([waypoint]))
        #expect(xml.contains("A &amp; B &lt;C&gt; &quot;D&quot; &apos;E&apos;"))
        #expect(xml.contains("href=\"https://example.com/?a=1&amp;b=2\""))

        let reloaded = try reload(FeatureCollection([waypoint]))
        let result = try #require(reloaded.gpxWaypoints.first)
        #expect(result.gpxName == tricky)
        #expect(result.gpxComment == "<comment> & more")
        #expect(result.gpxLinks.first?.text == "A & B")
    }

    @Test
    func illegalXMLCharactersAreRemoved() throws {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.gpxName = "A\u{0000}B\u{0008}C"

        let reloaded = try reload(FeatureCollection([waypoint]))
        #expect(reloaded.gpxWaypoints.first?.gpxName == "ABC")
    }

    @Test
    func highPrecisionCoordinatesRoundTrip() throws {
        let latitude = 52.51861123456789
        let longitude = 13.37611123456789
        let altitude = 1234.56789012345

        var waypoint = Feature(Point(Coordinate3D(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude)))
        waypoint.gpxType = .waypoint

        let reloaded = try reload(FeatureCollection([waypoint]))
        let point = try #require(reloaded.gpxWaypoints.first?.geometry as? Point)

        #expect(abs(point.coordinate.latitude - latitude) < 0.000000000001)
        #expect(abs(point.coordinate.longitude - longitude) < 0.000000000001)
        #expect(abs((point.coordinate.altitude ?? 0.0) - altitude) < 0.000000001)
    }

    @Test
    func projectedCoordinatesAreWrittenAsWGS84() throws {
        let coordinate = Coordinate3D(latitude: 52.518611, longitude: 13.376111)
        let projected = coordinate.projected(to: .epsg3857)
        #expect(projected.projection == .epsg3857)

        var waypoint = Feature(Point(projected))
        waypoint.gpxType = .waypoint

        let reloaded = try reload(FeatureCollection([waypoint]))
        let point = try #require(reloaded.gpxWaypoints.first?.geometry as? Point)

        #expect(abs(point.coordinate.latitude - coordinate.latitude) < 0.0000001)
        #expect(abs(point.coordinate.longitude - coordinate.longitude) < 0.0000001)
        #expect(point.projection == .epsg4326)
    }

    @Test
    func outOfRangeCoordinatesAreRejected() throws {
        var waypoint = Feature(Point(Coordinate3D.noSRID(x: 1_000_000.0, y: 2_000_000.0)))
        waypoint.gpxType = .waypoint

        do {
            _ = try GPXCoder.write(FeatureCollection([waypoint]))
            Issue.record("Expected out-of-range coordinate to throw")
        }
        catch let error as GPXError {
            guard case .invalidCoordinate = error else {
                Issue.record("Expected .invalidCoordinate, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func emailWithoutAtSignRoundTrips() throws {
        var fc = FeatureCollection()
        fc.gpxMetadataAuthor = GPXPerson(name: "No At", email: "nobody")
        fc.gpxMetadataName = "Email test"

        let xml = try xml(for: fc)
        #expect(xml.contains("<email id=\"nobody\" domain=\"\" />"))

        let reloaded = try reload(fc)
        #expect(reloaded.gpxMetadataAuthor?.email == "nobody")
    }

    @Test
    func emptyCollectionsWriteValidEmptyDocument() throws {
        let xml = try xml(for: FeatureCollection())
        #expect(xml.contains("version=\"1.1\""))
        #expect(xml.contains("</gpx>"))
        #expect(!xml.contains("<metadata>"))

        let reloaded = try reload(FeatureCollection())
        #expect(reloaded.features.isEmpty)
        #expect(reloaded.foreignMembers.isEmpty)
    }

    @Test
    func fileWriteFailureIsWrappedInGPXError() {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint

        let url = URL(fileURLWithPath: "/nonexistent-directory-\(UUID().uuidString)/file.gpx")
        do {
            try FeatureCollection([waypoint]).writeGPX(to: url)
            Issue.record("Expected a file write error")
        }
        catch let error as GPXError {
            guard case .fileWriteError = error else {
                Issue.record("Expected .fileWriteError, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func creatorIsEscapedAndWritten() throws {
        let data = try GPXCoder.write(FeatureCollection(), creator: "A & B")
        let xml = String(decoding: data, as: UTF8.self)
        #expect(xml.contains("creator=\"A &amp; B\""))
    }

    @Test
    func categoriesAndPhoneNumbersUseSchemaShapedElements() throws {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.gpxCategories = ["Office", "Outdoor"]
        waypoint.gpxPhoneNumbers = [
            GPXPhoneNumber(value: "+49", category: "Work"),
        ]

        let xml = try xml(for: FeatureCollection([waypoint]))
        #expect(xml.contains("<gpxx:Categories>"))
        #expect(xml.contains("<gpxx:Category>Office</gpxx:Category>"))
        #expect(xml.contains("<gpxx:PhoneNumber Category=\"Work\">+49</gpxx:PhoneNumber>"))

        let reloaded = try reload(FeatureCollection([waypoint]))
        let result = try #require(reloaded.gpxWaypoints.first)
        #expect(result.gpxCategories == ["Office", "Outdoor"])
        #expect(result.gpxPhoneNumbers.first?.category == "Work")
    }

    @Test
    func unknownExtensionPrefixIsSkippedWithoutBreakingOutput() throws {
        var waypoint = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        waypoint.gpxType = .waypoint
        waypoint.properties["extensions"] = [
            "unknown": ["Value": "x"],
        ] as [String: Sendable]

        let data = try GPXCoder.write(FeatureCollection([waypoint]))
        let xml = String(decoding: data, as: UTF8.self)
        #expect(!xml.contains("unknown:"))
        #expect(xml.contains("</gpx>"))
    }

}
