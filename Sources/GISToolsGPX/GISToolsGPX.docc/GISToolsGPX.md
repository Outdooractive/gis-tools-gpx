# ``GISToolsGPX``

Read and write GPX 1.1 (GPS Exchange Format) with waypoints, routes, tracks,
metadata, and Garmin extensions, mapped onto GISTools GeoJSON types.

## Overview

`GISToolsGPX` is a companion package for
[gis-tools](https://github.com/Outdooractive/gis-tools). It parses GPX files
into a `FeatureCollection` and writes them back as GPX 1.1 XML.

| GPX element | GeoJSON geometry | `gpxType` |
|---|---|---|
| `<wpt>` | `Point` | `.waypoint` |
| `<rte>` | `LineString` | `.route` |
| `<trk>` | `MultiLineString` | `.track` |

Waypoints, routes, and tracks keep their GPX-level metadata (`name`, `cmt`,
`desc`, `src`, links, `number`, `type`). Track and route points are exposed as
typed parallel arrays, and the full GPX `<metadata>` block is stored in the
collection's foreign members.

GPX 1.1 is read and written. GPX 1.0 is read-only; writing always produces GPX
1.1 and upgrades GPX 1.0 point fields where possible.

```swift
import GISTools
import GISToolsGPX

let collection = try GPXCoder.read(from: gpxURL)
for feature in collection.features {
    print(feature.gpxType as Any, feature.gpxName as Any)
}

try collection.writeGPX(to: outputURL)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:WaypointsRoutesTracks>

### Extensions and point data

- <doc:GarminExtensions>

### Writing and limitations

- <doc:WritingAndLimitations>

### Public API

- ``GPXCoder``
- ``GPXError``
- ``GPXElementType``
- ``GPSFixType``
- ``GPXLink``
- ``GPXPerson``
- ``GPXCopyright``
- ``GPXAddress``
- ``GPXPhoneNumber``
