import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXReadTests {

    // MARK: - Waypoint tests

    @Test
    func readWaypoints() async throws {
        let url = try #require(TestData.url(name: "waypoints.gpx"))
        let fc = try GPXCoder.read(from: url)

        let waypoints = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        #expect(waypoints.count == 3)

        let berlin = waypoints[0]
        #expect(berlin.properties["name"] as? String == "Reichstag (Berlin)")
        #expect(berlin.properties["sym"] as? String == "City")
        #expect(berlin.properties["fix"] as? String == "3d")
        #expect(berlin.properties["sat"] as? Int == 12)
        #expect(berlin.properties["hdop"] as? Double == 1.5)

        let point = berlin.geometry as? Point
        #expect(point != nil)
        #expect(point!.coordinate.latitude == 52.518611)
        #expect(point!.coordinate.longitude == 13.376111)
        #expect(point!.coordinate.altitude == 35.0)

        let paris = waypoints[1]
        #expect(paris.properties["name"] as? String == "Eiffel Tower")
        #expect(paris.properties["sym"] as? String == "Landmark")

        let london = waypoints[2]
        #expect(london.properties["name"] as? String == "Big Ben")
        #expect(london.properties["fix"] as? String == "2d")
    }

    // MARK: - Route tests

    @Test
    func readRoutes() async throws {
        let url = try #require(TestData.url(name: "routes.gpx"))
        let fc = try GPXCoder.read(from: url)

        let routes = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "rte"
        }
        #expect(routes.count == 1)

        let route = routes[0]
        #expect(route.properties["name"] as? String == "Berlin City Walk")
        #expect(route.properties["type"] as? String == "Walking")
        #expect(route.properties["number"] as? Int == 1)

        let lineString = route.geometry as? LineString
        #expect(lineString != nil)
        #expect(lineString!.coordinates.count == 3)
        #expect(lineString!.coordinates[0].latitude == 52.518611)
        #expect(lineString!.coordinates[2].latitude == 52.513791)
    }

    // MARK: - Track tests

    @Test
    func readTracks() async throws {
        let url = try #require(TestData.url(name: "tracks.gpx"))
        let fc = try GPXCoder.read(from: url)

        let tracks = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "trk"
        }
        #expect(tracks.count == 1)

        let track = tracks[0]
        #expect(track.properties["name"] as? String == "Morning Run")
        #expect(track.properties["type"] as? String == "Running")

        let multiLine = track.geometry as? MultiLineString
        #expect(multiLine != nil)
        #expect(multiLine!.lineStrings.count == 2)
        #expect(multiLine!.lineStrings[0].coordinates.count == 3)
        #expect(multiLine!.lineStrings[1].coordinates.count == 3)
    }

    // MARK: - Metadata tests

    @Test
    func readMetadata() async throws {
        let url = try #require(TestData.url(name: "metadata.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        #expect(fc.features.isEmpty)

        let name = fc.foreignMembers["gpx_name"] as? String
        #expect(name == "Test GPX File")

        let desc = fc.foreignMembers["gpx_desc"] as? String
        #expect(desc == "A GPX file with full metadata for testing")

        let keywords = fc.foreignMembers["gpx_keywords"] as? String
        #expect(keywords == "test, fixture, metadata")

        let author = fc.foreignMembers["gpx_author"] as? [String: Sendable]
        #expect(author?["name"] as? String == "Test Author")
        #expect(author?["email"] as? String == "test@example.com")

        let cr = fc.foreignMembers["gpx_copyright"] as? [String: Sendable]
        #expect(cr?["year"] as? Int == 2024)
        #expect(cr?["license"] as? String == "ODbL")
    }

    // MARK: - Complete file

    @Test
    func readCompleteGPX() async throws {
        let url = try #require(TestData.url(name: "complete.gpx"))
        let fc = try GPXCoder.read(from: url)

        let waypoints = fc.features.filter { ($0.properties["gpx_type"] as? String) == "wpt" }
        let routes = fc.features.filter { ($0.properties["gpx_type"] as? String) == "rte" }
        let tracks = fc.features.filter { ($0.properties["gpx_type"] as? String) == "trk" }

        #expect(waypoints.count == 1)
        #expect(routes.count == 1)
        #expect(tracks.count == 1)

        #expect(fc.foreignMembers["gpx_name"] as? String == "Complete Test GPX")
    }

    // MARK: - Empty file

    @Test
    func readEmptyGPX() async throws {
        let url = try #require(TestData.url(name: "empty.gpx"))
        let fc = try #require(FeatureCollection(gpx: url))

        #expect(fc.features.isEmpty)
        #expect(fc.foreignMembers.isEmpty)
    }

    // MARK: - GPX 1.0 tests

    @Test
    func readGPX10Waypoints() async throws {
        let url = try #require(TestData.url(name: "gpx10.gpx"))
        let fc = try GPXCoder.read(from: url)

        let waypoints = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        #expect(waypoints.count == 1)
        #expect(waypoints[0].properties["name"] as? String == "Reichstag")

        let links = waypoints[0].properties["link"] as? [[String: String]]
        #expect(links?.count == 1)
        #expect(links?[0]["href"] == "https://www.bundestag.de")
        #expect(links?[0]["text"] == "Bundestag website")
    }

    @Test
    func readGPX10Route() async throws {
        let url = try #require(TestData.url(name: "gpx10.gpx"))
        let fc = try GPXCoder.read(from: url)

        let routes = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "rte"
        }
        #expect(routes.count == 1)
        #expect(routes[0].properties["name"] as? String == "Berlin Walk")

        let lineString = routes[0].geometry as? LineString
        #expect(lineString != nil)
        #expect(lineString!.coordinates.count == 2)
    }

    // MARK: - OSM trace tests

    @Test
    func readOSMTrace() async throws {
        let url = try #require(TestData.url(name: "osm_trace.gpx"))
        let fc = try GPXCoder.read(from: url)

        let tracks = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "trk"
        }
        #expect(tracks.count == 1)
        #expect(tracks[0].properties["name"] as? String == "Berlin Street Mapping")

        let multiLine = tracks[0].geometry as? MultiLineString
        #expect(multiLine != nil)
        #expect(multiLine!.lineStrings.count == 1)
        #expect(multiLine!.lineStrings[0].coordinates.count == 10)

        let waypoints = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        #expect(waypoints.count == 2)
        #expect(waypoints[0].properties["name"] as? String == "Start")
        #expect(waypoints[1].properties["name"] as? String == "End")
    }

}
