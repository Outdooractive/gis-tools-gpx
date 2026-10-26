# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Dependency

- Update `gis-tools` from `3.0.0-beta.1` to `3.0.0-beta.5`.
- Adapt to optional `Feature.geometry` in gis-tools 3.0.

### Added

- `Feature.gpxElevation`, `gpxMagneticVariation`, `gpxGeoidHeight`,
  `gpxAgeOfDGPSData`, and `gpxDGPSID` typed accessors.
- Track-point arrays: `gpxWaterTemperatures`, `gpxDepths`, `gpxBearings`,
  `gpxTrackNames`, `gpxTrackComments`, `gpxTrackDescriptions`,
  `gpxTrackSources`, `gpxTrackSymbols`, `gpxTrackTypes`, `gpxTrackLinks`,
  `gpxTrackPointExtensions`, and `gpxTrackPointQuality`.
- DocC catalog with getting-started, element mapping, extension/slicing, and
  writing/limitation articles.
- CI coverage artifacts and a Linux test job; documentation build validation.

### Fixed
- Mismatched XML closing tags are now rejected consistently, including on
  Linux toolchains whose XMLParser accepts them.

- Writer: route and track `<extensions>` now precede route points and track
  segments, matching the GPX 1.1 schema order.
- Writer: Garmin `gpxx` extensions use context-appropriate wrappers
  (`WaypointExtension`, `RouteExtension`, `TrackExtension`,
  `RoutePointExtension`, `TrackPointExtension`) instead of the invalid
  `<gpxx:Extension>`.
- Writer: categories are emitted as a `<Categories>` parent with singular
  `<Category>` children, and phone numbers use the canonical `Category`
  attribute.
- Writer: coordinates use a locale-independent formatter with 15 significant
  digits; illegal XML characters are removed; emails without `@` are emitted
  as valid `id`/`domain` attributes.
- Writer: projected collections are reprojected to EPSG:4326; out-of-range or
  non-finite coordinates throw `GPXError.invalidCoordinate`.
- Parser: metadata links before or after `<author>` are no longer lost.
- Parser: route-level and track-level links survive route/track points.
- Parser: multiple `<extensions>` blocks on one element are merged.
- Parser: structured Garmin values are no longer duplicated at parent element
  boundaries; lowercase Garmin element names are canonicalized.
- Parser: non-standard prefixes bound to the Garmin namespaces are resolved
  through their `xmlns` declarations.
- Parser: GPX 1.0 plain-text author/email and metadata/route/track
  `url`/`urlname` links are supported.
- Parser: missing or unsupported versions, invalid roots, missing coordinates,
  and out-of-range coordinates report specific `GPXError` cases.
- Parser: CDATA content is decoded.
- Track points: unknown gpxtpx fields, GNSS quality fields, names, comments,
  descriptions, sources, symbols, types, and links survive round-trips.
- Point features: `gpxPointFeatures()` now writes timestamps in the format the
  reader expects, includes course/water temperature/depth/bearing, and
  preserves metadata, links, and raw extensions.
- Slicing: time windows work when some points have no timestamp; tracks
  without timestamps return an empty collection instead of all points.
- Track reconstruction: whole-number extension values are handled, and times,
  elevations, metadata, links, raw extensions, and quality fields are
  restored.

### Changed

- Invalid GPX input is rejected with `GPXError` instead of silently dropping
  malformed waypoints.
- `FeatureCollection.writeGPX(to:)` wraps file-system failures in
  `GPXError.fileWriteError`.
- `FeatureCollection.gpxMetadataLinks` also accepts single-dictionary storage.

### Tests

- Add parser robustness, writer validity, point-feature/slicing, and API
  consistency suites. The suite grew from 54 to 119 tests and package line
  coverage from about 80% to about 93%.
