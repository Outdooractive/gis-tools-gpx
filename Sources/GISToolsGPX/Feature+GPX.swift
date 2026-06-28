import Foundation
import GISTools

// MARK: - Feature GPX convenience properties

extension Feature {

    // MARK: - Element type

    /// The kind of GPX element this Feature represents.
    ///
    /// When set, the underlying `properties` dictionary is updated with
    /// the ``gpxType`` key so that subsequent ``FeatureCollection/writeGPX(to:creator:)``
    /// calls can reconstruct the correct GPX element.
    public var gpxType: GPXElementType? {
        get {
            guard let raw = properties["gpx_type"] as? String,
                  let type = GPXElementType(rawValue: raw)
            else { return nil }
            return type
        }
        set {
            properties["gpx_type"] = newValue?.rawValue
        }
    }

    // MARK: - Standard GPX properties

    /// The GPX name (`<name>`).
    public var gpxName: String? {
        get { properties["name"] as? String }
        set { properties["name"] = newValue }
    }

    /// The GPX comment (`<cmt>`).
    public var gpxComment: String? {
        get { properties["cmt"] as? String }
        set { properties["cmt"] = newValue }
    }

    /// The GPX description (`<desc>`).
    public var gpxDescription: String? {
        get { properties["desc"] as? String }
        set { properties["desc"] = newValue }
    }

    /// The GPX source (`<src>`).
    public var gpxSource: String? {
        get { properties["src"] as? String }
        set { properties["src"] = newValue }
    }

    /// The GPX symbol name (`<sym>`).
    public var gpxSymbol: String? {
        get { properties["sym"] as? String }
        set { properties["sym"] = newValue }
    }

    /// The GPX classification (`<type>`).
    public var gpxTypeName: String? {
        get { properties["type"] as? String }
        set { properties["type"] = newValue }
    }

    /// The GPS fix type (`<fix>`).
    public var gpxFix: GPSFixType? {
        get {
            guard let raw = properties["fix"] as? String else { return nil }
            return GPSFixType(rawValue: raw)
        }
        set {
            properties["fix"] = newValue?.rawValue
        }
    }

    /// Number of satellites (`<sat>`).
    public var gpxSatellites: Int? {
        get { intProp("sat") }
        set { properties["sat"] = newValue }
    }

    /// Horizontal dilution of precision (`<hdop>`).
    public var gpxHDOP: Double? {
        get { doubleProp("hdop") }
        set { properties["hdop"] = newValue }
    }

    /// Vertical dilution of precision (`<vdop>`).
    public var gpxVDOP: Double? {
        get { doubleProp("vdop") }
        set { properties["vdop"] = newValue }
    }

    /// Position dilution of precision (`<pdop>`).
    public var gpxPDOP: Double? {
        get { doubleProp("pdop") }
        set { properties["pdop"] = newValue }
    }

    /// Timestamp (`<time>`). ISO 8601 UTC.
    public var gpxTime: Date? {
        get {
            guard let s = properties["time"] as? String else { return nil }
            return GPXDateFormatter.parse(s)
        }
        set {
            if let date = newValue {
                properties["time"] = GPXDateFormatter.format(date)
            }
            else {
                properties["time"] = nil
            }
        }
    }

    /// Links associated with this GPX element (`<link>`).
    public var gpxLinks: [GPXLink] {
        get {
            guard let linkData = properties["link"] else { return [] }

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
                properties["link"] = nil
            }
            else {
                let dicts: [[String: String]] = newValue.map { link in
                    var d: [String: String] = ["href": link.href]
                    if let t = link.text { d["text"] = t }
                    if let tp = link.type { d["type"] = tp }
                    return d
                }
                properties["link"] = dicts
            }
        }
    }

    // MARK: - GPX 1.0 track-point fields

    /// Course over ground from a GPX 1.0 track point (`<course>`).
    public var gpxCourse10: Double? {
        get { doubleProp("course") }
        set { properties["course"] = newValue }
    }

    /// Speed from a GPX 1.0 track point (`<speed>`).
    public var gpxSpeed10: Double? {
        get { doubleProp("speed") }
        set { properties["speed"] = newValue }
    }

    // MARK: - Garmin TrackPointExtension v2 (gpxtpx)

    /// Heart rate in beats per minute.
    public var gpxHeartRate: Int? {
        get { gpxtpxInt("hr") }
        set { gpxtpxSet("hr", value: newValue) }
    }

    /// Cadence in revolutions per minute.
    public var gpxCadence: Int? {
        get { gpxtpxInt("cad") }
        set { gpxtpxSet("cad", value: newValue) }
    }

    /// Power in watts.
    public var gpxPower: Int? {
        get { gpxtpxInt("power") }
        set { gpxtpxSet("power", value: newValue) }
    }

    /// Speed in meters per second.
    public var gpxSpeed: Double? {
        get { gpxtpxDouble("speed") }
        set { gpxtpxSet("speed", value: newValue) }
    }

    /// Course over ground in degrees true.
    public var gpxCourse: Double? {
        get { gpxtpxDouble("course") }
        set { gpxtpxSet("course", value: newValue) }
    }

    /// Bearing in degrees true.
    public var gpxBearing: Double? {
        get { gpxtpxDouble("bearing") }
        set { gpxtpxSet("bearing", value: newValue) }
    }

    /// Air temperature in degrees Celsius.
    public var gpxAirTemperature: Double? {
        get { gpxtpxDouble("atemp") }
        set { gpxtpxSet("atemp", value: newValue) }
    }

    /// Water temperature in degrees Celsius.
    public var gpxWaterTemperature: Double? {
        get { gpxtpxDouble("wtemp") }
        set { gpxtpxSet("wtemp", value: newValue) }
    }

    /// Water depth in meters.
    public var gpxDepth: Double? {
        get { gpxtpxDouble("depth") }
        set { gpxtpxSet("depth", value: newValue) }
    }

    // MARK: - Garmin GpxExtensions v3 (gpxx)

    /// Proximity alarm distance in meters.
    public var gpxProximity: Double? {
        get { gpxxDouble("Proximity") }
        set { gpxxSet("Proximity", value: newValue) }
    }

    /// Display mode for waypoints on a map.
    public var gpxDisplayMode: String? {
        get { gpxxString("DisplayMode") }
        set { gpxxSet("DisplayMode", value: newValue) }
    }

    /// Postal address (Garmin WaypointExtension).
    public var gpxAddress: GPXAddress? {
        get {
            guard let dict = gpxxDict("Address") else { return nil }
            let streets: [String] = {
                if let arr = dict["StreetAddress"] as? [String] { return arr }
                if let str = dict["StreetAddress"] as? String { return [str] }
                return []
            }()
            return GPXAddress(
                streetAddresses: streets,
                city: dict["City"] as? String,
                state: dict["State"] as? String,
                country: dict["Country"] as? String,
                postalCode: dict["PostalCode"] as? String)
        }
        set {
            guard let addr = newValue else {
                gpxxDelete("Address")
                return
            }
            var dict: [String: Sendable] = [:]
            if !addr.streetAddresses.isEmpty {
                dict["StreetAddress"] = addr.streetAddresses
            }
            if let v = addr.city { dict["City"] = v }
            if let v = addr.state { dict["State"] = v }
            if let v = addr.country { dict["Country"] = v }
            if let v = addr.postalCode { dict["PostalCode"] = v }
            gpxxSet("Address", value: dict as [String: Sendable])
        }
    }

    /// Categories (Garmin WaypointExtension).
    public var gpxCategories: [String] {
        get {
            gpxxStringArray("Categories")
        }
        set {
            if newValue.isEmpty {
                gpxxDelete("Categories")
            }
            else {
                gpxxSet("Categories", value: newValue)
            }
        }
    }

    /// Phone numbers (Garmin WaypointExtension).
    public var gpxPhoneNumbers: [GPXPhoneNumber] {
        get {
            guard let entries = gpxxAnyArray("PhoneNumber") else { return [] }
            return entries.compactMap { entry in
                if let dict = entry as? [String: Sendable] {
                    return GPXPhoneNumber(
                        value: dict["value"] as? String ?? "",
                        category: dict["category"] as? String)
                }
                if let str = entry as? String {
                    return GPXPhoneNumber(value: str)
                }
                return nil
            }
        }
        set {
            if newValue.isEmpty {
                gpxxDelete("PhoneNumber")
            }
            else {
                let entries: [Sendable] = newValue.map { pn in
                    var dict: [String: Sendable] = ["value": pn.value]
                    if let cat = pn.category { dict["category"] = cat }
                    return dict
                }
                gpxxSet("PhoneNumber", value: entries)
            }
        }
    }

    /// Whether the route was automatically named (Garmin RouteExtension).
    public var gpxIsAutoNamed: Bool? {
        get { gpxxBool("IsAutoNamed") }
        set { gpxxSet("IsAutoNamed", value: newValue) }
    }

    /// Display color for routes or tracks (Garmin extension).
    public var gpxDisplayColor: String? {
        get { gpxxString("DisplayColor") }
        set { gpxxSet("DisplayColor", value: newValue) }
    }

    // MARK: - Private helpers

    private func intProp(_ key: String) -> Int? {
        if let i = properties[key] as? Int { return i }
        if let d = properties[key] as? Double { return Int(d) }
        if let s = properties[key] as? String { return Int(s) }
        return nil
    }

    private func doubleProp(_ key: String) -> Double? {
        if let d = properties[key] as? Double { return d }
        if let i = properties[key] as? Int { return Double(i) }
        if let s = properties[key] as? String { return Double(s) }
        return nil
    }

    // MARK: - Extension helpers (gpxtpx)

    private func gpxtpxInt(_ key: String) -> Int? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxtpx"] as? [String: Sendable]
        guard let val = ns?[key] else { return nil }
        if let i = val as? Int { return i }
        if let d = val as? Double { return Int(d) }
        if let s = val as? String { return Int(s) }
        return nil
    }

    private func gpxtpxDouble(_ key: String) -> Double? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxtpx"] as? [String: Sendable]
        guard let val = ns?[key] else { return nil }
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        if let s = val as? String { return Double(s) }
        return nil
    }

    private mutating func gpxtpxSet(_ key: String, value: Sendable?) {
        var ext = properties["extensions"] as? [String: Sendable] ?? [:]
        var ns = ext["gpxtpx"] as? [String: Sendable] ?? [:]
        if let value {
            ns[key] = value
        }
        else {
            let _ = ns.removeValue(forKey: key)
        }
        ext["gpxtpx"] = ns.isEmpty ? nil : ns
        properties["extensions"] = ext.isEmpty ? nil : ext
    }

    // MARK: - Extension helpers (gpxx)

    private func gpxxString(_ key: String) -> String? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxx"] as? [String: Sendable]
        guard let val = ns?[key] else { return nil }
        if let s = val as? String { return s }
        return nil
    }

    private func gpxxDouble(_ key: String) -> Double? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxx"] as? [String: Sendable]
        guard let val = ns?[key] else { return nil }
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        if let s = val as? String { return Double(s) }
        return nil
    }

    private func gpxxBool(_ key: String) -> Bool? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxx"] as? [String: Sendable]
        guard let val = ns?[key] else { return nil }
        if let b = val as? Bool { return b }
        if let s = val as? String {
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
        }
        return nil
    }

    private func gpxxDict(_ key: String) -> [String: Sendable]? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxx"] as? [String: Sendable]
        return ns?[key] as? [String: Sendable]
    }

    private func gpxxAnyArray(_ key: String) -> [Sendable]? {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxx"] as? [String: Sendable]
        return ns?[key] as? [Sendable]
    }

    private func gpxxStringArray(_ key: String) -> [String] {
        let ext = properties["extensions"] as? [String: Sendable]
        let ns = ext?["gpxx"] as? [String: Sendable]
        guard let val = ns?[key] else { return [] }
        if let str = val as? String { return [str] }
        if let arr = val as? [String] { return arr }
        if let arr = val as? [Sendable] {
            return arr.compactMap { $0 as? String }
        }
        return []
    }

    private mutating func gpxxSet(_ key: String, value: Sendable?) {
        var ext = properties["extensions"] as? [String: Sendable] ?? [:]
        var ns = ext["gpxx"] as? [String: Sendable] ?? [:]
        if let value {
            ns[key] = value
        }
        else {
            let _ = ns.removeValue(forKey: key)
        }
        ext["gpxx"] = ns.isEmpty ? nil : ns
        properties["extensions"] = ext.isEmpty ? nil : ext
    }

    private mutating func gpxxDelete(_ key: String) {
        gpxxSet(key, value: nil)
    }

}
