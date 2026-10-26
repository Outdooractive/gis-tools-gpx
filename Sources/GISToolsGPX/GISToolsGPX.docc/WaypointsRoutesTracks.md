# Waypoints, routes, and tracks

GPX has three located element types. Each becomes one GeoJSON feature with a
``GPXElementType`` stored in the `gpx_type` property.

## Waypoints

A `<wpt>` becomes a `Point` feature with `gpxType == .waypoint`. Standard GPX
fields have typed accessors:

```swift
let waypoint = collection.gpxWaypoints.first!

waypoint.gpxName              // <name>
waypoint.gpxComment           // <cmt>
waypoint.gpxDescription       // <desc>
waypoint.gpxSource            // <src>
waypoint.gpxSymbol            // <sym>
waypoint.gpxTypeName          // <type>
waypoint.gpxTime              // <time>
waypoint.gpxElevation         // <ele>, stored on the coordinate
waypoint.gpxFix               // <fix>
waypoint.gpxSatellites        // <sat>
waypoint.gpxHDOP              // <hdop>
waypoint.gpxVDOP              // <vdop>
waypoint.gpxPDOP              // <pdop>
waypoint.gpxMagneticVariation // <magvar>
waypoint.gpxGeoidHeight       // <geoidheight>
waypoint.gpxAgeOfDGPSData     // <ageofdgpsdata>
waypoint.gpxDGPSID            // <dgpsid>
waypoint.gpxLinks             // <link> elements
```

All accessors are settable. `gpxElevation` updates the geometry coordinate and
keeps an `ele` property as a fallback for non-Point features.

## Routes

A `<rte>` becomes a `LineString` feature with `gpxType == .route`. Route-level
metadata uses the same accessors as waypoints (`gpxName`, `gpxComment`,
`gpxDescription`, `gpxSource`, `gpxLinks`, `gpxTypeName`).

Per-`<rtept>` data is stored in parallel arrays aligned to the LineString
coordinates:

```swift
route.gpxRouteTimes        // [Date?]?
route.gpxRouteNames        // [String?]?
route.gpxRouteComments     // [String?]?
route.gpxRouteDescriptions // [String?]?
route.gpxRouteSources      // [String?]?
route.gpxRouteSymbols      // [String?]?
route.gpxRouteTypes        // [String?]?
route.gpxRouteLinks        // [[GPXLink]?]? — one inner list per point
route.gpxRouteExtensions   // [[String: [String: Sendable]]?]? — per-point raw extensions
```

A `nil` entry means that point had no value for the field. Missing trailing
entries are also treated as `nil`, so shorter arrays are valid.

## Tracks

A `<trk>` becomes a `MultiLineString` feature with `gpxType == .track`, one
`LineString` per `<trkseg>`. Track-level metadata uses the same accessors as
routes.

Per-`<trkpt>` data is flattened across all segments and stored in parallel
arrays aligned to the flattened coordinate order:

```swift
track.gpxTimes              // [Date?]?
track.gpxElevations         // [Double?]?
track.gpxHeartRates         // [Int?]?
track.gpxCadences           // [Int?]?
track.gpxPowers             // [Int?]?
track.gpxSpeeds             // [Double?]?
track.gpxCourses            // [Double?]?
track.gpxAirTemperatures    // [Double?]?
track.gpxWaterTemperatures  // [Double?]?
track.gpxDepths             // [Double?]?
track.gpxBearings           // [Double?]?
track.gpxTrackNames         // [String?]?
track.gpxTrackComments      // [String?]?
track.gpxTrackDescriptions  // [String?]?
track.gpxTrackSources       // [String?]?
track.gpxTrackSymbols       // [String?]?
track.gpxTrackTypes         // [String?]?
track.gpxTrackLinks         // [[GPXLink]?]?
track.gpxTrackPointExtensions // [[String: [String: Sendable]]?]?
track.gpxTrackPointQuality  // [[String: Sendable]?]? — fix/sat/dop/magvar/dgps
```

`gpxSpeeds` and `gpxCourses` combine GPX 1.1 `gpxtpx:speed`/`gpxtpx:course`
with the GPX 1.0 flat `<speed>`/`<course>` track-point fields. The gpxtpx value
wins when both are present.

Because arrays are aligned to the flattened coordinate list, index arithmetic
must use the same flattening:

```swift
let coordinates = (track.geometry as? MultiLineString)?.lineStrings
    .flatMap(\.coordinates) ?? []

for (index, coordinate) in coordinates.enumerated() {
    if let heartRate = track.gpxHeartRates?[index],
       let speed = track.gpxSpeeds?[index]
    {
        print(index, coordinate.latitude, heartRate, speed)
    }
}
```

## Metadata

The GPX `<metadata>` block is stored in the collection's foreign members and
exposed through typed properties:

```swift
collection.gpxMetadataName
collection.gpxMetadataDescription
collection.gpxMetadataKeywords
collection.gpxMetadataTime
collection.gpxMetadataAuthor
collection.gpxMetadataCopyright
collection.gpxMetadataLinks
collection.gpxMetadataBounds
```

The author supports name, email, and one link. The copyright carries the
required author plus optional year and license.
