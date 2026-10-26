#if canImport(FoundationXML)
import FoundationXML
#endif
import Foundation
import GISTools

// MARK: - Public API

extension GPXParser {

    /// Parses a GPX file from a URL and returns the intermediate model.
    ///
    /// - Parameter url: The URL of the GPX file.
    /// - Returns: A `GPXFile` containing the parsed data.
    /// - Throws: ``GPXError`` if parsing fails.
    static func parse(url: URL) throws -> GPXFile {
        if url.isFileURL,
           !FileManager.default.isReadableFile(atPath: url.path)
        {
            throw GPXError.fileReadError(detail: "Could not read file at \(url.path)")
        }
        guard let parser = XMLParser(contentsOf: url) else {
            throw GPXError.fileReadError(detail: "Could not open file at \(url.path)")
        }
        return try parse(parser: parser)
    }

    /// Parses a GPX file from a string and returns the intermediate model.
    ///
    /// - Parameter string: The GPX XML string.
    /// - Returns: A `GPXFile` containing the parsed data.
    /// - Throws: ``GPXError`` if parsing fails.
    static func parse(string: String) throws -> GPXFile {
        guard let data = string.data(using: .utf8) else {
            throw GPXError.invalidEncoding
        }
        let parser = XMLParser(data: data)
        return try parse(parser: parser)
    }

    /// Parses a GPX file from data and returns the intermediate model.
    ///
    /// - Parameter data: The GPX XML data.
    /// - Returns: A `GPXFile` containing the parsed data.
    /// - Throws: ``GPXError`` if parsing fails.
    static func parse(data: Data) throws -> GPXFile {
        let parser = XMLParser(data: data)
        return try parse(parser: parser)
    }

    // MARK: - Private

    private static func parse(parser: XMLParser) throws -> GPXFile {
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        let parsed = parser.parse()

        // Coordinate/version validation aborts the parser early; prefer the
        // specific error recorded by the delegate over XMLParser's generic one.
        if let error = delegate.parseError {
            throw error
        }

        guard parsed else {
            if let error = parser.parserError {
                throw GPXError.invalidXML(detail: error.localizedDescription)
            }
            throw GPXError.invalidXML(detail: "Unknown XML parse error")
        }

        guard let gpxFile = delegate.gpxFile else {
            throw GPXError.invalidGPX(detail: "No GPX root element found")
        }

        return gpxFile
    }

}

// MARK: - XMLParser Delegate

/// The namespace for the GPX parser. No public API exposed directly;
/// use `GPXParser` static methods.
enum GPXParser {

    /// Internal delegate for `XMLParser`. Not intended for external use.
    fileprivate final class GPXParserDelegate: NSObject, XMLParserDelegate {

        // MARK: - Parsed state

        var gpxFile: GPXFile?

        /// A specific parse error discovered by the delegate. The delegate
        /// aborts XML parsing after setting this.
        var parseError: GPXError?

        private var metadata: GPXMetadata?
        private var metadataLinks: [GPXLink] = []

        // GPX version from root element
        private var gpxVersion: String?
        private var isGPX10: Bool = false
        private var gpx10LinkURL: String?
        private var sawRootElement: Bool = false

        // Prefix → namespace URI declarations seen anywhere in the document.
        // Used to recognize Garmin extensions that use a non-standard prefix.
        private var declaredNamespaces: [String: String] = [:]

        private static let gpxNamespaceURIs: Set<String> = [
            "http://www.topografix.com/GPX/1/1",
            "http://www.topografix.com/GPX/1/0",
        ]

        // Accumulated characters for the current text node
        private var currentCharacters: String = ""

        // Element path stack (lowercased local names)
        private var pathStack: [String] = []

        // Track whether we're inside an <extensions> block
        private var extensionStackCount: Int = 0

        // Extension namespace → element → value accumulator for current point
        private var currentExtensions: [String: [String: Sendable]] = [:]
        private var currentExtensionPrefix: String?
        private var currentExtensionElement: String?

        // Structured extension tracking
        private var structuringAddress: Bool = false
        private var structuringCategories: Bool = false
        private var structuringPhoneNumber: Bool = false
        private var structuringRpt: Bool = false
        private var structuringDepth: Int = 0
        private var currentStructuredRootElement: String = ""
        private var currentStructuredDict: [String: Sendable] = [:]
        private var currentStructuredList: [Sendable] = []
        private var currentPhoneCategory: String?
        private var currentRptPoints: [[String: Double]] = []

        // In-progress model objects
        private var currentWaypoint: GPXWaypoint?
        private var waypointBuilders: [(GPXWaypoint) -> Void] = []

        private var currentLink: GPXLink?
        private var inLink: Bool = false
        private var currentLinkOwner: LinkOwner = .unknown

        private enum LinkOwner {
            case metadata
            case author
            case waypoint
            case route
            case track
            case unknown
        }

        private var currentPerson: GPXPerson?
        private var inAuthor: Bool = false

        private var currentCopyright: GPXCopyright?

        // For building complex elements
        private var currentLinks: [GPXLink] = []
        private var currentPoints: [GPXWaypoint] = []
        private var currentSegments: [[GPXWaypoint]] = []
        private var currentSegmentPoints: [GPXWaypoint] = []

        // Route being built
        private var currentRoute: GPXRoute?
        // Track being built
        private var currentTrack: GPXTrack?

        // Waypoint accumulation
        private var fileWaypoints: [GPXWaypoint] = []
        private var fileRoutes: [GPXRoute] = []
        private var fileTracks: [GPXTrack] = []

        // Parent context save/restore
        private var savedParentExtensions: [String: [String: Sendable]]? = nil
        private var savedParentLinks: [GPXLink]? = nil

        // MARK: - XMLParserDelegate

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            recordNamespaces(attributeDict)
            let localName = normalizedElementName(elementName)
            currentCharacters = ""
            pathStack.append(localName)

            if pathStack.count == 1 {
                sawRootElement = true
                if localName != "gpx" {
                    parseError = GPXError.invalidGPX(
                        detail: "Root element is '<\(elementName)>', expected '<gpx>'")
                    parser.abortParsing()
                    return
                }
            }

            let inExtension = extensionStackCount > 0

            if localName == "extensions" {
                extensionStackCount += 1
                resetStructuredState()
                return
            }

            if inExtension {
                handleExtensionStart(
                    originalName: elementName,
                    namespaceURI: namespaceURI,
                    qName: qName,
                    attributeDict: attributeDict)
                return
            }

            switch localName {
            case "gpx":
                handleGPXStart(attributeDict)
            case "metadata":
                handleMetadataStart()
            case "wpt", "rtept", "trkpt":
                handleWaypointStart(localName, attributeDict)
            case "rte":
                handleRouteStart()
            case "trk":
                handleTrackStart()
            case "trkseg":
                handleTrackSegmentStart()
            case "link":
                handleLinkStart(attributeDict)
            case "author":
                handleAuthorStart()
            case "copyright":
                handleCopyrightStart(attributeDict)
            case "email":
                handleEmailStart(attributeDict)
            case "bounds":
                handleBoundsStart(attributeDict)
            default:
                break
            }

            if parseError != nil {
                parser.abortParsing()
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let localName = normalizedElementName(elementName)

            if pathStack.last == localName {
                pathStack.removeLast()
            }

            if localName == "extensions" {
                extensionStackCount = max(0, extensionStackCount - 1)
                if extensionStackCount == 0 {
                    resetStructuredState()
                }
                return
            }

            if extensionStackCount > 0 {
                handleExtensionEnd(localName: localName)
                return
            }

            let chars = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

            switch localName {
            case "gpx":
                handleGPXEnd()
            case "metadata":
                handleMetadataEnd()
            case "wpt", "rtept", "trkpt":
                handleWaypointEnd(localName)
            case "rte":
                handleRouteEnd()
            case "trk":
                handleTrackEnd()
            case "trkseg":
                handleTrackSegmentEnd()
            case "link":
                handleLinkEnd(chars)
            case "author":
                handleAuthorEnd(chars)
            case "copyright":
                handleCopyrightEnd(chars)
            case "bounds":
                handleBoundsEnd()
            default:
                handleLeafElement(localName, chars)
            }
        }

        func parser(
            _ parser: XMLParser,
            foundCharacters string: String
        ) {
            currentCharacters += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            currentCharacters += String(data: CDATABlock, encoding: .utf8)
                ?? String(data: CDATABlock, encoding: .isoLatin1)
                ?? ""
        }

        // MARK: - Element handlers

        private func recordNamespaces(_ attrs: [String: String]) {
            for (key, value) in attrs {
                let lower = key.lowercased()
                guard lower.hasPrefix("xmlns:") else { continue }
                let prefix = String(lower.dropFirst("xmlns:".count))
                declaredNamespaces[prefix] = value
            }
        }

        /// Strips a namespace prefix when it is bound to a GPX namespace, so
        /// documents using `<gpx:wpt>` are parsed like default-namespace GPX.
        private func normalizedElementName(_ name: String) -> String {
            let parts = name.components(separatedBy: ":")
            guard parts.count == 2 else { return name.lowercased() }

            let prefix = parts[0].lowercased()
            guard let uri = declaredNamespaces[prefix],
                  Self.gpxNamespaceURIs.contains(uri)
            else {
                return name.lowercased()
            }
            return parts[1].lowercased()
        }

        private func handleGPXStart(_ attrs: [String: String]) {
            gpxVersion = attrs["version"]
            isGPX10 = (gpxVersion == "1.0")
            metadata = nil
            metadataLinks = []
            gpx10LinkURL = nil
            fileWaypoints = []
            fileRoutes = []
            fileTracks = []

            guard let version = gpxVersion else {
                parseError = GPXError.invalidGPX(
                    detail: "Missing required 'version' attribute on <gpx>")
                return
            }

            guard version == "1.1" || version == "1.0" else {
                parseError = GPXError.unsupportedVersion(version: version)
                return
            }
        }

        private func handleGPXEnd() {
            guard sawRootElement, let version = gpxVersion,
                  (version == "1.1" || version == "1.0")
            else { return }
            gpxFile = GPXFile(
                metadata: metadata,
                waypoints: fileWaypoints,
                routes: fileRoutes,
                tracks: fileTracks)
        }

        private func handleMetadataStart() {
            metadata = GPXMetadata()
            metadataLinks = []
            gpx10LinkURL = nil
        }

        private func handleMetadataEnd() {
            flushGPX10Link(into: &metadataLinks)

            var meta = metadata ?? GPXMetadata()
            meta.links = metadataLinks
            metadata = meta

            if meta.name == nil,
               meta.desc == nil,
               meta.author == nil,
               meta.copyright == nil,
               meta.links.isEmpty,
               meta.time == nil,
               meta.keywords == nil,
               meta.bounds == nil
            {
                metadata = nil
            }
        }

        private func handleWaypointStart(
            _ kind: String,
            _ attrs: [String: String]
        ) {
            guard let latStr = attrs["lat"],
                  let lonStr = attrs["lon"]
            else {
                parseError = GPXError.invalidGPX(
                    detail: "Waypoint '<\(kind)>' is missing 'lat' or 'lon'")
                return
            }

            guard let lat = Double(latStr),
                  let lon = Double(lonStr)
            else {
                parseError = GPXError.invalidCoordinate(
                    detail: "Unparsable coordinate lat='\(latStr)' lon='\(lonStr)'")
                return
            }

            guard lat.isFinite, lon.isFinite,
                  (-90.0 ... 90.0).contains(lat),
                  (-180.0 ... 180.0).contains(lon)
            else {
                parseError = GPXError.invalidCoordinate(
                    detail: "Coordinate out of range lat='\(lat)' lon='\(lon)'")
                return
            }

            currentWaypoint = GPXWaypoint(latitude: lat, longitude: lon)
            gpx10LinkURL = nil
            // Save parent context for child waypoints (rtept, trkpt)
            savedParentExtensions = nil
            savedParentLinks = nil
            if kind == "rtept" || kind == "trkpt" {
                savedParentExtensions = currentExtensions
                savedParentLinks = currentLinks
            }
            currentLinks = []
            currentExtensions = [:]

            switch kind {
            case "wpt":
                waypointBuilders.append { [weak self] wp in
                    self?.fileWaypoints.append(wp)
                }
            case "rtept":
                waypointBuilders.append { [weak self] wp in
                    self?.currentPoints.append(wp)
                }
            case "trkpt":
                waypointBuilders.append { [weak self] wp in
                    self?.currentSegmentPoints.append(wp)
                }
            default:
                break
            }
        }

        private func handleWaypointEnd(_ kind: String) {
            guard var wp = currentWaypoint else { return }
            // GPX 1.0: flush pending URL-only link
            flushGPX10Link(into: &currentLinks)
            wp.links = currentLinks
            wp.extensions = currentExtensions

            if let builder = waypointBuilders.popLast() {
                builder(wp)
            }
            currentWaypoint = nil
            // Restore parent context for child waypoints
            if let saved = savedParentLinks {
                currentLinks = saved
                savedParentLinks = nil
            }
            else {
                currentLinks = []
            }
            if let saved = savedParentExtensions {
                currentExtensions = saved
                savedParentExtensions = nil
            }
            else {
                currentExtensions = [:]
            }
        }

        private func handleRouteStart() {
            currentRoute = GPXRoute()
            currentPoints = []
            currentLinks = []
            currentExtensions = [:]
            gpx10LinkURL = nil
        }

        private func handleRouteEnd() {
            guard var route = currentRoute else { return }
            flushGPX10Link(into: &currentLinks)
            route.points = currentPoints
            route.links = currentLinks
            route.extensions = currentExtensions
            fileRoutes.append(route)
            currentRoute = nil
            currentPoints = []
            currentLinks = []
            currentExtensions = [:]
        }

        private func handleTrackStart() {
            currentTrack = GPXTrack()
            currentSegments = []
            currentLinks = []
            currentExtensions = [:]
            gpx10LinkURL = nil
        }

        private func handleTrackEnd() {
            guard var track = currentTrack else { return }
            flushGPX10Link(into: &currentLinks)
            track.segments = currentSegments
            track.links = currentLinks
            track.extensions = currentExtensions
            fileTracks.append(track)
            currentTrack = nil
            currentSegments = []
            currentLinks = []
            currentExtensions = [:]
        }

        private func handleTrackSegmentStart() {
            currentSegmentPoints = []
        }

        private func handleTrackSegmentEnd() {
            currentSegments.append(currentSegmentPoints)
            currentSegmentPoints = []
        }

        private func handleLinkStart(_ attrs: [String: String]) {
            currentLink = GPXLink(href: attrs["href"] ?? "")
            inLink = true

            let parent = pathStack.dropLast().last
            if inAuthor || parent == "author" {
                currentLinkOwner = .author
            }
            else if currentWaypoint != nil {
                currentLinkOwner = .waypoint
            }
            else if parent == "metadata" {
                currentLinkOwner = .metadata
            }
            else if currentRoute != nil, parent == "rte" {
                currentLinkOwner = .route
            }
            else if currentTrack != nil, parent == "trk" {
                currentLinkOwner = .track
            }
            else {
                currentLinkOwner = .unknown
            }
        }

        private func handleLinkEnd(_ chars: String) {
            inLink = false
            guard var link = currentLink else { return }

            if pathStack.last == "text" {
                link.text = chars
            }
            else if pathStack.last == "type" {
                link.type = chars
            }

            currentLink = nil
            let owner = currentLinkOwner
            currentLinkOwner = .unknown

            switch owner {
            case .metadata:
                metadataLinks.append(link)
            case .author:
                currentLinks.append(link)
            case .waypoint, .route, .track:
                currentLinks.append(link)
            case .unknown:
                break
            }
        }

        /// Appends a GPX 1.0 `<url>`/`<urlname>` pair when only the URL was
        /// present (no `<urlname>` follow-up).
        private func flushGPX10Link(into links: inout [GPXLink]) {
            guard isGPX10, let href = gpx10LinkURL else { return }
            links.append(GPXLink(href: href))
            gpx10LinkURL = nil
        }

        private func handleLinkLeaf(_ name: String, _ chars: String) {
            guard var link = currentLink else { return }

            switch name {
            case "text": link.text = chars
            case "type": link.type = chars
            default: break
            }

            currentLink = link
        }

        private func handleAuthorStart() {
            currentPerson = GPXPerson()
            currentLink = nil
            currentLinks = []
            inAuthor = true
        }

        private func handleAuthorEnd(_ chars: String) {
            guard var person = currentPerson else { return }
            inAuthor = false

            // GPX 1.0 stores the author as plain text.
            if isGPX10, !chars.isEmpty {
                person.name = chars
            }

            if person.link == nil, let link = currentLinks.first {
                person.link = link
            }
            if var meta = metadata {
                if isGPX10, let existing = meta.author {
                    var merged = existing
                    if let name = person.name { merged.name = name }
                    if let email = person.email { merged.email = email }
                    if let link = person.link { merged.link = link }
                    person = merged
                }
                meta.author = person
                metadata = meta
            }
            currentPerson = nil
            currentLinks = []
            currentLink = nil
        }

        private func handleCopyrightStart(_ attrs: [String: String]) {
            currentCopyright = GPXCopyright(
                author: attrs["author"] ?? "",
                year: nil,
                license: nil)
        }

        private func handleEmailStart(_ attrs: [String: String]) {
            let id = attrs["id"] ?? ""
            let domain = attrs["domain"] ?? ""
            guard !id.isEmpty || !domain.isEmpty else { return }

            var person = currentPerson ?? GPXPerson()
            if domain.isEmpty {
                person.email = id
            }
            else {
                person.email = "\(id)@\(domain)"
            }
            currentPerson = person
        }

        private func handleCopyrightEnd(_ chars: String) {
            guard let cr = currentCopyright else { return }

            if var meta = metadata {
                meta.copyright = cr
                metadata = meta
            }
            currentCopyright = nil
        }

        private func handleBoundsStart(_ attrs: [String: String]) {
            guard let minlatStr = attrs["minlat"],
                  let minlonStr = attrs["minlon"],
                  let maxlatStr = attrs["maxlat"],
                  let maxlonStr = attrs["maxlon"],
                  let minlat = Double(minlatStr),
                  let minlon = Double(minlonStr),
                  let maxlat = Double(maxlatStr),
                  let maxlon = Double(maxlonStr)
            else { return }
            var meta = metadata ?? GPXMetadata()
            meta.bounds = BoundingBox(
                southWest: Coordinate3D(latitude: minlat, longitude: minlon),
                northEast: Coordinate3D(latitude: maxlat, longitude: maxlon))
            metadata = meta
        }

        private func handleBoundsEnd() {
            // Bounds attributes are handled inline; no-op for end.
        }

        private func handleLeafElement(
            _ localName: String,
            _ chars: String
        ) {
            let parent = pathStack.last ?? ""
            let grandparent = pathStack.dropLast().last ?? ""

            // Link text/type children
            if inLink {
                handleLinkLeaf(localName, chars)
                return
            }

            // Author children (must check before metadata grandparent)
            if inAuthor {
                handleAuthorLeaf(localName, chars)
                return
            }

            // Copyright children (must check before metadata grandparent)
            if parent == "copyright" {
                handleCopyrightLeaf(localName, chars)
                return
            }

            // GPX Metadata children
            if grandparent == "metadata" || parent == "metadata" {
                handleMetadataLeaf(localName, chars, parent: parent)
                return
            }

            // Bounds children
            if grandparent == "bounds" {
                handleBoundsLeaf(localName, chars)
                return
            }

            // Waypoint children
            if currentWaypoint != nil {
                handleWaypointLeaf(localName, chars)
                return
            }

            // Route children (non-wpt)
            if currentRoute != nil, parent == "rte" {
                handleRouteLeaf(localName, chars)
                return
            }

            // Track children (non-trkpt)
            if currentTrack != nil, parent == "trk" {
                handleTrackLeaf(localName, chars)
                return
            }
        }

        private func handleMetadataLeaf(_ name: String, _ chars: String, parent: String) {
            var meta = metadata ?? GPXMetadata()
            let p = parent

            switch (p, name) {
            case ("metadata", "name"): meta.name = chars
            case ("metadata", "desc"): meta.desc = chars
            case ("metadata", "time"): meta.time = GPXDateFormatter.parse(chars)
            case ("metadata", "keywords"): meta.keywords = chars
            case ("metadata", "email"):
                // GPX 1.0 stores the email as plain text, not id/domain attributes.
                if isGPX10, !chars.isEmpty {
                    var person = meta.author ?? GPXPerson()
                    person.email = chars
                    meta.author = person
                }
            case ("metadata", "url"):
                if isGPX10, !chars.isEmpty {
                    gpx10LinkURL = chars
                }
            case ("metadata", "urlname"):
                if isGPX10 {
                    let href = gpx10LinkURL ?? ""
                    if !href.isEmpty || !chars.isEmpty {
                        metadataLinks.append(GPXLink(
                            href: href,
                            text: chars.isEmpty ? nil : chars))
                        gpx10LinkURL = nil
                    }
                }
            default: break
            }

            metadata = meta
        }

        private func handleAuthorLeaf(_ name: String, _ chars: String) {
            guard var person = currentPerson else { return }

            switch name {
            case "name": person.name = chars
            case "email":
                // email is in id/domain child elements, handled via link-like parsing
                break
            default: break
            }

            currentPerson = person
        }

        private func handleCopyrightLeaf(_ name: String, _ chars: String) {
            guard var cr = currentCopyright else { return }

            switch name {
            case "year": cr.year = Int(chars)
            case "license": cr.license = chars
            default: break
            }

            currentCopyright = cr
        }

        private func handleBoundsLeaf(_ name: String, _ chars: String) {
            guard let value = Double(chars) else { return }

            var meta = metadata ?? GPXMetadata()
            let existingBounds = meta.bounds
            var minlat = existingBounds?.southWest.latitude ?? 0.0
            var minlon = existingBounds?.southWest.longitude ?? 0.0
            var maxlat = existingBounds?.northEast.latitude ?? 0.0
            var maxlon = existingBounds?.northEast.longitude ?? 0.0

            switch name {
            case "minlat": minlat = value
            case "minlon": minlon = value
            case "maxlat": maxlat = value
            case "maxlon": maxlon = value
            default: break
            }

            meta.bounds = BoundingBox(
                southWest: Coordinate3D(latitude: minlat, longitude: minlon),
                northEast: Coordinate3D(latitude: maxlat, longitude: maxlon))
            metadata = meta
        }

        private func handleWaypointLeaf(_ name: String, _ chars: String) {
            guard var wp = currentWaypoint else { return }

            switch name {
            case "ele": wp.elevation = Double(chars)
            case "time": wp.time = GPXDateFormatter.parse(chars)
            case "magvar": wp.magneticVariation = Double(chars)
            case "geoidheight": wp.geoidHeight = Double(chars)
            case "name": wp.name = chars
            case "cmt": wp.comment = chars
            case "desc": wp.description = chars
            case "src": wp.source = chars
            case "sym": wp.symbol = chars
            case "type": wp.type = chars
            case "fix": wp.fix = GPSFixType(rawValue: chars)
            case "sat": wp.satellites = Int(chars)
            case "hdop": wp.horizontalDilution = Double(chars)
            case "vdop": wp.verticalDilution = Double(chars)
            case "pdop": wp.positionDilution = Double(chars)
            case "ageofdgpsdata": wp.ageOfDGPSData = Double(chars)
            case "dgpsid": wp.dgpsid = Int(chars)
            // GPX 1.0 track point elements
            case "course": wp.course = Double(chars)
            case "speed": wp.speed = Double(chars)
            // GPX 1.0 flat link elements
            case "url":
                if isGPX10, !chars.isEmpty { gpx10LinkURL = chars }
            case "urlname":
                if isGPX10 {
                    let href = gpx10LinkURL ?? ""
                    if !href.isEmpty || !chars.isEmpty {
                        currentLinks.append(GPXLink(
                            href: href,
                            text: chars.isEmpty ? nil : chars))
                        gpx10LinkURL = nil
                    }
                }
            default: break
            }

            currentWaypoint = wp
        }

        private func handleRouteLeaf(_ name: String, _ chars: String) {
            guard var route = currentRoute else { return }

            switch name {
            case "name": route.name = chars
            case "cmt": route.comment = chars
            case "desc": route.description = chars
            case "src": route.source = chars
            case "number": route.number = Int(chars)
            case "type": route.type = chars
            case "url":
                if isGPX10, !chars.isEmpty { gpx10LinkURL = chars }
            case "urlname":
                if isGPX10 {
                    let href = gpx10LinkURL ?? ""
                    if !href.isEmpty || !chars.isEmpty {
                        currentLinks.append(GPXLink(
                            href: href,
                            text: chars.isEmpty ? nil : chars))
                        gpx10LinkURL = nil
                    }
                }
            default: break
            }

            currentRoute = route
        }

        private func handleTrackLeaf(_ name: String, _ chars: String) {
            guard var track = currentTrack else { return }

            switch name {
            case "name": track.name = chars
            case "cmt": track.comment = chars
            case "desc": track.description = chars
            case "src": track.source = chars
            case "number": track.number = Int(chars)
            case "type": track.type = chars
            case "url":
                if isGPX10, !chars.isEmpty { gpx10LinkURL = chars }
            case "urlname":
                if isGPX10 {
                    let href = gpx10LinkURL ?? ""
                    if !href.isEmpty || !chars.isEmpty {
                        currentLinks.append(GPXLink(
                            href: href,
                            text: chars.isEmpty ? nil : chars))
                        gpx10LinkURL = nil
                    }
                }
            default: break
            }

            currentTrack = track
        }

        // MARK: - Extension handling

        private func resolvedExtensionNamespace(
            for prefix: String
        ) -> GPXExtensionNamespace? {
            if let uri = declaredNamespaces[prefix.lowercased()],
               let ns = GPXExtensionNamespace.namespace(forURI: uri)
            {
                return ns
            }
            return GPXExtensionNamespace.namespace(forPrefix: prefix)
        }

        private func handleExtensionStart(
            originalName: String,
            namespaceURI: String?,
            qName: String?,
            attributeDict: [String: String]
        ) {
            // With namespace processing disabled, parse prefix from element name
            let colonParts = originalName.components(separatedBy: ":")
            let hasPrefix = colonParts.count == 2
            let strippedName = hasPrefix ? colonParts[1] : originalName
            let lower = strippedName.lowercased()
            let prefix: String? = hasPrefix ? colonParts[0] : nil

            guard let prefix else { return }
            guard let ns = resolvedExtensionNamespace(for: prefix) else { return }

            switch lower {
            case "address":
                if structuringDepth == 0 { currentStructuredRootElement = "Address" }
                structuringAddress = true
                structuringDepth += 1
                currentStructuredDict = [:]
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            case "categories":
                if structuringDepth == 0 { currentStructuredRootElement = "Categories" }
                structuringCategories = true
                structuringDepth += 1
                currentStructuredList = []
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            case "phonenumber":
                if structuringDepth == 0 { currentStructuredRootElement = "PhoneNumber" }
                structuringPhoneNumber = true
                structuringDepth += 1
                currentStructuredList = []
                currentPhoneCategory = attributeDict["category"] ?? attributeDict["Category"]
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            case "rpt":
                if structuringDepth == 0 { currentStructuredRootElement = "rpt" }
                structuringRpt = true
                structuringDepth += 1
                currentRptPoints = []
                if let latStr = attributeDict["lat"],
                   let lonStr = attributeDict["lon"],
                   let lat = Double(latStr),
                   let lon = Double(lonStr)
                {
                    currentRptPoints.append(["lat": lat, "lon": lon])
                }
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            default:
                // Child of a structured element — increment depth
                if structuringAddress || structuringCategories || structuringPhoneNumber || structuringRpt {
                    structuringDepth += 1
                }
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            }
        }

        private func handleExtensionEnd(localName: String) {
            guard let prefix = currentExtensionPrefix,
                  let element = currentExtensionElement
            else {
                resetStructuredState()
                return
            }

            // Strip prefix from localName for comparison (namespace processing disabled)
            let colonParts = localName.components(separatedBy: ":")
            let strippedLocal = colonParts.count == 2 ? colonParts[1] : localName
            let lower = strippedLocal.lowercased()
            let chars = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

            // Handle structured extensions
            if structuringAddress {
                structuringDepth -= 1
                if structuringDepth == 0 {
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                else {
                    handleAddressChild(strippedLocal, chars)
                }
                return
            }

            if structuringCategories {
                structuringDepth -= 1
                if structuringDepth == 0 {
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                else {
                    handleCategoryChild(strippedLocal, chars)
                }
                return
            }

            if structuringPhoneNumber {
                structuringDepth -= 1
                if structuringDepth == 0 {
                    handlePhoneNumberChild(strippedLocal, chars)
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                return
            }

            if structuringRpt {
                structuringDepth -= 1
                if structuringDepth == 0 {
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                return
            }

            // Handle wrappers that contain children
            if lower == "trackpointextension"
                || lower == "routepointextension"
                || lower == "waypointextension"
                || lower == "routeextension"
                || lower == "trackextension"
            {
                // Flatten wrapper: copy children into extensions directly
                for (childKey, childValue) in currentStructuredDict {
                    var nsDict = currentExtensions[prefix] ?? [:]
                    nsDict[childKey] = childValue
                    currentExtensions[prefix] = nsDict
                }
                currentStructuredDict = [:]
                currentExtensionPrefix = nil
                currentExtensionElement = nil
                return
            }

            // Sniff wrapper children
            if !currentStructuredDict.isEmpty {
                let inferred = inferExtensionValue(chars)
                if !(inferred is String) || (inferred as? String)?.isEmpty == false {
                    currentStructuredDict[localName] = inferred
                }
                if lower == element.lowercased() {
                    // Done collecting wrapper children
                    currentExtensionPrefix = nil
                    currentExtensionElement = nil
                }
                return
            }

            // Leaf extension element
            let knownChildren = GPXExtensionNamespace.children(for: prefix)
            let canonicalChild = knownChildren.first { $0.lowercased() == lower }
            if lower == element.lowercased() || canonicalChild != nil {
                let keyName = lower == element.lowercased()
                    ? element
                    : (canonicalChild ?? strippedLocal)
                let inferred = inferExtensionValue(chars)
                let isEmptyStr: Bool = {
                    if let s = inferred as? String { return s.isEmpty }
                    return false
                }()
                if !isEmptyStr {
                    var nsDict = currentExtensions[prefix] ?? [:]
                    nsDict[keyName] = inferred
                    currentExtensions[prefix] = nsDict
                }
                currentExtensionPrefix = nil
                currentExtensionElement = nil
            }
        }

        // MARK: - Structured extension helpers

        private func handleAddressChild(_ name: String, _ chars: String) {
            let canonical: String?
            switch name.lowercased() {
            case "streetaddress": canonical = "StreetAddress"
            case "city": canonical = "City"
            case "state": canonical = "State"
            case "country": canonical = "Country"
            case "postalcode": canonical = "PostalCode"
            default: canonical = nil
            }

            guard let canonical, !chars.isEmpty else { return }

            if canonical == "StreetAddress" {
                var streets = currentStructuredDict["StreetAddress"] as? [String] ?? []
                streets.append(chars)
                currentStructuredDict["StreetAddress"] = streets as Sendable
            }
            else {
                currentStructuredDict[canonical] = chars
            }
        }

        private func handleCategoryChild(_ name: String, _ chars: String) {
            let lower = name.lowercased()
            if (lower == "category" || lower == "categories"), !chars.isEmpty {
                currentStructuredList.append(chars)
            }
            // Ignore the parent element ending
        }

        private func handlePhoneNumberChild(_ elementName: String, _ chars: String) {
            let value = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                var entry: [String: Sendable] = ["value": value]
                if let cat = currentPhoneCategory {
                    entry["category"] = cat
                }
                currentStructuredList.append(entry)
            }
        }

        private func handleRptChild(_ elementName: String, _ chars: String) {
            // rpt points have lat/lon attributes handled in start
        }

        private func finalizeStructuredExtension(prefix: String, element: String) {
            let key = currentStructuredRootElement.isEmpty ? element : currentStructuredRootElement
            if structuringAddress, !currentStructuredDict.isEmpty {
                var nsDict = currentExtensions[prefix] ?? [:]
                nsDict[key] = currentStructuredDict as [String: Sendable]
                currentExtensions[prefix] = nsDict
            }
            else if structuringCategories, !currentStructuredList.isEmpty {
                var nsDict = currentExtensions[prefix] ?? [:]
                if var existing = nsDict[key] as? [Sendable] {
                    existing.append(contentsOf: currentStructuredList)
                    nsDict[key] = existing
                }
                else {
                    nsDict[key] = currentStructuredList
                }
                currentExtensions[prefix] = nsDict
            }
            else if structuringPhoneNumber, !currentStructuredList.isEmpty {
                var nsDict = currentExtensions[prefix] ?? [:]
                if var existing = nsDict[key] as? [Sendable] {
                    existing.append(contentsOf: currentStructuredList)
                    nsDict[key] = existing
                }
                else {
                    nsDict[key] = currentStructuredList
                }
                currentExtensions[prefix] = nsDict
            }
            else if structuringRpt {
                var nsDict = currentExtensions[prefix] ?? [:]
                if var existing = nsDict[key] as? [Sendable] {
                    existing.append(contentsOf: currentRptPoints as [Sendable])
                    nsDict[key] = existing
                }
                else {
                    nsDict[key] = currentRptPoints as [Sendable]
                }
                currentExtensions[prefix] = nsDict
            }
            resetStructuredState()
        }

        private func resetStructuredState() {
            structuringAddress = false
            structuringCategories = false
            structuringPhoneNumber = false
            structuringRpt = false
            structuringDepth = 0
            currentStructuredRootElement = ""
            currentStructuredDict = [:]
            currentStructuredList = []
            currentPhoneCategory = nil
            currentRptPoints = []
            currentExtensionPrefix = nil
            currentExtensionElement = nil
        }

        private func inferExtensionValue(_ string: String) -> Sendable {
            // Check for boolean
            let lower = string.lowercased()
            if lower == "true" { return true }
            if lower == "false" { return false }

            // Preserve identifiers with leading zeros (e.g. "007").
            if string.count > 1, string.hasPrefix("0"), !string.hasPrefix("0.") {
                return string
            }

            // Try Double
            if let d = Double(string) {
                // If whole number, try Int for clean representation
                if d == floor(d), d >= Double(Int.min), d <= Double(Int.max) {
                    return Int(d)
                }
                return d
            }

            return string
        }

    }

}
