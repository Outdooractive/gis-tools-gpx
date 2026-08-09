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

        // Route-level metadata must round-trip
        #expect(relRoutes[0].properties["cmt"] as? String == "A walking route through Berlin")
        #expect(relRoutes[0].properties["desc"] as? String == "Explore Berlin landmarks on foot")
        #expect(relRoutes[0].properties["src"] as? String == "GISTools test data")
        #expect(relRoutes[0].properties["number"] as? Int == 1)
        #expect(relRoutes[0].properties["type"] as? String == "Walking")
    }

    // MARK: - Route per-point round-trip

    @Test
    func routePointDataRoundTrip() async throws {
        let url = try #require(TestData.url(name: "routes.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip_rtept_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let origRoute = original.features.first { ($0.properties["gpx_type"] as? String) == "rte" }
        let relRoute = reloaded.features.first { ($0.properties["gpx_type"] as? String) == "rte" }
        #expect(origRoute != nil)
        #expect(relRoute != nil)

        // 3 rtepts in the fixture
        let relLine = relRoute?.geometry as? LineString
        #expect(relLine?.coordinates.count == 3)

        // Per-rtept scalar arrays
        #expect(relRoute?.properties["gpx_route_names"] as? [String?]
            == ["Reichstag", "Brandenburg Gate", "Holocaust Memorial"])
        #expect(relRoute?.properties["gpx_route_comments"] as? [String?]
            == ["Start of the walk", nil, nil])
        #expect(relRoute?.properties["gpx_route_symbols"] as? [String?]
            == ["Trailhead", nil, nil])
        #expect(relRoute?.properties["gpx_route_types"] as? [String?]
            == ["Landmark", nil, nil])

        // Per-rtept time (only on the first rtept in the fixture)
        let origTimes = origRoute?.properties["gpx_route_times"] as? [Double?]
        let relTimes = relRoute?.properties["gpx_route_times"] as? [Double?]
        #expect(relTimes?.count == 3)
        #expect(origTimes?.count == relTimes?.count)
        #expect(relTimes?[0] != nil)
        #expect(relTimes?[1] == nil)
        #expect(relTimes?[2] == nil)
        if let orig = origTimes, let rel = relTimes {
            for i in 0 ..< orig.count {
                #expect(rel[i] == orig[i], "rtept time at \(i) did not round-trip")
            }
        }

        // Per-rtept links (only the second rtept has one)
        let relLinks = relRoute?.properties["gpx_route_links"] as? [[[String: String]]]
        #expect(relLinks?.count == 3)
        #expect(relLinks?[0].isEmpty == true)
        #expect(relLinks?[1].count == 1)
        #expect(relLinks?[1][0]["href"] == "https://example.com/gate")
        #expect(relLinks?[1][0]["text"] == "Gate info")
        #expect(relLinks?[2].isEmpty == true)

        // Per-rtept extensions (only the third rtept has a RoutePointExtension)
        let relExts = relRoute?.properties["gpx_route_extensions"] as? [[String: Sendable]]
        #expect(relExts?.count == 3)
        #expect(relExts?[0].isEmpty == true)
        #expect(relExts?[1].isEmpty == true)
        let gpxx = relExts?[2]["gpxx"] as? [String: Sendable]
        let rptPoints = gpxx?["rpt"] as? [Sendable]
        #expect(rptPoints?.count == 2)
        let firstRpt = rptPoints?[0] as? [String: Double]
        #expect(firstRpt?["lat"] == 52.5145)
        #expect(firstRpt?["lon"] == 13.3782)
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

        // Times must survive the round-trip (regression check)
        let origTimes = origTracks[0].properties["gpx_times"] as? [Double?]
        let relTimes = relTracks[0].properties["gpx_times"] as? [Double?]
        #expect(origTimes?.count == 6)
        #expect(relTimes?.count == origTimes?.count)
        #expect(relTimes?.allSatisfy { $0 != nil } == true)
    }

    // MARK: - Track per-point round-trip (time + sensor arrays)

    @Test
    func trackPointDataRoundTrip() async throws {
        let url = try #require(TestData.url(name: "extensions_gpxtpx.gpx"))
        let original = try GPXCoder.read(from: url)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrack_sensor_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try original.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let origTrack = original.features.first { ($0.properties["gpx_type"] as? String) == "trk" }
        let relTrack = reloaded.features.first { ($0.properties["gpx_type"] as? String) == "trk" }
        #expect(origTrack != nil)
        #expect(relTrack != nil)

        // Per-point time array
        let origTimes = origTrack?.properties["gpx_times"] as? [Double?]
        let relTimes = relTrack?.properties["gpx_times"] as? [Double?]
        #expect(relTimes?.count == 3)
        #expect(origTimes?.count == relTimes?.count)
        if let orig = origTimes, let rel = relTimes {
            for i in 0 ..< orig.count {
                #expect(rel[i] != nil, "time at \(i) was lost on re-encode")
                #expect(rel[i] == orig[i])
            }
        }

        // Heart rate, cadence, partial speed & atemp arrays
        #expect((relTrack?.properties["gpx_heart_rates"] as? [Int?]) == [120, 145, 160])
        #expect((relTrack?.properties["gpx_cadences"] as? [Int?]) == [85, 90, 95])
        #expect((relTrack?.properties["gpx_speeds"] as? [Double?]) == [nil, nil, 12.5])
        #expect((relTrack?.properties["gpx_air_temperatures"] as? [Double?]) == [nil, 18.5, nil])
        // No power data in fixture
        #expect(relTrack?.properties["gpx_powers"] == nil)
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

        let m = reloaded.foreignMembers

        // Scalar metadata fields
        #expect(m["gpx_name"] as? String == "Test GPX File")
        #expect(m["gpx_desc"] as? String == "A GPX file with full metadata for testing")
        #expect(m["gpx_keywords"] as? String == "test, fixture, metadata")
        #expect(m["gpx_time"] as? String == original.foreignMembers["gpx_time"] as? String)

        // Author (person): name, email, link
        let author = m["gpx_author"] as? [String: Sendable]
        #expect(author?["name"] as? String == "Test Author")
        #expect(author?["email"] as? String == "test@example.com")
        let authorLink = author?["link"] as? [String: String]
        #expect(authorLink?["href"] == "https://example.com")
        #expect(authorLink?["text"] == "Author Website")

        // Copyright: author, year, license
        let copyright = m["gpx_copyright"] as? [String: Sendable]
        #expect(copyright?["author"] as? String == "OpenStreetMap Contributors")
        #expect(copyright?["year"] as? Int == 2024)
        #expect(copyright?["license"] as? String == "ODbL")

        // Top-level metadata links
        let links = m["gpx_link"] as? [[String: String]]
        #expect(links?.count == 1)
        #expect(links?[0]["href"] == "https://www.openstreetmap.org")
        #expect(links?[0]["text"] == "OpenStreetMap")

        // Bounds
        let bounds = m["gpx_bounds"] as? [String: Sendable]
        #expect(bounds?["minlat"] as? Double == 52.5)
        #expect(bounds?["minlon"] as? Double == 13.3)
        #expect(bounds?["maxlat"] as? Double == 52.6)
        #expect(bounds?["maxlon"] as? Double == 13.5)
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
