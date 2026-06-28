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
    /// - Returns: A ``GPXFile`` containing the parsed data.
    /// - Throws: ``GPXError`` if parsing fails.
    static func parse(url: URL) throws -> GPXFile {
        guard let parser = XMLParser(contentsOf: url) else {
            throw GPXError.fileReadError(detail: "Could not open file at \(url.path)")
        }
        return try parse(parser: parser)
    }

    /// Parses a GPX file from a string and returns the intermediate model.
    ///
    /// - Parameter string: The GPX XML string.
    /// - Returns: A ``GPXFile`` containing the parsed data.
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
    /// - Returns: A ``GPXFile`` containing the parsed data.
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

        guard parser.parse() else {
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
/// use ``GPXParser`` static methods.
enum GPXParser {

    /// Internal delegate for `XMLParser`. Not intended for external use.
    fileprivate final class GPXParserDelegate: NSObject, XMLParserDelegate {

        // MARK: - Parsed state

        var gpxFile: GPXFile?

        private var metadata: GPXMetadata?

        // GPX version from root element
        private var gpxVersion: String?
        private var isGPX10: Bool = false
        private var gpx10LinkURL: String?

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

        // MARK: - XMLParserDelegate

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let localName = elementName.lowercased()
            currentCharacters = ""
            pathStack.append(localName)

            let inExtension = extensionStackCount > 0

            if localName == "extensions" {
                extensionStackCount += 1
                currentExtensions = [:]
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
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let localName = elementName.lowercased()

            if pathStack.last == localName {
                pathStack.removeLast()
            }

            if localName == "extensions" {
                extensionStackCount -= 1
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
                handleAuthorEnd()
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

        // MARK: - Element handlers

        private func handleGPXStart(_ attrs: [String: String]) {
            gpxVersion = attrs["version"]
            isGPX10 = (gpxVersion == "1.0")
            metadata = nil
            fileWaypoints = []
            fileRoutes = []
            fileTracks = []
        }

        private func handleGPXEnd() {
            guard let version = gpxVersion,
                  (version == "1.1" || version == "1.0")
            else { return }
            gpxFile = GPXFile(
                metadata: metadata,
                waypoints: fileWaypoints,
                routes: fileRoutes,
                tracks: fileTracks)
        }

        private func handleWaypointStart(
            _ kind: String,
            _ attrs: [String: String]
        ) {
            guard let latStr = attrs["lat"],
                  let lonStr = attrs["lon"],
                  let lat = Double(latStr),
                  let lon = Double(lonStr)
            else { return }

            currentWaypoint = GPXWaypoint(latitude: lat, longitude: lon)
            currentLinks = []
            // Save parent extensions for child waypoints (rtept, trkpt)
            savedParentExtensions = nil
            if kind == "rtept" || kind == "trkpt" {
                savedParentExtensions = currentExtensions
            }
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
            if isGPX10, let href = gpx10LinkURL {
                currentLinks.append(GPXLink(href: href))
                gpx10LinkURL = nil
            }
            wp.links = currentLinks
            wp.extensions = currentExtensions

            if let builder = waypointBuilders.popLast() {
                builder(wp)
            }
            currentWaypoint = nil
            currentLinks = []
            // Restore parent extensions for child waypoints
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
        }

        private func handleRouteEnd() {
            guard var route = currentRoute else { return }
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
        }

        private func handleTrackEnd() {
            guard var track = currentTrack else { return }
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
        }

        private func handleLinkEnd(_ chars: String) {
            guard var link = currentLink else { return }
            inLink = false

            if pathStack.last == "text" {
                link.text = chars
            }
            else if pathStack.last == "type" {
                link.type = chars
            }

            if let parent = pathStack.dropLast().last {
                switch parent {
                case "link":
                    // Nested link text/type element ended — just update the link
                    currentLink = link
                    return
                default:
                    break
                }
            }

            currentLinks.append(link)
            currentLink = nil
            // If we're directly inside metadata, add link to metadata
            if pathStack.last == "metadata" || pathStack.dropLast().last == "metadata" {
                var meta = metadata ?? GPXMetadata()
                meta.links = currentLinks
                metadata = meta
            }
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

        private func handleAuthorEnd() {
            guard var person = currentPerson else { return }
            inAuthor = false
            if person.link == nil, let link = currentLinks.first {
                person.link = link
            }
            if var meta = metadata {
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
            var person = currentPerson ?? GPXPerson()
            let id = attrs["id"] ?? ""
            let domain = attrs["domain"] ?? ""
            if !id.isEmpty || !domain.isEmpty {
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
            default: break
            }

            currentTrack = track
        }

        // MARK: - Extension handling

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
            guard let ns = GPXExtensionNamespace.namespace(forPrefix: prefix) else { return }

            switch lower {
            case "address":
                if structuringDepth == 0 { currentStructuredRootElement = strippedName }
                structuringAddress = true
                structuringDepth += 1
                currentStructuredDict = [:]
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            case "categories":
                if structuringDepth == 0 { currentStructuredRootElement = strippedName }
                structuringCategories = true
                structuringDepth += 1
                currentStructuredList = []
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            case "phonenumber":
                if structuringDepth == 0 { currentStructuredRootElement = strippedName }
                structuringPhoneNumber = true
                structuringDepth += 1
                currentStructuredList = []
                currentPhoneCategory = attributeDict["category"] ?? attributeDict["Category"]
                currentExtensionPrefix = ns.prefix
                currentExtensionElement = strippedName
            case "rpt":
                if structuringDepth == 0 { currentStructuredRootElement = strippedName }
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
                handleAddressChild(element, chars)
                structuringDepth -= 1
                if structuringDepth == 0 {
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                return
            }

            if structuringCategories {
                handleCategoryChild(element, chars)
                structuringDepth -= 1
                if structuringDepth == 0 {
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                return
            }

            if structuringPhoneNumber {
                handlePhoneNumberChild(element, chars)
                structuringDepth -= 1
                if structuringDepth == 0 {
                    finalizeStructuredExtension(prefix: prefix, element: element)
                }
                return
            }

            if structuringRpt {
                handleRptChild(element, chars)
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
            if lower == element.lowercased()
                || GPXExtensionNamespace.children(for: prefix).contains(strippedLocal)
            {
                let inferred = inferExtensionValue(chars)
                let isEmptyStr: Bool = {
                    if let s = inferred as? String { return s.isEmpty }
                    return false
                }()
                if !isEmptyStr {
                    var nsDict = currentExtensions[prefix] ?? [:]
                    nsDict[element] = inferred
                    currentExtensions[prefix] = nsDict
                }
                currentExtensionPrefix = nil
                currentExtensionElement = nil
            }
        }

        // MARK: - Structured extension helpers

        private func handleAddressChild(_ name: String, _ chars: String) {
            let lower = name.lowercased()
            if lower == "streetaddress" {
                var streets = currentStructuredDict["StreetAddress"] as? [String] ?? []
                if !chars.isEmpty { streets.append(chars) }
                currentStructuredDict["StreetAddress"] = streets as Sendable
            }
            else if !chars.isEmpty {
                currentStructuredDict[name] = chars
            }
        }

        private func handleCategoryChild(_ name: String, _ chars: String) {
            if name.lowercased() == "category", !chars.isEmpty {
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
                nsDict[key] = currentStructuredList
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
