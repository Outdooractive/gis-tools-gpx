import Foundation
import GISTools

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

    /// Reconstructs a track ``Feature`` from Point features produced by
    /// ``Feature/gpxPointFeatures()``.
    ///
    /// Non-Point features are silently skipped. gpxtpx extension data
    /// (hr, cad, power, speed, atemp) is re-accumulated into per-point
    /// arrays on the returned track Feature.
    ///
    /// - Returns: A `Feature<MultiLineString>` with per-point sensor
    ///            arrays, or `nil` if no Point features were found.
    public func gpxTrackFromPointFeatures() -> Feature? {
        let pointFeatures = features.filter { $0.geometry is Point }
        guard !pointFeatures.isEmpty else { return nil }

        let coords = pointFeatures.map { ($0.geometry as! Point).coordinate }
        let multiLine = MultiLineString(unchecked: [LineString(unchecked: coords)])

        var feature = Feature(multiLine)
        feature.properties["gpx_type"] = "trk"

        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var temperatures: [Double?] = []
        var elevations: [Double?] = []
        var times: [Double?] = []

        for pf in pointFeatures {
            let ext = pf.properties["extensions"] as? [String: Sendable]
            let gpxtpx = ext?["gpxtpx"] as? [String: Sendable]
            heartRates.append(gpxtpx?["hr"] as? Int)
            cadences.append(gpxtpx?["cad"] as? Int)
            powers.append(gpxtpx?["power"] as? Int)
            speeds.append(gpxtpx?["speed"] as? Double)
            temperatures.append(gpxtpx?["atemp"] as? Double)
            elevations.append(pf.properties["ele"] as? Double)
            times.append((pf.properties["time"] as? Date)?.timeIntervalSinceReferenceDate)
        }

        if heartRates.contains(where: { $0 != nil }) { feature.properties["gpx_heart_rates"] = heartRates }
        if cadences.contains(where: { $0 != nil }) { feature.properties["gpx_cadences"] = cadences }
        if powers.contains(where: { $0 != nil }) { feature.properties["gpx_powers"] = powers }
        if speeds.contains(where: { $0 != nil }) { feature.properties["gpx_speeds"] = speeds }
        if temperatures.contains(where: { $0 != nil }) { feature.properties["gpx_air_temperatures"] = temperatures }
        if elevations.contains(where: { $0 != nil }) { feature.properties["gpx_elevations"] = elevations }
        if times.contains(where: { $0 != nil }) { feature.properties["gpx_times"] = times }

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
