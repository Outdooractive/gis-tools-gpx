import Foundation
import GISTools

// MARK: - FeatureCollection convenience extensions

extension FeatureCollection {

    /// Creates a ``FeatureCollection`` from a GPX file.
    ///
    /// - Parameter gpx: The URL of the GPX file.
    public init?(gpx url: URL) {
        guard let fc = try? GPXCoder.read(from: url) else { return nil }
        self = fc
    }

    /// Writes the receiver as a GPX file.
    ///
    /// - Parameters:
    ///   - url: The output URL (must include `.gpx` extension).
    ///   - creator: The value for the `creator` attribute (default `"GISToolsGPX"`).
    public func writeGPX(
        to url: URL,
        creator: String = "GISToolsGPX"
    ) throws {
        try GPXCoder.write(self, to: url, creator: creator)
    }

}

// MARK: - GPXCoder

/// Reads and writes GPX 1.1 files (GPS Exchange Format).
///
/// GPX files contain waypoints (`<wpt>`), routes (`<rte>`), and tracks
/// (`<trk>`). This coder maps them to a ``FeatureCollection`` with:
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
/// GPX `<metadata>` is stored in ``FeatureCollection``'s `foreignMembers`.
public enum GPXCoder {

    // MARK: - Read

    /// Reads a GPX file and returns a ``FeatureCollection``.
    ///
    /// - Parameter url: The URL of the GPX file to read.
    /// - Returns: A ``FeatureCollection`` with the GPX data.
    /// - Throws: ``GPXError`` if the file cannot be read or parsed.
    public static func read(from url: URL) throws -> FeatureCollection {
        let gpx = try GPXParser.parse(url: url)
        return try convertToGeoJSON(gpx)
    }

    // MARK: - Write

    /// Writes a ``FeatureCollection`` as a GPX file.
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
        let gpx = try convertFromGeoJSON(featureCollection)
        let xml = GPXWriter.write(gpx, creator: creator)
        guard let data = xml.data(using: .utf8) else {
            throw GPXError.invalidEncoding
        }
        do {
            try data.write(to: url)
        }
        catch {
            throw GPXError.fileWriteError(detail: error.localizedDescription)
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
                    waypoints.append(featureToWaypoint(feature, point: point))
                }
            case "rte":
                if let lineString = feature.geometry as? LineString {
                    routes.append(featureToRoute(feature, lineString: lineString))
                }
            case "trk":
                if let multiLine = feature.geometry as? MultiLineString {
                    tracks.append(featureToTrack(feature, multiLine: multiLine))
                }
            default:
                // Try to infer from geometry type
                switch feature.geometry.type {
                case .point:
                    waypoints.append(featureToWaypoint(feature, point: feature.geometry as! Point))
                case .lineString:
                    routes.append(featureToRoute(feature, lineString: feature.geometry as! LineString))
                case .multiLineString:
                    tracks.append(featureToTrack(feature, multiLine: feature.geometry as! MultiLineString))
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
    ) -> GPXWaypoint {
        let props = feature.properties
        let coord = point.coordinate

        let links: [GPXLink] = extractLinks(from: props)
        let extensions: [String: [String: Sendable]] = extractExtensions(from: props)

        return GPXWaypoint(
            latitude: coord.latitude,
            longitude: coord.longitude,
            elevation: coord.altitude,
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

        return feature
    }

    private static func featureToRoute(
        _ feature: Feature,
        lineString: LineString
    ) -> GPXRoute {
        let props = feature.properties
        let links: [GPXLink] = extractLinks(from: props)
        let extensions: [String: [String: Sendable]] = extractExtensions(from: props)

        let points = lineString.coordinates.map { coord in
            GPXWaypoint(
                latitude: coord.latitude,
                longitude: coord.longitude,
                elevation: coord.altitude)
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
        var heartRates: [Int] = []
        var cadences: [Int] = []
        var powers: [Int] = []
        var gpxSpeeds: [Double] = []
        var temperatures: [Double] = []
        var elevations: [Double] = []
        var times: [Double] = []  // TimeInterval since reference date

        for segment in trk.segments {
            for wp in segment {
                if let t = wp.time { times.append(t.timeIntervalSinceReferenceDate) }
                if let e = wp.elevation { elevations.append(e) }
                if let ext = wp.extensions["gpxtpx"] {
                    if let hr = ext["hr"] as? Int { heartRates.append(hr) }
                    if let cad = ext["cad"] as? Int { cadences.append(cad) }
                    if let pw = ext["power"] as? Int { powers.append(pw) }
                    if let sp = ext["speed"] as? Double { gpxSpeeds.append(sp) }
                    if let tmp = ext["atemp"] as? Double { temperatures.append(tmp) }
                }
            }
        }

        if !heartRates.isEmpty { feature.properties["gpx_heart_rates"] = heartRates }
        if !cadences.isEmpty { feature.properties["gpx_cadences"] = cadences }
        if !powers.isEmpty { feature.properties["gpx_powers"] = powers }
        if !gpxSpeeds.isEmpty { feature.properties["gpx_speeds"] = gpxSpeeds }
        if !temperatures.isEmpty { feature.properties["gpx_air_temperatures"] = temperatures }
        if !elevations.isEmpty { feature.properties["gpx_elevations"] = elevations }
        if !times.isEmpty { feature.properties["gpx_times"] = times }

        return feature
    }

    private static func featureToTrack(
        _ feature: Feature,
        multiLine: MultiLineString
    ) -> GPXTrack {
        let props = feature.properties
        let links: [GPXLink] = extractLinks(from: props)
        let extensions: [String: [String: Sendable]] = extractExtensions(from: props)

        let segments = multiLine.lineStrings.map { lineString in
            lineString.coordinates.map { coord in
                GPXWaypoint(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    elevation: coord.altitude)
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

    private static func metadataFromForeignMembers(_ members: [String: Sendable]) -> GPXMetadata? {
        guard !members.isEmpty else { return nil }

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

        let links = extractLinks(from: members)

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

    private static func inferGPXType(from geometry: GeoJsonGeometry) -> String? {
        switch geometry.type {
        case .point: "wpt"
        case .lineString: "rte"
        case .multiLineString: "trk"
        default: nil
        }
    }

}
