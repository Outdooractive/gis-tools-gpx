import Foundation
import GISTools

// MARK: - FeatureCollection convenience extensions

extension FeatureCollection {

    /// Creates a `FeatureCollection` from a GPX file.
    ///
    /// - Parameter gpx: The URL of the GPX file.
    public init?(gpx url: URL) {
        guard let fc = try? GPXCoder.read(from: url) else { return nil }
        self = fc
    }

    /// Creates a `FeatureCollection` from GPX data.
    ///
    /// - Parameter gpxData: The raw GPX data.
    public init?(gpxData: Data) {
        guard let fc = try? GPXCoder.read(from: gpxData) else { return nil }
        self = fc
    }

    /// Returns the receiver serialised as GPX data.
    ///
    /// - Parameter creator: The `creator` attribute value (default `"GISToolsGPX"`).
    /// - Returns: The GPX data.
    /// - Throws: ``GPXError`` if serialization fails.
    public func gpxData(creator: String = "GISToolsGPX") throws -> Data {
        try GPXCoder.write(self, creator: creator)
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
        let data = try gpxData(creator: creator)
        do {
            try data.write(to: url)
        }
        catch {
            throw GPXError.fileWriteError(detail: error.localizedDescription)
        }
    }

}

// MARK: - FeatureCollection GPX convenience properties

extension FeatureCollection {

    // MARK: - Element type filtering

    /// Features that originated from `<wpt>` waypoint elements.
    public var gpxWaypoints: [Feature] {
        features.filter { $0.gpxType == .waypoint }
    }

    /// Features that originated from `<rte>` route elements.
    public var gpxRoutes: [Feature] {
        features.filter { $0.gpxType == .route }
    }

    /// Features that originated from `<trk>` track elements.
    public var gpxTracks: [Feature] {
        features.filter { $0.gpxType == .track }
    }

    // MARK: - Track reconstruction from point features

    /// Reconstructs a track `Feature` from Point features produced by
    /// `Feature.gpxPointFeatures()`.
    ///
    /// Non-Point features are silently skipped. Per-point times, elevations,
    /// sensor values, standard fields, links, raw extensions, and quality
    /// fields are re-accumulated into parallel arrays on the returned track
    /// Feature.
    ///
    /// - Returns: A `Feature<MultiLineString>` with per-point sensor
    ///            arrays, or `nil` if no Point features were found.
    public func gpxTrackFromPointFeatures() -> Feature? {
        let points: [(feature: Feature, point: Point)] = features.compactMap { feature in
            guard let point = feature.geometry as? Point else { return nil }
            return (feature, point)
        }
        guard !points.isEmpty else { return nil }

        let coords = points.map { $0.point.coordinate }
        let multiLine = MultiLineString(unchecked: [LineString(unchecked: coords)])

        var feature = Feature(multiLine)
        feature.properties["gpx_type"] = "trk"

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
        var times: [Double?] = []
        var names: [String?] = []
        var comments: [String?] = []
        var descriptions: [String?] = []
        var sources: [String?] = []
        var symbols: [String?] = []
        var types: [String?] = []
        var pointLinks: [[[String: String]]] = []
        var rawExtensions: [[String: Sendable]] = []
        var quality: [[String: Sendable]] = []

        for entry in points {
            let pf = entry.feature

            heartRates.append(pf.gpxHeartRate)
            cadences.append(pf.gpxCadence)
            powers.append(pf.gpxPower)
            speeds.append(pf.gpxSpeed)
            courses.append(pf.gpxCourse)
            temperatures.append(pf.gpxAirTemperature)
            waterTemperatures.append(pf.gpxWaterTemperature)
            depths.append(pf.gpxDepth)
            bearings.append(pf.gpxBearing)
            elevations.append(pf.gpxElevation ?? entry.point.coordinate.altitude)
            times.append(pf.gpxTime?.timeIntervalSinceReferenceDate)
            names.append(pf.gpxName)
            comments.append(pf.gpxComment)
            descriptions.append(pf.gpxDescription)
            sources.append(pf.gpxSource)
            symbols.append(pf.gpxSymbol)
            types.append(pf.gpxTypeName)
            pointLinks.append(pf.gpxLinks.map { link in
                var dict: [String: String] = ["href": link.href]
                if let text = link.text { dict["text"] = text }
                if let type = link.type { dict["type"] = type }
                return dict
            })
            rawExtensions.append(GPXTrackPointExtensionKey.raw(
                from: pf.properties["extensions"] as? [String: Sendable]))
            var fields: [String: Sendable] = [:]
            if let value = pf.gpxMagneticVariation { fields["magvar"] = value }
            if let value = pf.gpxGeoidHeight { fields["geoidheight"] = value }
            if let value = pf.gpxFix { fields["fix"] = value.rawValue }
            if let value = pf.gpxSatellites { fields["sat"] = value }
            if let value = pf.gpxHDOP { fields["hdop"] = value }
            if let value = pf.gpxVDOP { fields["vdop"] = value }
            if let value = pf.gpxPDOP { fields["pdop"] = value }
            if let value = pf.gpxAgeOfDGPSData { fields["ageofdgpsdata"] = value }
            if let value = pf.gpxDGPSID { fields["dgpsid"] = value }
            quality.append(fields)
        }

        if heartRates.contains(where: { $0 != nil }) { feature.properties["gpx_heart_rates"] = heartRates }
        if cadences.contains(where: { $0 != nil }) { feature.properties["gpx_cadences"] = cadences }
        if powers.contains(where: { $0 != nil }) { feature.properties["gpx_powers"] = powers }
        if speeds.contains(where: { $0 != nil }) { feature.properties["gpx_speeds"] = speeds }
        if courses.contains(where: { $0 != nil }) { feature.properties["gpx_courses"] = courses }
        if temperatures.contains(where: { $0 != nil }) {
            feature.properties["gpx_air_temperatures"] = temperatures
        }
        if waterTemperatures.contains(where: { $0 != nil }) {
            feature.properties["gpx_water_temperatures"] = waterTemperatures
        }
        if depths.contains(where: { $0 != nil }) { feature.properties["gpx_depths"] = depths }
        if bearings.contains(where: { $0 != nil }) { feature.properties["gpx_bearings"] = bearings }
        if elevations.contains(where: { $0 != nil }) {
            feature.properties["gpx_elevations"] = elevations
        }
        if times.contains(where: { $0 != nil }) { feature.properties["gpx_times"] = times }
        if names.contains(where: { $0 != nil }) { feature.properties["gpx_track_names"] = names }
        if comments.contains(where: { $0 != nil }) {
            feature.properties["gpx_track_comments"] = comments
        }
        if descriptions.contains(where: { $0 != nil }) {
            feature.properties["gpx_track_descriptions"] = descriptions
        }
        if sources.contains(where: { $0 != nil }) {
            feature.properties["gpx_track_sources"] = sources
        }
        if symbols.contains(where: { $0 != nil }) {
            feature.properties["gpx_track_symbols"] = symbols
        }
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

    // MARK: - Metadata

    /// The GPX file name from `<metadata><name>`.
    public var gpxMetadataName: String? {
        get { foreignMembers["gpx_name"] as? String }
        set { foreignMembers["gpx_name"] = newValue }
    }

    /// The GPX file description from `<metadata><desc>`.
    public var gpxMetadataDescription: String? {
        get { foreignMembers["gpx_desc"] as? String }
        set { foreignMembers["gpx_desc"] = newValue }
    }

    /// Keywords from `<metadata><keywords>`.
    public var gpxMetadataKeywords: String? {
        get { foreignMembers["gpx_keywords"] as? String }
        set { foreignMembers["gpx_keywords"] = newValue }
    }

    /// Timestamp from `<metadata><time>`.
    public var gpxMetadataTime: Date? {
        get {
            guard let s = foreignMembers["gpx_time"] as? String else { return nil }
            return GPXDateFormatter.parse(s)
        }
        set {
            if let date = newValue {
                foreignMembers["gpx_time"] = GPXDateFormatter.format(date)
            }
            else {
                foreignMembers["gpx_time"] = nil
            }
        }
    }

    /// Author from `<metadata><author>`.
    public var gpxMetadataAuthor: GPXPerson? {
        get {
            guard let dict = foreignMembers["gpx_author"] as? [String: Sendable] else { return nil }
            var link: GPXLink?
            if let linkDict = dict["link"] as? [String: String],
               let href = linkDict["href"]
            {
                link = GPXLink(href: href, text: linkDict["text"], type: linkDict["type"])
            }
            return GPXPerson(
                name: dict["name"] as? String,
                email: dict["email"] as? String,
                link: link)
        }
        set {
            guard let person = newValue else {
                foreignMembers["gpx_author"] = nil
                return
            }
            var dict: [String: Sendable] = [:]
            if let n = person.name { dict["name"] = n }
            if let e = person.email { dict["email"] = e }
            if let link = person.link {
                var ld: [String: String] = ["href": link.href]
                if let t = link.text { ld["text"] = t }
                if let tp = link.type { ld["type"] = tp }
                dict["link"] = ld as Sendable
            }
            foreignMembers["gpx_author"] = dict as Sendable
        }
    }

    /// Copyright from `<metadata><copyright>`.
    public var gpxMetadataCopyright: GPXCopyright? {
        get {
            guard let dict = foreignMembers["gpx_copyright"] as? [String: Sendable],
                  let author = dict["author"] as? String
            else { return nil }
            return GPXCopyright(
                author: author,
                year: dict["year"] as? Int,
                license: dict["license"] as? String)
        }
        set {
            guard let cr = newValue else {
                foreignMembers["gpx_copyright"] = nil
                return
            }
            var dict: [String: Sendable] = ["author": cr.author]
            if let y = cr.year { dict["year"] = y }
            if let l = cr.license { dict["license"] = l }
            foreignMembers["gpx_copyright"] = dict as Sendable
        }
    }

    /// Links from `<metadata><link>`.
    public var gpxMetadataLinks: [GPXLink] {
        get {
            guard let linkData = foreignMembers["gpx_link"] else { return [] }
            if let dicts = linkData as? [[String: String]] {
                return dicts.compactMap { dict in
                    guard let href = dict["href"] else { return nil }
                    return GPXLink(href: href, text: dict["text"], type: dict["type"])
                }
            }
            if let dict = linkData as? [String: String],
               let href = dict["href"]
            {
                return [GPXLink(href: href, text: dict["text"], type: dict["type"])]
            }
            return []
        }
        set {
            if newValue.isEmpty {
                foreignMembers["gpx_link"] = nil
            }
            else {
                let dicts: [[String: String]] = newValue.map { link in
                    var d: [String: String] = ["href": link.href]
                    if let t = link.text { d["text"] = t }
                    if let tp = link.type { d["type"] = tp }
                    return d
                }
                foreignMembers["gpx_link"] = dicts
            }
        }
    }

    /// Geographic bounds from `<metadata><bounds>`.
    public var gpxMetadataBounds: BoundingBox? {
        get {
            guard let dict = foreignMembers["gpx_bounds"] as? [String: Sendable],
                  let minlat = (dict["minlat"] as? Double) ?? (dict["minlat"] as? Int).map(Double.init),
                  let minlon = (dict["minlon"] as? Double) ?? (dict["minlon"] as? Int).map(Double.init),
                  let maxlat = (dict["maxlat"] as? Double) ?? (dict["maxlat"] as? Int).map(Double.init),
                  let maxlon = (dict["maxlon"] as? Double) ?? (dict["maxlon"] as? Int).map(Double.init)
            else { return nil }
            return BoundingBox(
                southWest: Coordinate3D(latitude: minlat, longitude: minlon),
                northEast: Coordinate3D(latitude: maxlat, longitude: maxlon))
        }
        set {
            guard let bounds = newValue else {
                foreignMembers["gpx_bounds"] = nil
                return
            }
            foreignMembers["gpx_bounds"] = [
                "minlat": bounds.southWest.latitude,
                "minlon": bounds.southWest.longitude,
                "maxlat": bounds.northEast.latitude,
                "maxlon": bounds.northEast.longitude,
            ] as [String: Sendable]
        }
    }

}

// MARK: - Track point extension keys

/// Namespace for the gpxtpx keys that are projected into typed per-point
/// arrays. Kept out of the verbatim extension dictionary so typed arrays stay
/// authoritative on write.
private enum GPXTrackPointExtensionKey {

    static let typed: Set<String> = [
        "hr", "cad", "power", "speed", "course", "atemp",
        "wtemp", "depth", "bearing",
    ]

    /// Returns the extension dictionary without gpxtpx keys that have a typed
    /// counterpart. Other namespaces are preserved verbatim.
    static func raw(from extensions: [String: Sendable]?) -> [String: Sendable] {
        guard let extensions else { return [:] }
        var result: [String: Sendable] = [:]
        for (prefix, value) in extensions {
            guard let namespace = value as? [String: Sendable] else { continue }
            if prefix == "gpxtpx" {
                let remaining = namespace.filter { !typed.contains($0.key) }
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

}
