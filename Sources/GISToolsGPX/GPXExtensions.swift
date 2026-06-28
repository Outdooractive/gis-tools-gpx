import Foundation

/// Well-known GPX extension namespaces and their element names.
enum GPXExtensionNamespace: String {

    /// Garmin TrackPoint Extension v2
    /// (http://www.garmin.com/xmlschemas/TrackPointExtension/v2)
    case gpxtpx = "http://www.garmin.com/xmlschemas/TrackPointExtension/v2"

    /// Garmin GPX Extensions v3
    /// (http://www.garmin.com/xmlschemas/GpxExtensions/v3)
    case gpxx = "http://www.garmin.com/xmlschemas/GpxExtensions/v3"

    var prefix: String {
        switch self {
        case .gpxtpx: "gpxtpx"
        case .gpxx: "gpxx"
        }
    }

    /// Returns the namespace for a given XML namespace URI.
    static func namespace(forURI uri: String) -> GPXExtensionNamespace? {
        for ns in [GPXExtensionNamespace.gpxtpx, .gpxx] {
            if uri == ns.rawValue { return ns }
        }
        return nil
    }

    /// Returns the namespace for a given prefix string.
    static func namespace(forPrefix prefix: String) -> GPXExtensionNamespace? {
        switch prefix.lowercased() {
        case "gpxtpx": .gpxtpx
        case "gpxx": .gpxx
        default: nil
        }
    }

    // Legacy: alias for namespace(forPrefix:)
    static func namespace(for prefix: String) -> GPXExtensionNamespace? {
        namespace(forPrefix: prefix)
    }

    /// Determines whether an element of this namespace is placed within
    /// a `<trkpt><extensions>` container (gpxtpx) or can appear in
    /// `<wpt>`, `<rte>`, and `<trk>` extensions (gpxx).
    var allowedIn: [GPXExtensionContext] {
        switch self {
        case .gpxtpx: [.trackPoint]
        case .gpxx: [.waypoint, .routePoint, .trackPoint, .route, .track]
        }
    }

    /// Returns the GPX 1.1 allowed children.
    static func children(for prefix: String) -> Set<String> {
        switch prefix.lowercased() {
        case "gpxtpx":
            ["hr", "cad", "atemp", "wtemp", "depth", "speed",
             "course", "bearing", "power", "TrackPointExtension"]
        case "gpxx":
            [
                "WaypointExtension", "RouteExtension", "RoutePointExtension",
                "TrackExtension", "TrackPointExtension",
                "Proximity", "Temperature", "Depth", "DisplayMode",
                "Categories", "Category", "Address", "StreetAddress",
                "City", "State", "Country", "PostalCode",
                "PhoneNumber", "IsAutoNamed",
                "DisplayColor", "Subclass", "rpt",
            ]
        default: []
        }
    }

}

/// The context in which a GPX extension element appears.
enum GPXExtensionContext {

    case waypoint
    case routePoint
    case trackPoint
    case route
    case track

}
