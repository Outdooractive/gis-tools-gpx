# Getting started

Install `GISToolsGPX` next to `GISTools` and read a GPX file into a
`FeatureCollection`.

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/Outdooractive/gis-tools",
        from: "3.0.0"),
    .package(
        url: "https://github.com/Outdooractive/gis-tools-gpx",
        from: "1.0.0"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "GISTools", package: "gis-tools"),
            .product(name: "GISToolsGPX", package: "gis-tools-gpx"),
        ]),
]
```

The package needs Swift 6.1 or newer. It supports iOS 15+, macOS 15+, tvOS 15+,
watchOS 7+, Linux, Android, and WebAssembly.

## Reading

Use ``GPXCoder`` for throwing reads or the optional convenience initializer:

```swift
import GISTools
import GISToolsGPX

let collection = try GPXCoder.read(from: gpxURL)

// Optional convenience initializer:
if let collection = FeatureCollection(gpx: gpxURL) {
    print(collection.features.count)
}

// Read from Data instead of a file:
let fromData = try GPXCoder.read(from: gpxData)

// Read from an in-memory XML string:
let fromString = try GPXCoder.read(from: Data(xmlString.utf8))
```

Reading always returns EPSG:4326 coordinates. Every feature carries a
`Feature.gpxType` value so waypoints, routes, and tracks can be filtered:

```swift
let waypoints = collection.gpxWaypoints
let routes = collection.gpxRoutes
let tracks = collection.gpxTracks
```

## Writing

```swift
try collection.writeGPX(to: outputURL)
try collection.writeGPX(to: outputURL, creator: "My App")

// Data instead of a file:
let data = try collection.gpxData()
let dataViaCoder = try GPXCoder.write(collection)
```

GPX only supports WGS84 coordinates. A collection with a known projected CRS
(for example EPSG:3857 or EPSG:4978) is reprojected to EPSG:4326 before
writing. `noSRID` collections are written as-is, so their values must already
be valid latitudes and longitudes; otherwise ``GPXError/invalidCoordinate(detail:)``
is thrown.

## Error handling

All reading and writing failures are reported as ``GPXError``:

```swift
do {
    let collection = try GPXCoder.read(from: url)
    try collection.writeGPX(to: outputURL)
}
catch let error as GPXError {
    print(error.localizedDescription)
}
```

Malformed XML produces ``GPXError/invalidXML(detail:)``, non-GPX documents and
missing required attributes produce ``GPXError/invalidGPX(detail:)``, versions
other than 1.0 and 1.1 produce ``GPXError/unsupportedVersion(version:)``, and
invalid or out-of-range coordinates produce
``GPXError/invalidCoordinate(detail:)``.
