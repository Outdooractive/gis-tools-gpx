# Garmin extensions and point slicing

`GISToolsGPX` recognizes the two Garmin extension namespaces used by fitness
devices and Outdooractive routes, and also exposes the raw extension
dictionaries for anything without a typed accessor.

## Garmin TrackPointExtension v2 (`gpxtpx`)

Point features expose individual sensor values:

```swift
var point = Feature(Point(Coordinate3D(latitude: 52.5, longitude: 13.3)))
point.gpxHeartRate = 145
point.gpxCadence = 90
point.gpxPower = 220         // watts
point.gpxSpeed = 12.5        // m/s
point.gpxCourse = 45.0       // degrees true
point.gpxBearing = 44.0      // degrees true
point.gpxAirTemperature = 18.5
point.gpxWaterTemperature = 16.0
point.gpxDepth = 2.0         // meters

// Read back:
let heartRate = point.gpxHeartRate
let speed = point.gpxSpeed
```

Track features accumulate `<trkpt>` values into arrays (see
[Waypoints, routes, and tracks][waypointsroutestracks]). `gpxWaterTemperatures`, `gpxDepths`, and
`gpxBearings` cover the corresponding gpxtpx fields.

When writing, gpxtpx values are placed inside a
`<gpxtpx:TrackPointExtension>` wrapper. Values parsed from a non-standard
prefix are normalized to the canonical `gpxtpx` prefix.

## Garmin GpxExtensions v3 (`gpxx`)

Waypoints expose structured address, category, and phone-number values:

```swift
let waypoint = collection.gpxWaypoints.first!

waypoint.gpxAddress       // GPXAddress(streetAddresses:city:state:country:postalCode:)
waypoint.gpxCategories    // [String]
waypoint.gpxPhoneNumbers  // [GPXPhoneNumber]
waypoint.gpxProximity     // Double?
waypoint.gpxDisplayMode   // String?
waypoint.gpxDisplayColor  // String?
waypoint.gpxIsAutoNamed   // Bool?
```

All of these are settable. On write, gpxx elements are wrapped in the
context-appropriate Garmin wrapper: `WaypointExtension` for `<wpt>`,
`RouteExtension` for `<rte>`, `TrackExtension` for `<trk>`,
`RoutePointExtension` for `<rtept>`, and `TrackPointExtension` for `<trkpt>`.
Repeatable categories are emitted as one `<Categories>` parent with singular
`<Category>` children.

## Raw extension access

Extensions are stored under the feature property `extensions`, keyed by
namespace prefix:

```swift
let extensions = feature.properties["extensions"] as? [String: Sendable]
let gpxtpx = extensions?["gpxtpx"] as? [String: Sendable]
let gpxx = extensions?["gpxx"] as? [String: Sendable]

let hr = gpxtpx?["hr"] as? Int
let city = (gpxx?["Address"] as? [String: Sendable])?["City"] as? String
```

Per-point data that has no typed array is preserved verbatim:

- `gpxTrackPointExtensions` keeps non-gpxtpx namespaces and unknown gpxtpx
  fields on a track.
- `gpxRouteExtensions` keeps raw extensions on each route point.
- `gpx_track_point_quality` keeps the GPX quality fields on each track point.

Only `gpxtpx` and `gpxx` are recognized as extension namespaces. Other
namespaces are ignored by the parser and are not written, even if they appear
in a raw `extensions` dictionary.

## Converting track points to features

`gpxPointFeatures()` expands a track `MultiLineString` into individual
`Point` features. Each point keeps its time, elevation, name, comment,
description, source, symbol, type, links, and sensor extensions:

```swift
let points = track.gpxPointFeatures()

points.features[0].gpxHeartRate
points.features[0].gpxTime
points.features[0].gpxName
```

Non-Point features are skipped. The generated features have
`gpxType == .waypoint`, so they can be written as a GPX waypoint collection.

## Slicing

Time, distance, and fractional windows return a `FeatureCollection` of point
features.

```swift
let morning = track.gpxPointFeatures(from: startDate, to: endDate)
let lastKilometer = track.gpxPointFeatures(
    from: totalMeters - 1_000.0,
    to: totalMeters)
let middle = track.gpxPointFeatures(fraction: 0.33, to: 0.66)
```

Boundaries are inclusive. Time slicing requires timestamps; a track without
timestamps produces an empty collection for a time window. Distances are in
meters for EPSG:4326 (Haversine) and in projection units for projected
coordinates. Fractional windows are clamped to `0.0 ... 1.0`.

## Reconstructing a track

Point features produced by `gpxPointFeatures()` can be folded back into a
track:

```swift
let rebuilt = points.gpxTrackFromPointFeatures()
// or:
let rebuiltViaFeature = Feature(gpxTrackFrom: points)

rebuilt?.gpxHeartRates?[0]
rebuilt?.gpxTimes?.first
```

The result has a single segment and preserves per-point times, elevations,
sensor arrays, names, comments, descriptions, sources, symbols, types, links,
raw extensions, and quality fields. Lap boundaries from the original
`<trkseg>` elements are not reconstructed.

[waypointsroutestracks]: https://swiftpackageindex.com/Outdooractive/gis-tools-gpx/documentation/gistoolsgpx/waypointsroutestracks
