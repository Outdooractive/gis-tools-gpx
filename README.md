[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-gpx%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/gis-tools-gpx)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-gpx%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/gis-tools-gpx)
[![](https://img.shields.io/github/license/Outdooractive/gis-tools-gpx)](https://github.com/Outdooractive/gis-tools-gpx/blob/main/LICENSE)  
[![](https://img.shields.io/github/v/release/Outdooractive/gis-tools-gpx?sort=semver&display_name=tag)](https://github.com/Outdooractive/gis-tools-gpx/releases) [![](https://img.shields.io/github/release-date/Outdooractive/gis-tools-gpx?display_date=published_at)](https://github.com/Outdooractive/gis-tools-gpx/releases)  
[![](https://img.shields.io/github/issues/Outdooractive/gis-tools-gpx)](https://github.com/Outdooractive/gis-tools-gpx/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/gis-tools-gpx)](https://github.com/Outdooractive/gis-tools-gpx/pulls)

# GISToolsGPX

GPX 1.1 (GPS Exchange Format) read and write support for Swift, built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools). Parses waypoints, routes, and tracks into typed `FeatureCollection` objects — and writes them back as valid GPX XML.

## Features

- Reads and writes GPX 1.1 files, with **read-only** support for GPX 1.0
- Waypoints (`<wpt>`) → `Feature<Point>`, Routes (`<rte>`) → `Feature<LineString>`, Tracks (`<trk>`) → `Feature<MultiLineString>`
- Typed convenience API on `Feature` and `FeatureCollection` — no manual dictionary casting
- Full `<metadata>` block (name, author, copyright, bounds, keywords, time, links)
- **Garmin TrackPointExtension v2** (`gpxtpx`): hr, cad, power, speed, course, bearing, temperature, depth
- **Garmin GpxExtensions v3** (`gpxx`): Address, Categories, PhoneNumber, DisplayColor, IsAutoNamed, rpt
- Structured extension values: `Address` → `GPXAddress`, `Categories` → `[String]`, `PhoneNumber` → `[GPXPhoneNumber]`
- Automatic type inference for extension values (booleans, integers, floating-point, strings)
- **Per-point sensor arrays**: heart rate, cadence, power, speed, temperature — stored as parallel arrays
- **`gpxPointFeatures()`**: expand track points into individual `Point` features with per-point sensor data
- Time-window and distance-window slicing of point features
- GPX 1.0-specific fields: `course`/`speed` on track points, flat `url`/`urlname` links
- Round-trip fidelity: write → read preserves element types, coordinates, properties, and extensions

## Requirements

Swift 6.1 or higher. Compiles on iOS (≥ iOS 15), macOS (≥ macOS 15), tvOS (≥ tvOS 15), watchOS (≥ watchOS 7), Linux, Android and Wasm. No external dependencies beyond the base `gis-tools` package.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/gis-tools-gpx", from: "1.0.0"),
    .package(url: "https://github.com/Outdooractive/gis-tools", from: "2.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "GISToolsGPX", package: "gis-tools-gpx"),
        .product(name: "GISTools", package: "gis-tools"),
    ]),
]
```

## Usage

### Reading

```swift
import GISTools
import GISToolsGPX

let url = URL(fileURLWithPath: "/path/to/file.gpx")
let fc = try GPXCoder.read(from: url)

// Or via the convenience init:
guard let fc = FeatureCollection(gpx: url) else { return }
```

### Writing

```swift
try fc.writeGPX(to: outputURL)

// Or via the coder directly:
try GPXCoder.write(fc, to: outputURL)
```

### Inspecting GPX element types

Each `Feature` carries a `gpxType` property identifying its origin:

```swift
for feature in fc.features {
    switch feature.gpxType {
    case .waypoint: print("Waypoint: \(feature.gpxName ?? "unnamed")")
    case .route:    print("Route: \(feature.gpxName ?? "unnamed")")
    case .track:    print("Track: \(feature.gpxName ?? "unnamed")")
    case nil:       print("Unknown GPX type")
    }
}
```

### Waypoint properties

```swift
let waypoint = fc.features.first!
print(waypoint.gpxName)            // "Reichstag (Berlin)"
print(waypoint.gpxSymbol)          // "City"
print(waypoint.gpxFix)             // .threeDimensional
print(waypoint.gpxSatellites)      // 12
print(waypoint.gpxHDOP)            // 1.5
print(waypoint.gpxTime)            // Optional<Date>

// Coordinate access
let coord = (waypoint.geometry as! Point).coordinate
print(coord.latitude)              // 52.518611
print(coord.longitude)             // 13.376111
print(coord.altitude)              // 35.0
```

### Track and route geometry

```swift
let track = fc.features[1]
let multiLine = track.geometry as! MultiLineString
for (i, segment) in multiLine.lineStrings.enumerated() {
    print("Segment \(i): \(segment.coordinates.count) points")
}

let route = fc.features[2]
let lineString = route.geometry as! LineString
print("Route has \(lineString.coordinates.count) waypoints")
```

### Garmin fitness extensions (gpxtpx)

Track-point-level fitness data via typed properties:

```swift
var pointFeature = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.3)))
pointFeature.gpxHeartRate = 145
pointFeature.gpxCadence = 90
pointFeature.gpxPower = 220        // watts
pointFeature.gpxSpeed = 12.5       // m/s
pointFeature.gpxCourse = 45.0      // degrees true
pointFeature.gpxAirTemperature = 18.5
pointFeature.gpxDepth = 2.0        // meters

// Reading back:
let hr = feature.gpxHeartRate      // Int? (145)
let cad = feature.gpxCadence       // Int? (90)
let speed = feature.gpxSpeed       // Double? (12.5)
```

### Per-point sensor arrays (track Features only)

Track-level fitness data (gpxtpx extensions on `<trkpt>`) is accumulated into parallel arrays on the track Feature:

```swift
let track = fc.features.first { $0.gpxType == .track }!

let hr = track.gpxHeartRates       // [Int?]? — [120, 145, 160, ...]
let cad = track.gpxCadences         // [Int?]? — [80, 90, 95, ...]
let pw = track.gpxPowers            // [Int?]? — [150, 220, ...] (nil = missing)
let spd = track.gpxSpeeds           // [Double?]? — [12.5, ...]
let tmp = track.gpxAirTemperatures  // [Double?]? — [22.5, ...]
let elev = track.gpxElevations      // [Double?]? — [35.0, 38.0, ...]

// Arrays align with coordinates — nil where no data was recorded
for i in 0..<(track.gpxHeartRates?.count ?? 0) {
    if let hr = hr?[i], let cad = cad?[i] {
        print("Point \(i): HR=\(hr), cad=\(cad)")
    }
}
```

### Converting track points to individual Features

Expand the `MultiLineString` track into individual `Point` features, each carrying its own sensor data:

```swift
let pts = track.gpxPointFeatures()
pts.features.count                  // 3 (one per track point)
pts.features[0].gpxHeartRate        // 120 (via convenience accessor)
pts.features[2].gpxSpeed            // 12.5 (reads from extensions["gpxtpx"])

// Time-window slicing
let morning = track.gpxPointFeatures(from: morningDate, to: noonDate)

// Distance-window slicing (meters along track)
let lastKm = track.gpxPointFeatures(from: totalM - 1000, to: totalM)

// Fractional-window slicing (0.0–1.0)
let middle = track.gpxPointFeatures(fraction: 0.33, to: 0.66)
```

### Reconstructing a track from point features

Convert a `FeatureCollection` of Point features back into a `Feature<MultiLineString>` track with per-point sensor arrays rebuilt:

```swift
let pts = track.gpxPointFeatures()

// Via FeatureCollection:
let rebuilt = pts.gpxTrackFromPointFeatures()
rebuilt?.gpxHeartRates?[0]   // 120
rebuilt?.gpxSpeeds?[2]        // 12.5

// Via Feature convenience init (also reads extensions["gpxtpx"]):
let track = Feature(gpxTrackFrom: pts)
track?.gpxCadences?[1]        // 90
track?.gpxHeartRate           // nil (track Feature has arrays, not single values)
```

Non-Point features are silently skipped. Returns `nil` if no Point features exist. The gpxtpx extension data (hr, cad, power, speed, atemp) is extracted from each point and re-accumulated into parallel arrays, so round-trips preserve sensor data. The track has a single segment (no lap splitting).

### Garmin waypoint extensions (gpxx)

Address, categories, and phone numbers as structured types:

```swift
let address = waypoint.gpxAddress
print(address?.streetAddresses)    // ["Teststrasse 123", "Floor 4"]
print(address?.city)               // "Berlin"
print(address?.country)            // "Germany"
print(address?.postalCode)         // "10115"

let categories = waypoint.gpxCategories
print(categories)                  // ["Office", "Technology", "Outdoor"]

for phone in waypoint.gpxPhoneNumbers {
    print("\(phone.category ?? "other"): \(phone.value)")
    // Work: +49-30-555-1234
    // Mobile: +49-170-555-5678
}

let isAutoNamed = route.gpxIsAutoNamed  // Bool?
let color = route.gpxDisplayColor       // String? ("Red", "Blue", etc.)
```

### Round-trip: build from scratch

```swift
import GISTools
import GISToolsGPX

var fc = FeatureCollection()

// Add metadata
fc.gpxMetadataName = "My GPX File"
fc.gpxMetadataKeywords = "hiking, alps"
fc.gpxMetadataAuthor = GPXPerson(
    name: "Jane Hiker",
    email: "jane@example.com")
fc.gpxMetadataBounds = BoundingBox(
    southWest: Coordinate3D(latitude: 47.0, longitude: 10.0),
    northEast: Coordinate3D(latitude: 48.0, longitude: 11.0))

// Add a waypoint
var wpt = Feature(Point(Coordinate3D(latitude: 47.56, longitude: 10.22)))
wpt.gpxType = .waypoint
wpt.gpxName = "Alpine Lodge"
wpt.gpxSymbol = "Lodging"
wpt.gpxElevation = 1420.0
wpt.gpxAddress = GPXAddress(
    streetAddresses: ["Bergstrasse 1"],
    city: "Oberstdorf",
    country: "Germany",
    postalCode: "87561")
fc.features.append(wpt)

// Add a route
var rte = Feature(LineString(unchecked: [
    Coordinate3D(latitude: 47.56, longitude: 10.22),
    Coordinate3D(latitude: 47.57, longitude: 10.25),
    Coordinate3D(latitude: 47.59, longitude: 10.30),
]))
rte.gpxType = .route
rte.gpxName = "Summit Trail"
rte.gpxTypeName = "Hiking"
fc.features.append(rte)

// Write to file
try fc.writeGPX(to: outputURL)
```

### Setting and writing extensions

```swift
var wpt = Feature(Point(Coordinate3D(latitude: 47.56, longitude: 10.22)))
wpt.gpxType = .waypoint
wpt.gpxName = "Checkpoint"

// Fitness data
wpt.gpxHeartRate = 120
wpt.gpxPower = 180

// Structured address
wpt.gpxAddress = GPXAddress(
    streetAddresses: ["Alpenstraße 1"],
    city: "Innsbruck",
    country: "Austria")

// Categories and phone numbers
wpt.gpxCategories = ["Hiking", "Rest Stop"]
wpt.gpxPhoneNumbers = [
    GPXPhoneNumber(value: "+43-512-555", category: "Info"),
]

// Route display properties
wpt.gpxDisplayColor = "Red"
wpt.gpxIsAutoNamed = false

// Write — all extension data round-trips
try FeatureCollection([wpt]).writeGPX(to: outputURL)
```

### GPX 1.0 read support

GPX 1.0 files are parsed with backward-compatible handling:

```swift
let fc = try GPXCoder.read(from: gpx10URL)

// GPX 1.0 flat links (url/urlname) converted to GPXLink
let waypoint = fc.features.first!
for link in waypoint.gpxLinks {
    print("\(link.href): \(link.text ?? "")")
    // https://www.bundestag.de: Bundestag website
}

// GPX 1.0 course/speed on track points (not extensions)
// These are stored as gpxCourse10 / gpxSpeed10 on the waypoints
// within track segments, not on the track Feature itself.
```

### OSM traces

OpenStreetMap GPS traces are standard GPX 1.1 files — they read and write like any other GPX:

```swift
let trace = try GPXCoder.read(from: osmURL)
let track = trace.features.first { $0.gpxType == .track }!
let multiline = track.geometry as! MultiLineString
print("\(multiline.lineStrings[0].coordinates.count) trace points")

// OSM traces often use cmt/desc for tagging
print(track.gpxDescription)  // e.g. "Walking trace through Berlin Mitte"
```

### Raw extension access

If you need the raw extension dictionary (for namespaces not covered by the typed API):

```swift
let ext = feature.properties["extensions"] as? [String: Sendable]
let gpxtpx = ext?["gpxtpx"] as? [String: Sendable]
let gpxx = ext?["gpxx"] as? [String: Sendable]

// Direct key access
let hr = gpxtpx?["hr"] as? Int
let city = (gpxx?["Address"] as? [String: Sendable])?["City"] as? String
```

### Typed API reference

**On `Feature`:**

| Property | Type | GPX Source |
|---|---|---|
| `gpxType` | `GPXElementType?` | `.waypoint`, `.route`, `.track` |
| `gpxName` | `String?` | `<name>` |
| `gpxComment` | `String?` | `<cmt>` |
| `gpxDescription` | `String?` | `<desc>` |
| `gpxSource` | `String?` | `<src>` |
| `gpxSymbol` | `String?` | `<sym>` |
| `gpxTypeName` | `String?` | `<type>` |
| `gpxFix` | `GPSFixType?` | `<fix>` |
| `gpxSatellites` | `Int?` | `<sat>` |
| `gpxHDOP` | `Double?` | `<hdop>` |
| `gpxVDOP` | `Double?` | `<vdop>` |
| `gpxPDOP` | `Double?` | `<pdop>` |
| `gpxTime` | `Date?` | `<time>` |
| `gpxLinks` | `[GPXLink]` | `<link>` |
| `gpxCourse10` | `Double?` | `<course>` (GPX 1.0) |
| `gpxSpeed10` | `Double?` | `<speed>` (GPX 1.0) |
| `gpxHeartRate` | `Int?` | gpxtpx `hr` |
| `gpxCadence` | `Int?` | gpxtpx `cad` |
| `gpxPower` | `Int?` | gpxtpx `power` |
| `gpxSpeed` | `Double?` | gpxtpx `speed` |
| `gpxCourse` | `Double?` | gpxtpx `course` |
| `gpxBearing` | `Double?` | gpxtpx `bearing` |
| `gpxAirTemperature` | `Double?` | gpxtpx `atemp` |
| `gpxWaterTemperature` | `Double?` | gpxtpx `wtemp` |
| `gpxDepth` | `Double?` | gpxtpx `depth` |
| `gpxHeartRates` | `[Int?]?` | gpxtpx `hr` (per-point array) |
| `gpxCadences` | `[Int?]?` | gpxtpx `cad` (per-point array) |
| `gpxPowers` | `[Int?]?` | gpxtpx `power` (per-point array) |
| `gpxSpeeds` | `[Double?]?` | gpxtpx `speed` (per-point array) |
| `gpxAirTemperatures` | `[Double?]?` | gpxtpx `atemp` (per-point array) |
| `gpxElevations` | `[Double?]?` | `<ele>` (per-point array) |
| `gpxTimes` | `[Date?]?` | `<time>` (per-point array) |
| `gpxProximity` | `Double?` | gpxx `Proximity` |
| `gpxDisplayMode` | `String?` | gpxx `DisplayMode` |
| `gpxAddress` | `GPXAddress?` | gpxx `Address` |
| `gpxCategories` | `[String]` | gpxx `Categories` |
| `gpxPhoneNumbers` | `[GPXPhoneNumber]` | gpxx `PhoneNumber` |
| `gpxIsAutoNamed` | `Bool?` | gpxx `IsAutoNamed` |
| `gpxDisplayColor` | `String?` | gpxx `DisplayColor` |

**On `FeatureCollection`:**

| Property | Type | GPX Source |
|---|---|---|
| `gpxWaypoints` | `[Feature]` | waypoints (filtered by `gpxType`) |
| `gpxRoutes` | `[Feature]` | routes (filtered by `gpxType`) |
| `gpxTracks` | `[Feature]` | tracks (filtered by `gpxType`) |
| `gpxMetadataName` | `String?` | `<metadata><name>` |
| `gpxMetadataDescription` | `String?` | `<metadata><desc>` |
| `gpxMetadataKeywords` | `String?` | `<metadata><keywords>` |
| `gpxMetadataTime` | `Date?` | `<metadata><time>` |
| `gpxMetadataAuthor` | `GPXPerson?` | `<metadata><author>` |
| `gpxMetadataCopyright` | `GPXCopyright?` | `<metadata><copyright>` |
| `gpxMetadataLinks` | `[GPXLink]` | `<metadata><link>` |
| `gpxMetadataBounds` | `BoundingBox?` | `<metadata><bounds>` |

**Methods on `FeatureCollection`:**

| Method | Returns | Description |
|---|---|---|
| `gpxTrackFromPointFeatures()` | `Feature?` | Reconstructs a `Feature<MultiLineString>` from Point features produced by `gpxPointFeatures()`. gpxtpx sensor data is re-accumulated into per-point arrays. Returns `nil` if no Point features exist. |

**Convenience initializer on `Feature`:**

| Initializer | Description |
|---|---|
| `Feature(gpxTrackFrom:)` | Creates a track Feature from a `FeatureCollection` of Point features. Same as `gpxTrackFromPointFeatures()`. |

**Public model types:**

| Type | Fields |
|---|---|
| `GPXLink` | `href: String`, `text: String?`, `type: String?` |
| `GPXPerson` | `name: String?`, `email: String?`, `link: GPXLink?` |
| `GPXCopyright` | `author: String`, `year: Int?`, `license: String?` |
| `GPXAddress` | `streetAddresses: [String]`, `city: String?`, `state: String?`, `country: String?`, `postalCode: String?` |
| `GPXPhoneNumber` | `value: String`, `category: String?` |

### Supported extension namespaces

| Prefix | Namespace URI | Elements |
|---|---|---|
| `gpxtpx` | `http://www.garmin.com/xmlschemas/TrackPointExtension/v2` | hr, cad, power, speed, course, bearing, atemp, wtemp, depth |
| `gpxx` | `http://www.garmin.com/xmlschemas/GpxExtensions/v3` | Address, Categories, PhoneNumber, WaypointExtension, RouteExtension, TrackExtension, RoutePointExtension, TrackPointExtension, Proximity, Temperature, Depth, DisplayMode, DisplayColor, IsAutoNamed, Subclass, rpt |

### Limitations

- GPX 1.0 is **read-only**; written files always use GPX 1.1
- List-type extensions (Categories, PhoneNumber) use generic element names on write; exact child-element names may differ on round-trip
- Track-point-level and route-point-level extensions are lost during write because only track/route `Feature` objects are serialized (segment-level data is not individually written)
- `Subclass` (hexBinary) and `rpt` autoroute points are parsed but not exposed via the typed API

## Contributing

Please [create an issue](https://github.com/Outdooractive/gis-tools-gpx/issues) or [open a pull request](https://github.com/Outdooractive/gis-tools-gpx/pulls) with a fix or enhancement.

## License

MIT

## Authors

Thomas Rasch, Outdooractive

Built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).
