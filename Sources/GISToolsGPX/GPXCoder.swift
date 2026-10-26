import Foundation
import GISTools

// MARK: - GPXCoder

/// Reads and writes GPX 1.1 files (GPS Exchange Format).
///
/// GPX files contain waypoints (`<wpt>`), routes (`<rte>`), and tracks
/// (`<trk>`). This coder maps them to a `FeatureCollection` with:
///
/// | GPX Element     | GeoJSON Geometry    | `gpx_type` property |
/// |-----------------|---------------------|---------------------|
/// | `<wpt>`         | `Point`             | `"wpt"`             |
/// | `<rte>`         | `LineString`        | `"rte"`             |
/// | `<trk>`         | `MultiLineString`   | `"trk"`             |
///
/// GPX extensions (Garmin `gpxtpx`, `gpxx`, etc.) are stored as a nested
/// dictionary under `Feature.properties["extensions"]`.
///
/// GPX `<metadata>` is stored in `FeatureCollection`'s `foreignMembers`.
public enum GPXCoder {

    // MARK: - Read

    /// Reads a GPX file and returns a `FeatureCollection`.
    ///
    /// - Parameter url: The URL of the GPX file to read.
    /// - Returns: A `FeatureCollection` with the GPX data.
    /// - Throws: ``GPXError`` if the file cannot be read or parsed.
    public static func read(from url: URL) throws -> FeatureCollection {
        let gpx = try GPXParser.parse(url: url)
        return try convertToGeoJSON(gpx)
    }

    /// Reads GPX data and returns a `FeatureCollection`.
    ///
    /// - Parameter data: The raw GPX data.
    /// - Returns: A `FeatureCollection` with the GPX data.
    /// - Throws: ``GPXError`` if the data cannot be parsed.
    public static func read(from data: Data) throws -> FeatureCollection {
        let gpx = try GPXParser.parse(data: data)
        return try convertToGeoJSON(gpx)
    }

    // MARK: - Write

    /// Serializes a `FeatureCollection` to GPX data.
    ///
    /// The collection is reprojected to EPSG:4326 (the only CRS GPX
    /// supports) when it has a known projected CRS.
    ///
    /// - Parameters:
    ///   - featureCollection: The FeatureCollection to serialize.
    ///   - creator: The `creator` attribute value (default `"GISToolsGPX"`).
    /// - Returns: The GPX data.
    /// - Throws: ``GPXError`` if serialization fails.
    public static func write(
        _ featureCollection: FeatureCollection,
        creator: String = "GISToolsGPX"
    ) throws -> Data {
        let collection = collectionInWGS84(featureCollection)
        let gpx = try convertFromGeoJSON(collection)
        let xml = GPXWriter.write(gpx, creator: creator)
        guard let data = xml.data(using: .utf8) else {
            throw GPXError.invalidEncoding
        }
        return data
    }

    /// Writes a `FeatureCollection` as a GPX file.
    ///
    /// - Parameters:
    ///   - featureCollection: The FeatureCollection to write.
    ///   - url: The output URL for the GPX file.
    ///   - creator: The `creator` attribute value (default `"GISToolsGPX"`).
    /// - Throws: ``GPXError`` if the file cannot be written.
    public static func write(
        _ featureCollection: FeatureCollection,
        to url: URL,
        creator: String = "GISToolsGPX"
    ) throws {
        let data = try write(featureCollection, creator: creator)
        do {
            try data.write(to: url)
        }
        catch {
            throw GPXError.fileWriteError(detail: error.localizedDescription)
        }
    }

    // MARK: - Projection

    /// GPX stores WGS84 (EPSG:4326) coordinates only. Reproject known
    /// projected collections; `noSRID` data is written as-is.
    private static func collectionInWGS84(
        _ featureCollection: FeatureCollection
    ) -> FeatureCollection {
        switch featureCollection.projection {
        case .epsg4326, .noSRID:
            featureCollection
        default:
            featureCollection.projected(to: .epsg4326)
        }
    }

    // MARK: - GPXFile → FeatureCollection

    private static func convertToGeoJSON(_ gpx: GPXFile) throws -> FeatureCollection {
        var features: [Feature] = []

        for wp in gpx.waypoints {
            features.append(waypointToFeature(wp, gpxType: "wpt"))
        }

        for rte in gpx.routes {
            features.append(routeToFeature(rte))
        }

        for trk in gpx.tracks {
            features.append(trackToFeature(trk))
        }

        var fc = FeatureCollection(features)

        if let meta = gpx.metadata {
            fc.foreignMembers = metadataToForeignMembers(meta)
        }

        return fc
    }

    // MARK: - FeatureCollection → GPXFile

    private static func convertFromGeoJSON(_ fc: FeatureCollection) throws -> GPXFile {
        let metadata = metadataFromForeignMembers(fc.foreignMembers)
        var waypoints: [GPXWaypoint] = []
        var routes: [GPXRoute] = []
        var tracks: [GPXTrack] = []

        for feature in fc.features {
            let gpxType: String?
            if let type = feature.properties["gpx_type"] as? String {
                gpxType = type
            }
            else {
                gpxType = inferGPXType(from: feature.geometry)
            }

            switch gpxType {
            case "wpt":
                if let point = feature.geometry as? Point {
                    waypoints.append(try featureToWaypoint(feature, point: point))
                }
            case "rte":
                if let lineString = feature.geometry as? LineString {
                    routes.append(try featureToRoute(feature, lineString: lineString))
                }
            case "trk":
                if let multiLine = feature.geometry as? MultiLineString {
                    tracks.append(try featureToTrack(feature, multiLine: multiLine))
                }
            default:
                // Try to infer from the geometry type
                switch feature.geometry {
                case let point as Point:
                    waypoints.append(try featureToWaypoint(feature, point: point))
                case let lineString as LineString:
                    routes.append(try featureToRoute(feature, lineString: lineString))
                case let multiLine as MultiLineString:
                    tracks.append(try featureToTrack(feature, multiLine: multiLine))
                default:
                    break
                }
            }
        }

        return GPXFile(
            metadata: metadata,
            waypoints: waypoints,
            routes: routes,
            tracks: tracks)
    }

    // MARK: - Waypoint conversion

    private static func waypointToFeature(
        _ wp: GPXWaypoint,
        gpxType: String
    ) -> Feature {
        let coordinate = Coordinate3D(
            latitude: wp.latitude,
            longitude: wp.longitude,
            altitude: wp.elevation)
        var feature = Feature(Point(coordinate))
        feature.properties["gpx_type"] = gpxType

        if let time = wp.time { feature.properties["time"] = GPXDateFormatter.format(time) }
        if let v = wp.magneticVariation { feature.properties["magvar"] = v }
        if let v = wp.geoidHeight { feature.properties["geoidheight"] = v }
        if let v = wp.name { feature.properties["name"] = v }
        if let v = wp.comment { feature.properties["cmt"] = v }
        if let v = wp.description { feature.properties["desc"] = v }
        if let v = wp.source { feature.properties["src"] = v }
        if !wp.links.isEmpty { feature.properties["link"] = linksToDicts(wp.links) }
        if let v = wp.symbol { feature.properties["sym"] = v }
        if let v = wp.type { feature.properties["type"] = v }
        if let v = wp.fix { feature.properties["fix"] = v.rawValue }
        if let v = wp.satellites { feature.properties["sat"] = v }
        if let v = wp.horizontalDilution { feature.properties["hdop"] = v }
        if let v = wp.verticalDilution { feature.properties["vdop"] = v }
        if let v = wp.positionDilution { feature.properties["pdop"] = v }
        if let v = wp.ageOfDGPSData { feature.properties["ageofdgpsdata"] = v }
        if let v = wp.dgpsid { feature.properties["dgpsid"] = v }
        if let v = wp.course { feature.properties["course"] = v }
        if let v = wp.speed { feature.properties["speed"] = v }

        if !wp.extensions.isEmpty {
            feature.properties["extensions"] = wp.extensions as [String: Sendable]
        }

        return feature
    }

    private static func featureToWaypoint(
        _ feature: Feature,
        point: Point
    ) throws -> GPXWaypoint {
        let props = feature.properties
        let coord = point.coordinate
        try validateGPSCoordinate(coord)

        let links: [GPXLink] = extractLinks(from: props)
        let extensions: [String: [String: Sendable]] = extractExtensions(from: props)

        return GPXWaypoint(
            latitude: coord.latitude,
            longitude: coord.longitude,
            elevation: coord.altitude ?? doubleProp(props, "ele"),
            time: dateProp(props, "time"),
            magneticVariation: doubleProp(props, "magvar"),
            geoidHeight: doubleProp(props, "geoidheight"),
            name: stringProp(props, "name"),
            comment: stringProp(props, "cmt"),
            description: stringProp(props, "desc"),
            source: stringProp(props, "src"),
            links: links,
            symbol: stringProp(props, "sym"),
            type: stringProp(props, "type"),
            fix: GPSFixType(rawValue: stringProp(props, "fix") ?? ""),
            satellites: intProp(props, "sat"),
            horizontalDilution: doubleProp(props, "hdop"),
            verticalDilution: doubleProp(props, "vdop"),
            positionDilution: doubleProp(props, "pdop"),
            ageOfDGPSData: doubleProp(props, "ageofdgpsdata"),
            dgpsid: intProp(props, "dgpsid"),
            course: doubleProp(props, "course"),
            speed: doubleProp(props, "speed"),
            extensions: extensions)
    }

    // MARK: - Route conversion

    private static func routeToFeature(_ rte: GPXRoute) -> Feature {
        let coordinates = rte.points.map {
            Coordinate3D(latitude: $0.latitude,
                         longitude: $0.longitude,
                         altitude: $0.elevation)
        }
        var feature = Feature(LineString(unchecked: coordinates))
        feature.properties["gpx_type"] = "rte"

        if let v = rte.name { feature.properties["name"] = v }
        if let v = rte.comment { feature.properties["cmt"] = v }
        if let v = rte.description { feature.properties["desc"] = v }
        if let v = rte.source { feature.properties["src"] = v }
        if !rte.links.isEmpty { feature.properties["link"] = linksToDicts(rte.links) }
        if let v = rte.number { feature.properties["number"] = v }
        if let v = rte.type { feature.properties["type"] = v }

        if !rte.extensions.isEmpty {
            feature.properties["extensions"] = rte.extensions as [String: Sendable]
        }

        // Per-rtept data is accumulated into parallel arrays aligned to the
        // LineString coordinates. Arrays are only stored when they contain
        // at least one non-nil value, mirroring the track convention.
        var times: [Double?] = []
        var names: [String?] = []
        var comments: [String?] = []
        var descriptions: [String?] = []
        var sources: [String?] = []
        var symbols: [String?] = []
        var types: [String?] = []
        var links: [[[String: String]]] = []
        var rteExtensions: [[String: Sendable]] = []

        for wp in rte.points {
            times.append(wp.time?.timeIntervalSinceReferenceDate)
            names.append(wp.name)
            comments.append(wp.comment)
            descriptions.append(wp.description)
            sources.append(wp.source)
            symbols.append(wp.symbol)
            types.append(wp.type)
            links.append(linksToDicts(wp.links))
            if wp.extensions.isEmpty {
                rteExtensions.append([:])
            }
            else {
                rteExtensions.append(wp.extensions as [String: Sendable])
            }
        }

        if times.contains(where: { $0 != nil }) { feature.properties["gpx_route_times"] = times }
        if names.contains(where: { $0 != nil }) { feature.properties["gpx_route_names"] = names }
        if comments.contains(where: { $0 != nil }) { feature.properties["gpx_route_comments"] = comments }
        if descriptions.contains(where: { $0 != nil }) { feature.properties["gpx_route_descriptions"] = descriptions }
        if sources.contains(where: { $0 != nil }) { feature.properties["gpx_route_sources"] = sources }
        if symbols.contains(where: { $0 != nil }) { feature.properties["gpx_route_symbols"] = symbols }
        if types.contains(where: { $0 != nil }) { feature.properties["gpx_route_types"] = types }
        if links.contains(where: { !$0.isEmpty }) {
            feature.properties["gpx_route_links"] = links as [[[String: String]]]
        }
        if rteExtensions.contains(where: { !$0.isEmpty }) {
            feature.properties["gpx_route_extensions"] = rteExtensions as [[String: Sendable]]
        }

        return feature
    }

    private static func featureToRoute(
        _ feature: Feature,
        lineString: LineString
    ) throws -> GPXRoute {
        let props = feature.properties
        let links: [GPXLink] = extractLinks(from: props)
        let extensions: [String: [String: Sendable]] = extractExtensions(from: props)

        // Per-rtept parallel arrays (aligned to coordinate indices). Each
        // array is optional and may be shorter than the coordinate list;
        // out-of-range or missing entries yield nil/empty values.
        let routeTimes = props["gpx_route_times"] as? [Double?]
        let routeNames = props["gpx_route_names"] as? [String?]
        let routeComments = props["gpx_route_comments"] as? [String?]
        let routeDescriptions = props["gpx_route_descriptions"] as? [String?]
        let routeSources = props["gpx_route_sources"] as? [String?]
        let routeSymbols = props["gpx_route_symbols"] as? [String?]
        let routeTypes = props["gpx_route_types"] as? [String?]
        let routeLinks = props["gpx_route_links"] as? [[[String: String]]]
        let routeExtensions = props["gpx_route_extensions"] as? [[String: Sendable]]

        let points = try lineString.coordinates.enumerated().map { idx, coord -> GPXWaypoint in
            try validateGPSCoordinate(coord)

            // Extensions
            var pointExtensions: [String: [String: Sendable]] = [:]
            if let arr = routeExtensions, idx < arr.count, !arr[idx].isEmpty {
                for (prefix, value) in arr[idx] {
                    if let nsDict = value as? [String: Sendable] {
                        pointExtensions[prefix] = nsDict
                    }
                }
            }

            // Links
            var pointLinks: [GPXLink] = []
            if let arr = routeLinks, idx < arr.count, !arr[idx].isEmpty {
                pointLinks = arr[idx].compactMap { dictLink($0) }
            }

            return GPXWaypoint(
                latitude: coord.latitude,
                longitude: coord.longitude,
                elevation: coord.altitude,
                time: routeTimes.flatMap { idx < $0.count ? $0[idx] : nil }
                    .map { Date(timeIntervalSinceReferenceDate: $0) },
                name: routeNames.flatMap { idx < $0.count ? $0[idx] : nil },
                comment: routeComments.flatMap { idx < $0.count ? $0[idx] : nil },
                description: routeDescriptions.flatMap { idx < $0.count ? $0[idx] : nil },
                source: routeSources.flatMap { idx < $0.count ? $0[idx] : nil },
                links: pointLinks,
                symbol: routeSymbols.flatMap { idx < $0.count ? $0[idx] : nil },
                type: routeTypes.flatMap { idx < $0.count ? $0[idx] : nil },
                extensions: pointExtensions)
        }

        return GPXRoute(
            name: stringProp(props, "name"),
            comment: stringProp(props, "cmt"),
            description: stringProp(props, "desc"),
            source: stringProp(props, "src"),
            links: links,
            number: intProp(props, "number"),
            type: stringProp(props, "type"),
            points: points,
            extensions: extensions)
    }

    // MARK: - Track conversion

    private static func trackToFeature(_ trk: GPXTrack) -> Feature {
        let lineStrings: [LineString] = trk.segments.map { segment in
            let coords = segment.map {
                Coordinate3D(latitude: $0.latitude,
                             longitude: $0.longitude,
                             altitude: $0.elevation)
            }
            return LineString(unchecked: coords)
        }

        var feature = Feature(MultiLineString(unchecked: lineStrings))
        feature.properties["gpx_type"] = "trk"

        if let v = trk.name { feature.properties["name"] = v }
        if let v = trk.comment { feature.properties["cmt"] = v }
        if let v = trk.description { feature.properties["desc"] = v }
        if let v = trk.source { feature.properties["src"] = v }
        if !trk.links.isEmpty { feature.properties["link"] = linksToDicts(trk.links) }
        if let v = trk.number { feature.properties["number"] = v }
        if let v = trk.type { feature.properties["type"] = v }

        if !trk.extensions.isEmpty {
            feature.properties["extensions"] = trk.extensions as [String: Sendable]
        }

        // Accumulate per-point sensor arrays from track segment waypoints
        // Arrays are aligned to coordinate index — missing values are nil.
        //
        // `course` and `speed` come from two sources:
        //   - GPX 1.1 gpxtpx TrackPointExtension v2 (`<gpxtpx:course>`, `<gpxtpx:speed>`)
        //   - GPX 1.0 flat track-point elements (`<course>`, `<speed>`)
        // The gpxtpx value wins when both are present (it is the newer spec);
        // otherwise the GPX 1.0 flat value is used. On write, both are emitted
        // as gpxtpx extensions (we always write GPX 1.1), upgrading 1.0 data.
        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var courses: [Double?] = []
        var temperatures: [Double?] = []
        var waterTemperatures: [Double?] = []
        var depths: [Double?] = []
        var bearings: [Double?] = []
        var elevations: [Double?] = []
        var times: [Double?] = []  // TimeInterval since reference date
        var names: [String?] = []
        var comments: [String?] = []
        var descriptions: [String?] = []
        var sources: [String?] = []
        var symbols: [String?] = []
        var types: [String?] = []
        var pointLinks: [[[String: String]]] = []
        var rawExtensions: [[String: Sendable]] = []
        var quality: [[String: Sendable]] = []

        for wp in trk.segments.flatMap({ $0 }) {
            times.append(wp.time?.timeIntervalSinceReferenceDate)
            elevations.append(wp.elevation)
            names.append(wp.name)
            comments.append(wp.comment)
            descriptions.append(wp.description)
            sources.append(wp.source)
            symbols.append(wp.symbol)
            types.append(wp.type)
            pointLinks.append(linksToDicts(wp.links))
            rawExtensions.append(rawTrackPointExtensions(wp.extensions))
            quality.append(trackPointQuality(wp))

            let ext = wp.extensions["gpxtpx"]
            heartRates.append(extensionInt(ext, "hr"))
            cadences.append(extensionInt(ext, "cad"))
            powers.append(extensionInt(ext, "power"))
            speeds.append(extensionDouble(ext, "speed") ?? wp.speed)
            courses.append(extensionDouble(ext, "course") ?? wp.course)
            temperatures.append(extensionDouble(ext, "atemp"))
            waterTemperatures.append(extensionDouble(ext, "wtemp"))
            depths.append(extensionDouble(ext, "depth"))
            bearings.append(extensionDouble(ext, "bearing"))
        }

        // Only store arrays that have at least one non-nil value
        if heartRates.contains(where: { $0 != nil }) { feature.properties["gpx_heart_rates"] = heartRates }
        if cadences.contains(where: { $0 != nil }) { feature.properties["gpx_cadences"] = cadences }
        if powers.contains(where: { $0 != nil }) { feature.properties["gpx_powers"] = powers }
        if speeds.contains(where: { $0 != nil }) { feature.properties["gpx_speeds"] = speeds }
        if courses.contains(where: { $0 != nil }) { feature.properties["gpx_courses"] = courses }
        if temperatures.contains(where: { $0 != nil }) { feature.properties["gpx_air_temperatures"] = temperatures }
        if waterTemperatures.contains(where: { $0 != nil }) {
            feature.properties["gpx_water_temperatures"] = waterTemperatures
        }
        if depths.contains(where: { $0 != nil }) { feature.properties["gpx_depths"] = depths }
        if bearings.contains(where: { $0 != nil }) { feature.properties["gpx_bearings"] = bearings }
        if elevations.contains(where: { $0 != nil }) { feature.properties["gpx_elevations"] = elevations }
        if times.contains(where: { $0 != nil }) { feature.properties["gpx_times"] = times }
        if names.contains(where: { $0 != nil }) { feature.properties["gpx_track_names"] = names }
        if comments.contains(where: { $0 != nil }) { feature.properties["gpx_track_comments"] = comments }
        if descriptions.contains(where: { $0 != nil }) {
            feature.properties["gpx_track_descriptions"] = descriptions
        }
        if sources.contains(where: { $0 != nil }) { feature.properties["gpx_track_sources"] = sources }
        if symbols.contains(where: { $0 != nil }) { feature.properties["gpx_track_symbols"] = symbols }
        if types.contains(where: { $0 != nil }) { feature.properties["gpx_track_types"] = types }
        if pointLinks.contains(where: { !$0.isEmpty }) {
            feature.properties["gpx_track_links"] = pointLinks
        }
        if rawExtensions.contains(where: { !$0.isEmpty }) {
            feature.properties["gpx_track_point_extensions"] = rawExtensions
        }
        if quality.contains(where: { !$0.isEmpty }) {
            feature.properties["gpx_track_point_quality"] = quality
        }

        return feature
    }

    private static func featureToTrack(
        _ feature: Feature,
        multiLine: MultiLineString
    ) throws -> GPXTrack {
        let props = feature.properties
        let links: [GPXLink] = extractLinks(from: props)
        let extensions: [String: [String: Sendable]] = extractExtensions(from: props)

        let times = props["gpx_times"] as? [Double?]
        let heartRates = props["gpx_heart_rates"] as? [Int?]
        let cadences = props["gpx_cadences"] as? [Int?]
        let powers = props["gpx_powers"] as? [Int?]
        let speeds = props["gpx_speeds"] as? [Double?]
        let courses = props["gpx_courses"] as? [Double?]
        let temperatures = props["gpx_air_temperatures"] as? [Double?]
        let waterTemperatures = props["gpx_water_temperatures"] as? [Double?]
        let depths = props["gpx_depths"] as? [Double?]
        let bearings = props["gpx_bearings"] as? [Double?]
        let names = props["gpx_track_names"] as? [String?]
        let comments = props["gpx_track_comments"] as? [String?]
        let descriptions = props["gpx_track_descriptions"] as? [String?]
        let sources = props["gpx_track_sources"] as? [String?]
        let symbols = props["gpx_track_symbols"] as? [String?]
        let types = props["gpx_track_types"] as? [String?]
        let pointLinks = props["gpx_track_links"] as? [[[String: String]]]
        let rawExtensions = props["gpx_track_point_extensions"] as? [[String: Sendable]]
        let quality = props["gpx_track_point_quality"] as? [[String: Sendable]]

        var pointIndex = 0
        let segments = try multiLine.lineStrings.map { lineString in
            try lineString.coordinates.map { coord -> GPXWaypoint in
                try validateGPSCoordinate(coord)
                let idx = pointIndex
                pointIndex += 1

                let time = optionalValue(times, at: idx)
                    .map { Date(timeIntervalSinceReferenceDate: $0) }

                var pointExtensions = extensionDictionary(
                    from: optionalValue(rawExtensions, at: idx))

                var gpxtpx = pointExtensions["gpxtpx"] ?? [:]
                if let v = optionalValue(heartRates, at: idx) { gpxtpx["hr"] = v }
                if let v = optionalValue(cadences, at: idx) { gpxtpx["cad"] = v }
                if let v = optionalValue(powers, at: idx) { gpxtpx["power"] = v }
                if let v = optionalValue(speeds, at: idx) { gpxtpx["speed"] = v }
                if let v = optionalValue(courses, at: idx) { gpxtpx["course"] = v }
                if let v = optionalValue(temperatures, at: idx) { gpxtpx["atemp"] = v }
                if let v = optionalValue(waterTemperatures, at: idx) { gpxtpx["wtemp"] = v }
                if let v = optionalValue(depths, at: idx) { gpxtpx["depth"] = v }
                if let v = optionalValue(bearings, at: idx) { gpxtpx["bearing"] = v }
                if !gpxtpx.isEmpty { pointExtensions["gpxtpx"] = gpxtpx }

                let pointLinkValues = optionalValue(pointLinks, at: idx) ?? []
                let pointGPXLinks = pointLinkValues.compactMap { dictLink($0) }
                let pointQuality = quality.flatMap {
                    $0.indices.contains(idx) ? $0[idx] : nil
                } ?? [:]

                return GPXWaypoint(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    elevation: coord.altitude,
                    time: time,
                    magneticVariation: doubleProp(pointQuality, "magvar"),
                    geoidHeight: doubleProp(pointQuality, "geoidheight"),
                    name: optionalValue(names, at: idx),
                    comment: optionalValue(comments, at: idx),
                    description: optionalValue(descriptions, at: idx),
                    source: optionalValue(sources, at: idx),
                    links: pointGPXLinks,
                    symbol: optionalValue(symbols, at: idx),
                    type: optionalValue(types, at: idx),
                    fix: stringProp(pointQuality, "fix").flatMap(GPSFixType.init(rawValue:)),
                    satellites: intProp(pointQuality, "sat"),
                    horizontalDilution: doubleProp(pointQuality, "hdop"),
                    verticalDilution: doubleProp(pointQuality, "vdop"),
                    positionDilution: doubleProp(pointQuality, "pdop"),
                    ageOfDGPSData: doubleProp(pointQuality, "ageofdgpsdata"),
                    dgpsid: intProp(pointQuality, "dgpsid"),
                    extensions: pointExtensions)
            }
        }

        return GPXTrack(
            name: stringProp(props, "name"),
            comment: stringProp(props, "cmt"),
            description: stringProp(props, "desc"),
            source: stringProp(props, "src"),
            links: links,
            number: intProp(props, "number"),
            type: stringProp(props, "type"),
            segments: segments,
            extensions: extensions)
    }

    /// GPX extension keys that are projected into typed track-point arrays.
    /// Everything else is kept verbatim so vendor extensions survive a
    /// read → write → read cycle.
    private static let typedGPXTrackExtensionKeys: Set<String> = [
        "hr", "cad", "power", "speed", "course", "atemp",
        "wtemp", "depth", "bearing",
    ]

    private static func rawTrackPointExtensions(
        _ extensions: [String: [String: Sendable]]
    ) -> [String: Sendable] {
        var result: [String: Sendable] = [:]
        for (prefix, namespace) in extensions {
            if prefix == "gpxtpx" {
                let remaining = namespace.filter { !typedGPXTrackExtensionKeys.contains($0.key) }
                if !remaining.isEmpty {
                    result[prefix] = remaining
                }
            }
            else {
                result[prefix] = namespace
            }
        }
        return result
    }

    private static func trackPointQuality(_ wp: GPXWaypoint) -> [String: Sendable] {
        var quality: [String: Sendable] = [:]
        if let v = wp.magneticVariation { quality["magvar"] = v }
        if let v = wp.geoidHeight { quality["geoidheight"] = v }
        if let v = wp.fix { quality["fix"] = v.rawValue }
        if let v = wp.satellites { quality["sat"] = v }
        if let v = wp.horizontalDilution { quality["hdop"] = v }
        if let v = wp.verticalDilution { quality["vdop"] = v }
        if let v = wp.positionDilution { quality["pdop"] = v }
        if let v = wp.ageOfDGPSData { quality["ageofdgpsdata"] = v }
        if let v = wp.dgpsid { quality["dgpsid"] = v }
        return quality
    }

    private static func extensionDictionary(
        from raw: [String: Sendable]?
    ) -> [String: [String: Sendable]] {
        guard let raw else { return [:] }
        var result: [String: [String: Sendable]] = [:]
        for (prefix, value) in raw {
            if let namespace = value as? [String: Sendable] {
                result[prefix] = namespace
            }
        }
        return result
    }

    private static func optionalValue<T>(_ values: [T?]?, at index: Int) -> T? {
        guard let values, values.indices.contains(index) else { return nil }
        return values[index]
    }

    // MARK: - Metadata conversion

    private static func metadataToForeignMembers(_ meta: GPXMetadata) -> [String: Sendable] {
        var members: [String: Sendable] = [:]

        if let v = meta.name { members["gpx_name"] = v }
        if let v = meta.desc { members["gpx_desc"] = v }
        if let v = meta.keywords { members["gpx_keywords"] = v }
        if let time = meta.time { members["gpx_time"] = GPXDateFormatter.format(time) }

        if let author = meta.author {
            var authorDict: [String: Sendable] = [:]
            if let n = author.name { authorDict["name"] = n }
            if let e = author.email { authorDict["email"] = e }
            if let link = author.link {
                authorDict["link"] = linkToDict(link) as Sendable
            }
            members["gpx_author"] = authorDict as Sendable
        }

        if let cr = meta.copyright {
            var crDict: [String: Sendable] = [:]
            crDict["author"] = cr.author
            if let year = cr.year { crDict["year"] = year }
            if let license = cr.license { crDict["license"] = license }
            members["gpx_copyright"] = crDict as Sendable
        }

        if !meta.links.isEmpty {
            members["gpx_link"] = linksToDicts(meta.links) as Sendable
        }

        if let bounds = meta.bounds {
            members["gpx_bounds"] = [
                "minlat": bounds.southWest.latitude,
                "minlon": bounds.southWest.longitude,
                "maxlat": bounds.northEast.latitude,
                "maxlon": bounds.northEast.longitude,
            ] as [String: Sendable]
        }

        return members
    }

    private static let metadataForeignMemberKeys: Set<String> = [
        "gpx_name", "gpx_desc", "gpx_author", "gpx_copyright",
        "gpx_link", "gpx_time", "gpx_keywords", "gpx_bounds",
    ]

    private static func metadataFromForeignMembers(_ members: [String: Sendable]) -> GPXMetadata? {
        guard members.keys.contains(where: { metadataForeignMemberKeys.contains($0) }) else {
            return nil
        }

        let boundsDict = members["gpx_bounds"] as? [String: Sendable]
        let bounds: BoundingBox? = boundsDict.flatMap {
            let minlat = ($0["minlat"] as? Double) ?? ($0["minlat"] as? Int).map(Double.init)
            let minlon = ($0["minlon"] as? Double) ?? ($0["minlon"] as? Int).map(Double.init)
            let maxlat = ($0["maxlat"] as? Double) ?? ($0["maxlat"] as? Int).map(Double.init)
            let maxlon = ($0["maxlon"] as? Double) ?? ($0["maxlon"] as? Int).map(Double.init)
            guard let minlat, let minlon, let maxlat, let maxlon else { return nil }
            return BoundingBox(
                southWest: Coordinate3D(latitude: minlat, longitude: minlon),
                northEast: Coordinate3D(latitude: maxlat, longitude: maxlon))
        }

        let authorDict = members["gpx_author"] as? [String: Sendable]
        let author: GPXPerson? = authorDict.map {
            GPXPerson(
                name: $0["name"] as? String,
                email: $0["email"] as? String,
                link: dictLink($0["link"] as? [String: String]))
        }

        let crDict = members["gpx_copyright"] as? [String: Sendable]
        let cr: GPXCopyright? = crDict.flatMap {
            guard let crAuthor = $0["author"] as? String else { return nil }
            return GPXCopyright(
                author: crAuthor,
                year: $0["year"] as? Int,
                license: $0["license"] as? String)
        }

        let links: [GPXLink]
        if let linkData = members["gpx_link"] {
            if let dicts = linkData as? [[String: String]] {
                links = dicts.compactMap { dictLink($0) }
            }
            else if let dict = linkData as? [String: String] {
                links = [dictLink(dict)].compactMap { $0 }
            }
            else {
                links = []
            }
        }
        else {
            links = []
        }

        return GPXMetadata(
            name: members["gpx_name"] as? String,
            desc: members["gpx_desc"] as? String,
            author: author,
            copyright: cr,
            links: links,
            time: dateProp(members, "gpx_time"),
            keywords: members["gpx_keywords"] as? String,
            bounds: bounds)
    }

    // MARK: - Helpers — property extraction

    private static func stringProp(_ props: [String: Sendable], _ key: String) -> String? {
        props[key] as? String
    }

    /// Extracts a Double from an extension dict, tolerating Int values.
    /// The parser's `inferExtensionValue` converts whole-number Doubles to
    /// Int (e.g. `45.0` → `Int(45)`), so `as? Double` alone is unsafe for
    /// numeric extension fields like `speed`, `course`, and `atemp`.
    private static func extensionDouble(_ dict: [String: Sendable]?, _ key: String) -> Double? {
        guard let val = dict?[key] else { return nil }
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        if let s = val as? String { return Double(s) }
        return nil
    }

    private static func extensionInt(_ dict: [String: Sendable]?, _ key: String) -> Int? {
        guard let val = dict?[key] else { return nil }
        if let i = val as? Int { return i }
        if let d = val as? Double { return Int(d) }
        if let s = val as? String { return Int(s) }
        return nil
    }

    private static func doubleProp(_ props: [String: Sendable], _ key: String) -> Double? {
        if let d = props[key] as? Double { return d }
        if let i = props[key] as? Int { return Double(i) }
        if let s = props[key] as? String { return Double(s) }
        return nil
    }

    private static func intProp(_ props: [String: Sendable], _ key: String) -> Int? {
        if let i = props[key] as? Int { return i }
        if let d = props[key] as? Double { return Int(d) }
        if let s = props[key] as? String { return Int(s) }
        return nil
    }

    private static func dateProp(_ props: [String: Sendable], _ key: String) -> Date? {
        if let date = props[key] as? Date { return date }
        guard let s = props[key] as? String else { return nil }
        return GPXDateFormatter.parse(s)
    }

    // MARK: - Helpers — links

    private static func linksToDicts(_ links: [GPXLink]) -> [[String: String]] {
        links.map { linkToDict($0) }
    }

    private static func linkToDict(_ link: GPXLink) -> [String: String] {
        var dict: [String: String] = ["href": link.href]
        if let text = link.text { dict["text"] = text }
        if let type = link.type { dict["type"] = type }
        return dict
    }

    private static func dictLink(_ dict: [String: String]?) -> GPXLink? {
        guard let dict, let href = dict["href"] else { return nil }
        return GPXLink(href: href, text: dict["text"], type: dict["type"])
    }

    private static func extractLinks(from props: [String: Sendable]) -> [GPXLink] {
        guard let linkData = props["link"] else { return [] }

        if let dicts = linkData as? [[String: String]] {
            return dicts.compactMap { dictLink($0) }
        }
        if let dict = linkData as? [String: String] {
            return [dictLink(dict)].compactMap { $0 }
        }
        return []
    }

    // MARK: - Helpers — extensions

    private static func extractExtensions(
        from props: [String: Sendable]
    ) -> [String: [String: Sendable]] {
        guard let raw = props["extensions"] as? [String: Sendable] else { return [:] }

        var result: [String: [String: Sendable]] = [:]
        for (prefix, value) in raw {
            if let nsDict = value as? [String: Sendable] {
                result[prefix] = nsDict
            }
        }
        return result
    }

    // MARK: - Helpers — misc

    private static func validateGPSCoordinate(_ coordinate: Coordinate3D) throws {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90.0 ... 90.0).contains(coordinate.latitude),
              (-180.0 ... 180.0).contains(coordinate.longitude)
        else {
            throw GPXError.invalidCoordinate(
                detail: "lat='\(coordinate.latitude)' lon='\(coordinate.longitude)'")
        }
        if let altitude = coordinate.altitude, !altitude.isFinite {
            throw GPXError.invalidCoordinate(
                detail: "non-finite altitude at lat='\(coordinate.latitude)' lon='\(coordinate.longitude)'")
        }
    }

    private static func inferGPXType(from geometry: GeoJsonGeometry?) -> String? {
        switch geometry?.type {
        case .point: "wpt"
        case .lineString: "rte"
        case .multiLineString: "trk"
        default: nil
        }
    }

}
