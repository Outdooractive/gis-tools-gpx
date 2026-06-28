import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXRoundTripTests {

    // MARK: - Waypoint round-trip

    @Test
    func waypointRoundTrip() async throws {
        let url = try #require(TestData.url(name: "waypoints.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_waypoints_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        #expect(reloaded.features.count == original.features.count)
        for i in 0 ..< original.features.count {
            #expect(reloaded.features[i].properties["name"] as? String
                == original.features[i].properties["name"] as? String)
            #expect(reloaded.features[i].properties["gpx_type"] as? String
                == original.features[i].properties["gpx_type"] as? String)
        }
    }

    // MARK: - Route round-trip

    @Test
    func routeRoundTrip() async throws {
        let url = try #require(TestData.url(name: "routes.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_route_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let origRoutes = original.features.filter { ($0.properties["gpx_type"] as? String) == "rte" }
        let relRoutes = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "rte" }
        #expect(relRoutes.count == origRoutes.count)
        #expect(relRoutes[0].properties["name"] as? String == "Berlin City Walk")
    }

    // MARK: - Track round-trip

    @Test
    func trackRoundTrip() async throws {
        let url = try #require(TestData.url(name: "tracks.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_track_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let origTracks = original.features.filter { ($0.properties["gpx_type"] as? String) == "trk" }
        let relTracks = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "trk" }
        #expect(relTracks.count == origTracks.count)

        let origML = origTracks[0].geometry as? MultiLineString
        let relML = relTracks[0].geometry as? MultiLineString
        #expect(origML?.lineStrings.count == relML?.lineStrings.count)
        for i in 0 ..< (origML?.lineStrings.count ?? 0) {
            #expect(origML!.lineStrings[i].coordinates.count == relML!.lineStrings[i].coordinates.count)
        }
    }

    // MARK: - Metadata round-trip

    @Test
    func metadataRoundTrip() async throws {
        let url = try #require(TestData.url(name: "metadata.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_meta_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        #expect(reloaded.foreignMembers["gpx_name"] as? String == "Test GPX File")
        #expect(reloaded.foreignMembers["gpx_keywords"] as? String == "test, fixture, metadata")
    }

    // MARK: - Complete file round-trip

    @Test
    func completeRoundTrip() async throws {
        let url = try #require(TestData.url(name: "complete.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_complete_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let origWpt = original.features.filter { ($0.properties["gpx_type"] as? String) == "wpt" }
        let relWpt = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "wpt" }
        #expect(relWpt.count == origWpt.count)

        let origRte = original.features.filter { ($0.properties["gpx_type"] as? String) == "rte" }
        let relRte = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "rte" }
        #expect(relRte.count == origRte.count)

        let origTrk = original.features.filter { ($0.properties["gpx_type"] as? String) == "trk" }
        let relTrk = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "trk" }
        #expect(relTrk.count == origTrk.count)

        #expect(reloaded.foreignMembers["gpx_name"] as? String == "Complete Test GPX")
    }

    // MARK: - GPX 1.0 round-trip (best-effort)

    @Test
    func readGPX10TrackCourseSpeed() async throws {
        let url = try #require(TestData.url(name: "gpx10.gpx"))
        let fc = try GPXCoder.read(from: url)

        let tracks = fc.features.filter {
            ($0.properties["gpx_type"] as? String) == "trk"
        }
        #expect(tracks.count == 1)
        #expect(tracks[0].properties["name"] as? String == "Track with course/speed")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_gpx10_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try fc.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))
        #expect(reloaded.features.count >= 1)
    }

    // MARK: - Structured extension round-trip

    @Test
    func structuredExtensionRoundTrip() async throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_struct_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let waypoints = reloaded.features.filter {
            ($0.properties["gpx_type"] as? String) == "wpt"
        }
        #expect(waypoints.count == 1)
        #expect(waypoints[0].properties["name"] as? String == "Outdooractive HQ")

        let extensions = waypoints[0].properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]

        let address = gpxx?["Address"] as? [String: Sendable]
        #expect(address?["City"] as? String == "Berlin")
        #expect(address?["Country"] as? String == "Germany")

        let categories = gpxx?["Categories"] as? [Sendable]
        if let cats = categories {
            #expect(cats.count == 3 || cats.count == 4,
                    "Categories count mismatch: \(cats.count)")
        }
    }

}
