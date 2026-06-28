import Foundation
import GISTools

// MARK: - GPX File Model

/// Intermediate representation of a parsed GPX file.
/// This model is not public — it sits between the XML parser and the
/// GeoJSON FeatureCollection conversion.
struct GPXFile {

    var metadata: GPXMetadata?
    var waypoints: [GPXWaypoint]
    var routes: [GPXRoute]
    var tracks: [GPXTrack]

    init(metadata: GPXMetadata? = nil,
         waypoints: [GPXWaypoint] = [],
         routes: [GPXRoute] = [],
         tracks: [GPXTrack] = []
    ) {
        self.metadata = metadata
        self.waypoints = waypoints
        self.routes = routes
        self.tracks = tracks
    }

}

// MARK: - GPX Metadata

struct GPXMetadata {

    var name: String?
    var desc: String?
    var author: GPXPerson?
    var copyright: GPXCopyright?
    var links: [GPXLink]
    var time: Date?
    var keywords: String?
    var bounds: BoundingBox?

    init(name: String? = nil,
         desc: String? = nil,
         author: GPXPerson? = nil,
         copyright: GPXCopyright? = nil,
         links: [GPXLink] = [],
         time: Date? = nil,
         keywords: String? = nil,
         bounds: BoundingBox? = nil
    ) {
        self.name = name
        self.desc = desc
        self.author = author
        self.copyright = copyright
        self.links = links
        self.time = time
        self.keywords = keywords
        self.bounds = bounds
    }

}

// MARK: - GPX Waypoint

struct GPXWaypoint {

    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date?
    var magneticVariation: Double?
    var geoidHeight: Double?
    var name: String?
    var comment: String?
    var description: String?
    var source: String?
    var links: [GPXLink]
    var symbol: String?
    var type: String?
    var fix: GPSFixType?
    var satellites: Int?
    var horizontalDilution: Double?
    var verticalDilution: Double?
    var positionDilution: Double?
    var ageOfDGPSData: Double?
    var dgpsid: Int?
    var course: Double?
    var speed: Double?
    var extensions: [String: [String: Sendable]]

    init(latitude: Double,
         longitude: Double,
         elevation: Double? = nil,
         time: Date? = nil,
         magneticVariation: Double? = nil,
         geoidHeight: Double? = nil,
         name: String? = nil,
         comment: String? = nil,
         description: String? = nil,
         source: String? = nil,
         links: [GPXLink] = [],
         symbol: String? = nil,
         type: String? = nil,
         fix: GPSFixType? = nil,
         satellites: Int? = nil,
         horizontalDilution: Double? = nil,
         verticalDilution: Double? = nil,
         positionDilution: Double? = nil,
         ageOfDGPSData: Double? = nil,
         dgpsid: Int? = nil,
         course: Double? = nil,
         speed: Double? = nil,
         extensions: [String: [String: Sendable]] = [:]
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
        self.magneticVariation = magneticVariation
        self.geoidHeight = geoidHeight
        self.name = name
        self.comment = comment
        self.description = description
        self.source = source
        self.links = links
        self.symbol = symbol
        self.type = type
        self.fix = fix
        self.satellites = satellites
        self.horizontalDilution = horizontalDilution
        self.verticalDilution = verticalDilution
        self.positionDilution = positionDilution
        self.ageOfDGPSData = ageOfDGPSData
        self.dgpsid = dgpsid
        self.course = course
        self.speed = speed
        self.extensions = extensions
    }

}

// MARK: - GPX Route

struct GPXRoute {

    var name: String?
    var comment: String?
    var description: String?
    var source: String?
    var links: [GPXLink]
    var number: Int?
    var type: String?
    var points: [GPXWaypoint]
    var extensions: [String: [String: Sendable]]

    init(name: String? = nil,
         comment: String? = nil,
         description: String? = nil,
         source: String? = nil,
         links: [GPXLink] = [],
         number: Int? = nil,
         type: String? = nil,
         points: [GPXWaypoint] = [],
         extensions: [String: [String: Sendable]] = [:]
    ) {
        self.name = name
        self.comment = comment
        self.description = description
        self.source = source
        self.links = links
        self.number = number
        self.type = type
        self.points = points
        self.extensions = extensions
    }

}

// MARK: - GPX Track

struct GPXTrack {

    var name: String?
    var comment: String?
    var description: String?
    var source: String?
    var links: [GPXLink]
    var number: Int?
    var type: String?
    var segments: [[GPXWaypoint]]
    var extensions: [String: [String: Sendable]]

    init(name: String? = nil,
         comment: String? = nil,
         description: String? = nil,
         source: String? = nil,
         links: [GPXLink] = [],
         number: Int? = nil,
         type: String? = nil,
         segments: [[GPXWaypoint]] = [],
         extensions: [String: [String: Sendable]] = [:]
    ) {
        self.name = name
        self.comment = comment
        self.description = description
        self.source = source
        self.links = links
        self.number = number
        self.type = type
        self.segments = segments
        self.extensions = extensions
    }

}
