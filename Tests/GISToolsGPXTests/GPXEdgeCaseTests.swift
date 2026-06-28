import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXEdgeCaseTests {

    // MARK: - Error handling

    @Test
    func invalidFile() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try "not a GPX file".write(to: tempURL, atomically: true, encoding: .utf8)

        #expect(FeatureCollection(gpx: tempURL) == nil)
    }

    @Test
    func convenienceInit() async throws {
        let url = try #require(TestData.url(name: "waypoints.gpx"))

        let fc = try #require(FeatureCollection(gpx: url))
        #expect(fc.features.count == 3)
    }

    // MARK: - Geometry type inference (write)

    @Test
    func inferGeometryTypeFromProperties() async throws {
        var pointFeature = Feature(Point(Coordinate3D(latitude: 0.0, longitude: 0.0)))
        pointFeature.properties["gpx_type"] = "wpt"
        pointFeature.properties["name"] = "Test Point"

        var routeFeature = Feature(
            LineString(unchecked: [
                Coordinate3D(latitude: 0.0, longitude: 0.0),
                Coordinate3D(latitude: 1.0, longitude: 1.0),
            ]))
        routeFeature.properties["gpx_type"] = "rte"
        routeFeature.properties["name"] = "Test Route"

        var trackFeature = Feature(
            MultiLineString(unchecked: [
                LineString(unchecked: [
                    Coordinate3D(latitude: 0.0, longitude: 0.0),
                    Coordinate3D(latitude: 1.0, longitude: 1.0),
                ]),
            ]))
        trackFeature.properties["gpx_type"] = "trk"
        trackFeature.properties["name"] = "Test Track"

        let fc = FeatureCollection([pointFeature, routeFeature, trackFeature])

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("infer_\(UUID().uuidString).gpx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try fc.writeGPX(to: tempURL)
        let reloaded = try #require(FeatureCollection(gpx: tempURL))

        let wpts = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "wpt" }
        let rtes = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "rte" }
        let trks = reloaded.features.filter { ($0.properties["gpx_type"] as? String) == "trk" }

        #expect(wpts.count == 1)
        #expect(rtes.count == 1)
        #expect(trks.count == 1)

        #expect(wpts[0].properties["name"] as? String == "Test Point")
        #expect(rtes[0].geometry.type == .lineString)
        #expect(trks[0].geometry.type == .multiLineString)
    }

}
