import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXPointFeatureTests {

    private func trackFeature(
        coordinates: [Coordinate3D],
        times: [Date?]? = nil,
        heartRates: [Int?]? = nil,
        speeds: [Double?]? = nil,
        courses: [Double?]? = nil
    ) -> Feature {
        var feature = Feature(MultiLineString(unchecked: [
            LineString(unchecked: coordinates),
        ]))
        feature.gpxType = .track
        feature.gpxTimes = times
        feature.gpxHeartRates = heartRates
        feature.gpxSpeeds = speeds
        feature.gpxCourses = courses
        return feature
    }

    // MARK: - Point feature generation

    @Test
    func trackPointQualityFieldsSurviveRoundTrip() throws {
        let fc = try GPXCoder.read(from: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="52.5" lon="13.4">
                    <magvar>2.5</magvar>
                    <geoidheight>47</geoidheight>
                    <fix>3d</fix>
                    <sat>9</sat>
                    <hdop>1.1</hdop>
                    <vdop>1.2</vdop>
                    <pdop>1.3</pdop>
                    <ageofdgpsdata>0.5</ageofdgpsdata>
                    <dgpsid>42</dgpsid>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """.utf8))

        let track = try #require(fc.gpxTracks.first)
        let quality = try #require(track.gpxTrackPointQuality?.first ?? nil)
        #expect(quality["fix"] as? String == "3d")
        #expect(quality["sat"] as? Int == 9)

        let points = track.gpxPointFeatures()
        let point = try #require(points.features.first)
        #expect(point.gpxFix == .threeDimensional)
        #expect(point.gpxSatellites == 9)
        #expect(point.gpxDGPSID == 42)

        let rebuilt = try #require(points.gpxTrackFromPointFeatures())
        let reloaded = try GPXCoder.read(from: try GPXCoder.write(
            FeatureCollection([rebuilt])))
        let result = try #require(reloaded.gpxTracks.first)
        let reloadedQuality = try #require(result.gpxTrackPointQuality?.first ?? nil)
        #expect(reloadedQuality["fix"] as? String == "3d")
        #expect(reloadedQuality["sat"] as? Int == 9)
        #expect(reloadedQuality["hdop"] as? Double == 1.1)
        #expect(reloadedQuality["dgpsid"] as? Int == 42)
    }

    @Test
    func pointFeaturesCarryTimesAndSensors() throws {
        let url = try #require(TestData.url(name: "extensions_gpxtpx.gpx"))
        let fc = try GPXCoder.read(from: url)
        let track = try #require(fc.gpxTracks.first)

        let points = track.gpxPointFeatures()
        #expect(points.features.count == 3)

        let first = points.features[0]
        #expect(first.gpxTime != nil)
        #expect(first.gpxHeartRate == 120)
        #expect(first.gpxCadence == 85)
        #expect(first.gpxElevation == 35.0)

        // The time must survive writing point features as waypoints.
        let reloaded = try GPXCoder.read(from: try GPXCoder.write(points))
        let waypoint = try #require(reloaded.gpxWaypoints.first)
        #expect(waypoint.gpxTime == first.gpxTime)
    }

    @Test
    func pointFeaturesIncludeCourseAndUnknownExtensions() throws {
        let fc = try GPXCoder.read(from: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
                 version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="52.5" lon="13.4">
                    <extensions>
                      <gpxtpx:TrackPointExtension>
                        <gpxtpx:course>45</gpxtpx:course>
                        <gpxtpx:wtemp>17.5</gpxtpx:wtemp>
                        <gpxtpx:bearing>90</gpxtpx:bearing>
                        <gpxtpx:vendorField>kept</gpxtpx:vendorField>
                      </gpxtpx:TrackPointExtension>
                    </extensions>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """.utf8))

        let track = try #require(fc.gpxTracks.first)
        #expect(track.gpxCourses == [45.0])
        #expect(track.gpxWaterTemperatures == [17.5])
        #expect(track.gpxBearings == [90.0])

        let points = track.gpxPointFeatures()
        let point = try #require(points.features.first)
        #expect(point.gpxCourse == 45.0)
        #expect(point.gpxWaterTemperature == 17.5)
        #expect(point.gpxBearing == 90.0)

        let extensions = point.properties["extensions"] as? [String: Sendable]
        let gpxtpx = extensions?["gpxtpx"] as? [String: Sendable]
        #expect(gpxtpx?["vendorField"] as? String == "kept")
    }

    @Test
    func pointFeaturesPreserveTrackPointMetadata() throws {
        let fc = try GPXCoder.read(from: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="52.5" lon="13.4">
                    <name>Point one</name>
                    <cmt>Note</cmt>
                    <desc>Description</desc>
                    <src>GPS</src>
                    <sym>Flag</sym>
                    <type>Waypoint</type>
                    <link href="https://point.example"><text>Point link</text></link>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """.utf8))

        let track = try #require(fc.gpxTracks.first)
        let points = track.gpxPointFeatures()
        let point = try #require(points.features.first)

        #expect(point.gpxName == "Point one")
        #expect(point.gpxComment == "Note")
        #expect(point.gpxDescription == "Description")
        #expect(point.gpxSource == "GPS")
        #expect(point.gpxSymbol == "Flag")
        #expect(point.gpxTypeName == "Waypoint")
        #expect(point.gpxLinks.first?.href == "https://point.example")
    }

    // MARK: - Slicing

    @Test
    func timeSliceHandlesMissingTimestamps() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000.0)
        let coordinates = [
            Coordinate3D(latitude: 52.50, longitude: 13.40),
            Coordinate3D(latitude: 52.51, longitude: 13.41),
            Coordinate3D(latitude: 52.52, longitude: 13.42),
        ]
        let track = trackFeature(
            coordinates: coordinates,
            times: [base, nil, base.addingTimeInterval(60.0)])

        let sliced = track.gpxPointFeatures(
            from: base.addingTimeInterval(-1.0),
            to: base.addingTimeInterval(61.0))
        #expect(sliced.features.count == 2)

        let none = trackFeature(coordinates: coordinates)
        #expect(none.gpxPointFeatures(
            from: base,
            to: base.addingTimeInterval(60.0)).features.isEmpty)
    }

    @Test
    func timeSliceBoundariesAreInclusive() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000.0)
        let track = trackFeature(
            coordinates: [
                Coordinate3D(latitude: 52.50, longitude: 13.40),
                Coordinate3D(latitude: 52.51, longitude: 13.41),
                Coordinate3D(latitude: 52.52, longitude: 13.42),
            ],
            times: [
                base,
                base.addingTimeInterval(60.0),
                base.addingTimeInterval(120.0),
            ])

        let firstTwo = track.gpxPointFeatures(
            from: base,
            to: base.addingTimeInterval(60.0))
        #expect(firstTwo.features.count == 2)

        let reversed = track.gpxPointFeatures(
            from: base.addingTimeInterval(120.0),
            to: base)
        #expect(reversed.features.isEmpty)
    }

    @Test
    func distanceSliceSelectsPointsAlongTrack() throws {
        let coordinates = [
            Coordinate3D(latitude: 52.50, longitude: 13.40),
            Coordinate3D(latitude: 52.51, longitude: 13.40),
            Coordinate3D(latitude: 52.52, longitude: 13.40),
        ]
        let track = trackFeature(coordinates: coordinates)

        let all = track.gpxPointFeatures(from: 0.0, to: 100_000.0)
        #expect(all.features.count == 3)

        let firstSegment = track.gpxPointFeatures(from: 0.0, to: 1_500.0)
        #expect(firstSegment.features.count == 2)

        let none = track.gpxPointFeatures(from: 10_000.0, to: 20_000.0)
        #expect(none.features.isEmpty)
    }

    @Test
    func fractionSliceClampsToTrack() throws {
        let track = trackFeature(
            coordinates: [
                Coordinate3D(latitude: 52.50, longitude: 13.40),
                Coordinate3D(latitude: 52.51, longitude: 13.40),
                Coordinate3D(latitude: 52.52, longitude: 13.40),
            ])

        #expect(track.gpxPointFeatures(fraction: 0.0, to: 1.0).features.count == 3)
        #expect(track.gpxPointFeatures(fraction: -1.0, to: 2.0).features.count == 3)
        #expect(track.gpxPointFeatures(fraction: 0.8, to: 0.2).features.isEmpty)
    }

    @Test
    func emptyTrackSlicesAreEmpty() throws {
        let track = trackFeature(coordinates: [])
        #expect(track.gpxPointFeatures().features.isEmpty)
        #expect(track.gpxPointFeatures(fraction: 0.0, to: 1.0).features.isEmpty)
        #expect(track.gpxPointFeatures(from: 0.0, to: 100.0).features.isEmpty)
    }

    // MARK: - Reconstruction

    @Test
    func reconstructTrackFromPointFeaturesPreservesAllSensors() throws {
        let fc = try GPXCoder.read(from: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
                 version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="52.50" lon="13.40">
                    <ele>100</ele>
                    <time>2024-01-15T08:00:00.000Z</time>
                    <extensions>
                      <gpxtpx:TrackPointExtension>
                        <gpxtpx:hr>120</gpxtpx:hr>
                        <gpxtpx:speed>12</gpxtpx:speed>
                        <gpxtpx:course>45</gpxtpx:course>
                        <gpxtpx:atemp>18</gpxtpx:atemp>
                        <gpxtpx:wtemp>15</gpxtpx:wtemp>
                        <gpxtpx:depth>3</gpxtpx:depth>
                        <gpxtpx:bearing>90</gpxtpx:bearing>
                      </gpxtpx:TrackPointExtension>
                    </extensions>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """.utf8))

        let track = try #require(fc.gpxTracks.first)
        let points = track.gpxPointFeatures()
        let rebuilt = try #require(points.gpxTrackFromPointFeatures())

        #expect(rebuilt.gpxHeartRates == [120])
        #expect(rebuilt.gpxSpeeds == [12.0])
        #expect(rebuilt.gpxCourses == [45.0])
        #expect(rebuilt.gpxAirTemperatures == [18.0])
        #expect(rebuilt.gpxWaterTemperatures == [15.0])
        #expect(rebuilt.gpxDepths == [3.0])
        #expect(rebuilt.gpxBearings == [90.0])
        #expect(rebuilt.gpxElevations == [100.0])
        #expect(rebuilt.gpxTimes?.first != nil)
    }

    @Test
    func reconstructTrackHandlesIntegerExtensionValues() throws {
        var point = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        point.gpxType = .waypoint
        point.properties["extensions"] = [
            "gpxtpx": ["speed": 12, "atemp": 20],
        ] as [String: Sendable]

        let rebuilt = try #require(
            FeatureCollection([point]).gpxTrackFromPointFeatures())
        #expect(rebuilt.gpxSpeeds == [12.0])
        #expect(rebuilt.gpxAirTemperatures == [20.0])
    }

    @Test
    func reconstructedTrackPreservesPointMetadataAndUnknownExtensions() throws {
        let fc = try GPXCoder.read(from: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
                 version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="52.5" lon="13.4">
                    <name>Named point</name>
                    <link href="https://point.example"><text>Point</text></link>
                    <extensions>
                      <gpxtpx:TrackPointExtension>
                        <gpxtpx:vendorField>kept</gpxtpx:vendorField>
                      </gpxtpx:TrackPointExtension>
                    </extensions>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """.utf8))

        let track = try #require(fc.gpxTracks.first)
        let rebuilt = try #require(
            track.gpxPointFeatures().gpxTrackFromPointFeatures())

        #expect(rebuilt.gpxTrackNames == ["Named point"])
        let firstPointLinks = rebuilt.gpxTrackLinks?.first ?? nil
        #expect(firstPointLinks?.first?.href == "https://point.example")

        let extensions = rebuilt.gpxTrackPointExtensions?.first ?? nil
        let gpxtpx = extensions?["gpxtpx"]
        #expect(gpxtpx?["vendorField"] as? String == "kept")
    }

    @Test
    func reconstructedTrackRoundTripsThroughGPX() throws {
        let fc = try GPXCoder.read(from: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
                 version="1.1">
              <trk>
                <trkseg>
                  <trkpt lat="52.5" lon="13.4">
                    <time>2024-01-15T08:00:00.000Z</time>
                    <extensions>
                      <gpxtpx:TrackPointExtension>
                        <gpxtpx:hr>120</gpxtpx:hr>
                        <gpxtpx:speed>12</gpxtpx:speed>
                      </gpxtpx:TrackPointExtension>
                    </extensions>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """.utf8))

        let track = try #require(fc.gpxTracks.first)
        let rebuilt = try #require(
            track.gpxPointFeatures().gpxTrackFromPointFeatures())

        let reloaded = try GPXCoder.read(from: try GPXCoder.write(
            FeatureCollection([rebuilt])))
        let result = try #require(reloaded.gpxTracks.first)

        #expect(result.gpxHeartRates == [120])
        #expect(result.gpxSpeeds == [12.0])
        #expect(result.gpxTimes?.first != nil)
    }

    @Test
    func nonPointFeaturesAreSkippedDuringReconstruction() throws {
        var point = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.4)))
        point.gpxType = .waypoint
        var route = Feature(LineString(unchecked: [
            Coordinate3D(latitude: 52.5, longitude: 13.4),
            Coordinate3D(latitude: 52.6, longitude: 13.5),
        ]))
        route.gpxType = .route

        let rebuilt = try #require(
            FeatureCollection([route, point]).gpxTrackFromPointFeatures())
        let geometry = try #require(rebuilt.geometry as? MultiLineString)
        #expect(geometry.lineStrings.count == 1)
        #expect(geometry.lineStrings[0].coordinates.count == 1)
    }

}
