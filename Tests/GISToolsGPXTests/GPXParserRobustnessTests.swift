import Foundation
import Testing
@testable import GISTools
@testable import GISToolsGPX

struct GPXParserRobustnessTests {

    private static let header = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="test">
        """

    private func read(_ xml: String) throws -> FeatureCollection {
        try GPXCoder.read(from: Data(xml.utf8))
    }

    // MARK: - Malformed input

    @Test
    func malformedXMLThrowsInvalidXML() {
        do {
            _ = try read("<gpx version=\"1.1\"><trk></gpx>")
            Issue.record("Expected malformed XML to throw")
        }
        catch let error as GPXError {
            guard case .invalidXML = error else {
                Issue.record("Expected .invalidXML, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func emptyDataThrows() {
        #expect(throws: GPXError.self) {
            _ = try GPXCoder.read(from: Data())
        }
    }

    @Test
    func nonGPXRootThrowsInvalidGPX() {
        do {
            _ = try read("<notgpx version=\"1.1\"></notgpx>")
            Issue.record("Expected non-GPX root to throw")
        }
        catch let error as GPXError {
            guard case .invalidGPX = error else {
                Issue.record("Expected .invalidGPX, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func missingVersionThrowsInvalidGPX() {
        do {
            _ = try read(
                """
                <gpx xmlns="http://www.topografix.com/GPX/1/1"></gpx>
                """)
            Issue.record("Expected missing version to throw")
        }
        catch let error as GPXError {
            guard case .invalidGPX = error else {
                Issue.record("Expected .invalidGPX, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func unsupportedVersionThrows() {
        do {
            _ = try read(
                """
                <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.2"></gpx>
                """)
            Issue.record("Expected unsupported version to throw")
        }
        catch let error as GPXError {
            guard case .unsupportedVersion(let version) = error else {
                Issue.record("Expected .unsupportedVersion, got \(error)")
                return
            }
            #expect(version == "1.2")
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func missingCoordinateThrows() {
        do {
            _ = try read(
                """
                <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
                  <wpt lon="13.0"><name>No latitude</name></wpt>
                </gpx>
                """)
            Issue.record("Expected missing coordinate to throw")
        }
        catch let error as GPXError {
            guard case .invalidGPX = error else {
                Issue.record("Expected .invalidGPX, got \(error)")
                return
            }
        }
        catch {
            Issue.record("Expected GPXError, got \(error)")
        }
    }

    @Test
    func outOfRangeCoordinateThrows() {
        do {
            _ = try read(
                """
                <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
                  <wpt lat="95" lon="13.0"><name>Too far north</name></wpt>
                </gpx>
                """)
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

    // MARK: - Text handling

    @Test
    func cdataAndEntitiesAreDecoded() throws {
        let fc = try read(
            Self.header + """
                  <metadata>
                    <name><![CDATA[Tom & Jerry <3]]></name>
                    <desc>A &amp; B &#x2713;</desc>
                  </metadata>
                </gpx>
                """)

        #expect(fc.gpxMetadataName == "Tom & Jerry <3")
        #expect(fc.gpxMetadataDescription == "A & B \u{2713}")
    }

    @Test
    func extensionsOnSeparateBlocksAreMerged() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
                 xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3"
                 version="1.1">
              <wpt lat="52.5" lon="13.4">
                <name>Split extensions</name>
                <extensions><gpxtpx:hr>111</gpxtpx:hr></extensions>
                <extensions><gpxx:DisplayMode>SymbolAndName</gpxx:DisplayMode></extensions>
              </wpt>
            </gpx>
            """)

        let waypoint = try #require(fc.gpxWaypoints.first)
        #expect(waypoint.gpxHeartRate == 111)
        #expect(waypoint.gpxDisplayMode == "SymbolAndName")
    }

    @Test
    func nonStandardNamespacePrefixIsResolved() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:tpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
                 xmlns:gdata="http://www.garmin.com/xmlschemas/GpxExtensions/v3"
                 version="1.1">
              <trk>
                <name>Aliased</name>
                <extensions><gdata:DisplayColor>Green</gdata:DisplayColor></extensions>
                <trkseg>
                  <trkpt lat="52.5" lon="13.4">
                    <extensions><tpx:TrackPointExtension><tpx:hr>99</tpx:hr></tpx:TrackPointExtension></extensions>
                  </trkpt>
                </trkseg>
              </trk>
            </gpx>
            """)

        let track = try #require(fc.gpxTracks.first)
        #expect(track.gpxHeartRates == [99])
        #expect(track.gpxDisplayColor == "Green")
    }

    // MARK: - Links

    @Test
    func metadataLinksBeforeAndAfterAuthorAreKept() throws {
        let fc = try read(
            Self.header + """
                  <metadata>
                    <link href="https://before.example"><text>Before</text></link>
                    <author>
                      <name>Author</name>
                      <link href="https://author.example"><text>Author site</text></link>
                    </author>
                    <link href="https://after.example" />
                  </metadata>
                </gpx>
                """)

        #expect(fc.gpxMetadataLinks.map(\.href)
            == ["https://before.example", "https://after.example"])
        #expect(fc.gpxMetadataAuthor?.link?.href == "https://author.example")
    }

    @Test
    func routeAndTrackLevelLinksSurvivePoints() throws {
        let fc = try read(
            Self.header + """
                  <rte>
                    <name>Route</name>
                    <link href="https://route.example"><text>Route</text></link>
                    <rtept lat="52.5" lon="13.4"><name>Start</name></rtept>
                  </rte>
                  <trk>
                    <name>Track</name>
                    <link href="https://track.example" />
                    <trkseg>
                      <trkpt lat="52.5" lon="13.4"><name>Point</name></trkpt>
                    </trkseg>
                  </trk>
                </gpx>
                """)

        let route = try #require(fc.gpxRoutes.first)
        #expect(route.gpxLinks.map(\.href) == ["https://route.example"])
        #expect(route.gpxLinks.first?.text == "Route")

        let track = try #require(fc.gpxTracks.first)
        #expect(track.gpxLinks.map(\.href) == ["https://track.example"])
        #expect(track.gpxTrackLinks == nil)
    }

    // MARK: - GPX 1.0 fields

    @Test
    func gpx10PlainTextAuthorEmailAndURLs() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/0" version="1.0">
              <metadata>
                <name>Legacy</name>
                <author>Legacy Author</author>
                <email>legacy@example.com</email>
                <url>https://metadata.example</url>
                <urlname>Metadata site</urlname>
              </metadata>
              <rte>
                <name>Legacy route</name>
                <url>https://route.example</url>
                <urlname>Route site</urlname>
                <rtept lat="52.5" lon="13.4" />
              </rte>
              <trk>
                <name>Legacy track</name>
                <url>https://track.example</url>
              </trk>
            </gpx>
            """)

        #expect(fc.gpxMetadataAuthor?.name == "Legacy Author")
        #expect(fc.gpxMetadataAuthor?.email == "legacy@example.com")
        #expect(fc.gpxMetadataLinks.first?.href == "https://metadata.example")
        #expect(fc.gpxMetadataLinks.first?.text == "Metadata site")

        let route = try #require(fc.gpxRoutes.first)
        #expect(route.gpxLinks.map(\.href) == ["https://route.example"])

        let track = try #require(fc.gpxTracks.first)
        #expect(track.gpxLinks.map(\.href) == ["https://track.example"])
    }

    // MARK: - Extension structure

    @Test
    func lowercaseGarminStructuredExtensionsAreCanonicalized() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3"
                 version="1.1">
              <wpt lat="52.5" lon="13.4">
                <extensions>
                  <gpxx:waypointextension>
                    <gpxx:address>
                      <gpxx:streetaddress>Main Street 1</gpxx:streetaddress>
                      <gpxx:city>Berlin</gpxx:city>
                    </gpxx:address>
                    <gpxx:categories>
                      <gpxx:category>Office</gpxx:category>
                    </gpxx:categories>
                    <gpxx:phonenumber Category="Work">+49</gpxx:phonenumber>
                  </gpxx:waypointextension>
                </extensions>
              </wpt>
            </gpx>
            """)

        let waypoint = try #require(fc.gpxWaypoints.first)
        #expect(waypoint.gpxAddress?.city == "Berlin")
        #expect(waypoint.gpxAddress?.streetAddresses == ["Main Street 1"])
        #expect(waypoint.gpxCategories == ["Office"])
        #expect(waypoint.gpxPhoneNumbers == [GPXPhoneNumber(value: "+49", category: "Work")])
    }

    @Test
    func structuredExtensionValuesAreNotDuplicated() throws {
        let url = try #require(TestData.url(name: "extensions_structured.gpx"))
        let fc = try GPXCoder.read(from: url)
        let waypoint = try #require(fc.gpxWaypoints.first)

        #expect(waypoint.gpxCategories == ["Office", "Technology", "Outdoor"])
        #expect(waypoint.gpxAddress?.streetAddresses
            == ["123 Alpinestrasse", "Floor 4"])
        #expect(waypoint.gpxPhoneNumbers.count == 2)
    }

    @Test
    func emptySegmentsAndRoutesAreHandled() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
              <rte><name>Empty route</name></rte>
              <trk><name>Empty track</name><trkseg></trkseg></trk>
            </gpx>
            """)

        let route = try #require(fc.gpxRoutes.first)
        let line = try #require(route.geometry as? LineString)
        #expect(line.coordinates.isEmpty)

        let track = try #require(fc.gpxTracks.first)
        let lines = try #require(track.geometry as? MultiLineString)
        #expect(lines.lineStrings.count == 1)
        #expect(lines.lineStrings[0].coordinates.isEmpty)

        let reloaded = try GPXCoder.read(from: try GPXCoder.write(fc))
        #expect(reloaded.gpxRoutes.first?.geometry as? LineString != nil)
        #expect(reloaded.gpxTracks.first?.geometry as? MultiLineString != nil)
    }

    @Test
    func prefixedGPXElementsAreParsed() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1" version="1.1">
              <gpx:metadata><gpx:name>Prefixed</gpx:name></gpx:metadata>
              <gpx:wpt lat="52.5" lon="13.4"><gpx:name>Point</gpx:name></gpx:wpt>
            </gpx:gpx>
            """)

        #expect(fc.gpxMetadataName == "Prefixed")
        #expect(fc.gpxWaypoints.first?.gpxName == "Point")
    }

    @Test
    func numericLookingExtensionStringsKeepLeadingZeros() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3"
                 version="1.1">
              <wpt lat="52.5" lon="13.4">
                <extensions><gpxx:Subclass>007</gpxx:Subclass></extensions>
              </wpt>
            </gpx>
            """)

        let waypoint = try #require(fc.gpxWaypoints.first)
        let extensions = waypoint.properties["extensions"] as? [String: Sendable]
        let gpxx = extensions?["gpxx"] as? [String: Sendable]
        #expect(gpxx?["Subclass"] as? String == "007")
    }

    @Test
    func unprefixedExtensionChildrenInsidePrefixedWrapper() throws {
        let fc = try read(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3"
                 version="1.1">
              <wpt lat="52.5" lon="13.4">
                <extensions>
                  <gpxx:WaypointExtension xmlns="http://www.garmin.com/xmlschemas/GpxExtensions/v3">
                    <DisplayMode>SymbolAndName</DisplayMode>
                  </gpxx:WaypointExtension>
                </extensions>
              </wpt>
            </gpx>
            """)

        let waypoint = try #require(fc.gpxWaypoints.first)
        #expect(waypoint.gpxDisplayMode == "SymbolAndName")
    }

}
