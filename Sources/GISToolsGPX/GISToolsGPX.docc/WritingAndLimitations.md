# Writing and limitations

## What is written

`GPXCoder.write(_:creator:)`, `GPXCoder.write(_:to:creator:)` and
`FeatureCollection.writeGPX(to:)` write a complete GPX 1.1 document:

- XML declaration and a `<gpx>` root with `version="1.1"` and `creator`
- `<metadata>` in schema order (name, desc, author, copyright, links, time,
  keywords, bounds)
- `<wpt>`, `<rte>`, and `<trk>` elements in collection order
- route/track metadata and extensions before route points or track segments
- per-point standard fields, links, and extensions
- Garmin extension namespaces and context-appropriate wrappers
- ISO 8601 timestamps with fractional seconds

Element text and attributes are XML-escaped. Characters that are not legal in
XML 1.0 (for example U+0000) are removed. Coordinates are written with up to
15 significant digits using a locale-independent formatter.

## Projection

GPX is defined in WGS84 (EPSG:4326). Known projected collections (EPSG:3857,
EPSG:4978, UTM, national grids, and so on) are reprojected to EPSG:4326 before
writing. `noSRID` collections are written unchanged, and their coordinates are
validated against the WGS84 ranges. Reading always yields EPSG:4326.

## Fidelity

The following survive a read → write → read cycle:

- waypoint, route, and track element types and geometry
- waypoint fields, links, and extensions
- route and track metadata and links
- route-point times, names, comments, descriptions, sources, symbols, types,
  links, and raw extensions
- track-point times, elevations, sensor arrays, names, comments, descriptions,
  sources, symbols, types, links, raw extensions, and quality fields
- the complete metadata block
- Garmin `gpxtpx` and `gpxx` extension values that were parsed

## GPX 1.0

GPX 1.0 is read-only. Writing always emits GPX 1.1.

- Plain-text `<author>` and `<email>` in metadata become the author name and
  email.
- Flat `<url>`/`<urlname>` links are converted to `GPXLink`.
- Track-point `<course>` and `<speed>` are exposed through the course/speed
  arrays and written back as gpxtpx extensions.
- Waypoint `<course>`/`<speed>` are written back as gpxtpx extensions.
- Route-point `<course>`/`<speed>` are not preserved.

## Limitations

- Only the `gpxtpx` and `gpxx` extension namespaces are recognized. Custom
  namespaces are not parsed and are not written.
- Extension elements must use a namespace prefix. A default namespace declared
  directly on an `<extensions>` element is not supported.
- Metadata `<extensions>` are not represented in the model.
- Route-point GNSS quality fields (`fix`, `sat`, `dop`, `magvar`,
  `geoidheight`, `ageofdgpsdata`, `dgpsid`) are not preserved.
- Track reconstruction creates a single segment; original `<trkseg>`
  boundaries are not recovered.
- The model does not write GPX 1.0 output.
- Unknown prefixes in a user-built `extensions` dictionary are skipped rather
  than written.
- `noSRID` coordinates are assumed to already be WGS84 values.
