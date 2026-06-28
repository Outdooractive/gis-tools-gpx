import Foundation

// MARK: - GPX XML Writer

/// Writes a ``GPXFile`` model to a GPX 1.1 XML string.
enum GPXWriter {

    /// Writes the GPX file model to a complete GPX 1.1 XML string.
    ///
    /// - Parameters:
    ///   - gpx: The GPX file model to write.
    ///   - creator: The `creator` attribute value.
    /// - Returns: A GPX 1.1 XML string.
    static func write(
        _ gpx: GPXFile,
        creator: String = "GISToolsGPX"
    ) -> String {
        var collector: [String] = []

        collector.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")

        let usedNamespaces = collectUsedNamespaces(gpx)
        let xmlns = buildGPXOpenTag(usedNamespaces: usedNamespaces, creator: creator)
        collector.append(xmlns)

        // Metadata
        if let meta = gpx.metadata {
            collector.append(indent(1) + "<metadata>")
            writeMetadata(meta, to: &collector, indentLevel: 2)
            collector.append(indent(1) + "</metadata>")
        }

        // Waypoints
        for wp in gpx.waypoints {
            writeWaypoint(wp, elementName: "wpt", to: &collector, indentLevel: 1)
        }

        // Routes
        for rte in gpx.routes {
            collector.append(indent(1) + "<rte>")
            writeRouteMeta(rte, to: &collector, indentLevel: 2)
            for pt in rte.points {
                writeWaypoint(pt, elementName: "rtept", to: &collector, indentLevel: 2)
            }
            writeExtensions(rte.extensions, to: &collector, indentLevel: 2)
            collector.append(indent(1) + "</rte>")
        }

        // Tracks
        for trk in gpx.tracks {
            collector.append(indent(1) + "<trk>")
            writeTrackMeta(trk, to: &collector, indentLevel: 2)
            for seg in trk.segments {
                collector.append(indent(2) + "<trkseg>")
                for pt in seg {
                    writeWaypoint(pt, elementName: "trkpt", to: &collector, indentLevel: 3)
                }
                collector.append(indent(2) + "</trkseg>")
            }
            writeExtensions(trk.extensions, to: &collector, indentLevel: 2)
            collector.append(indent(1) + "</trk>")
        }

        collector.append("</gpx>")
        return collector.joined(separator: "\n") + "\n"
    }

    // MARK: - XML helpers

    private static func indent(_ level: Int) -> String {
        String(repeating: "  ", count: level * 2)
            .prefix(level * 2)
            .description
    }

    private static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func formatDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func formatCoordinate(_ value: Double) -> String {
        String(format: "%.9g", value)
    }

    // MARK: - Namespace handling

    private static func collectUsedNamespaces(_ gpx: GPXFile) -> Set<String> {
        var prefixes = Set<String>()

        for wp in gpx.waypoints {
            prefixes.formUnion(wp.extensions.keys)
        }
        for rte in gpx.routes {
            prefixes.formUnion(rte.extensions.keys)
            for pt in rte.points {
                prefixes.formUnion(pt.extensions.keys)
            }
        }
        for trk in gpx.tracks {
            prefixes.formUnion(trk.extensions.keys)
            for seg in trk.segments {
                for pt in seg {
                    prefixes.formUnion(pt.extensions.keys)
                }
            }
        }

        return prefixes
    }

    private static func buildGPXOpenTag(
        usedNamespaces: Set<String>,
        creator: String
    ) -> String {
        var parts: [String] = []
        parts.append("<gpx")
        parts.append(" xmlns=\"http://www.topografix.com/GPX/1/1\"")
        parts.append(" version=\"1.1\"")
        parts.append(" creator=\"\(escapeXML(creator))\"")

        for prefix in usedNamespaces.sorted() {
            if let ns = GPXExtensionNamespace.namespace(for: prefix) {
                parts.append(" xmlns:\(prefix)=\"\(ns.rawValue)\"")
            }
        }

        parts.append(">")
        return parts.joined()
    }

    // MARK: - Metadata

    private static func writeMetadata(
        _ meta: GPXMetadata,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)

        if let name = meta.name { collector.append(i + element("name", name)) }
        if let desc = meta.desc { collector.append(i + element("desc", desc)) }

        if let author = meta.author {
            collector.append(i + "<author>")
            writePerson(author, to: &collector, indentLevel: indentLevel + 1)
            collector.append(i + "</author>")
        }

        if let cr = meta.copyright {
            collector.append(i + "<copyright author=\"\(escapeXML(cr.author))\">")
            if let year = cr.year {
                collector.append(indent(indentLevel + 1) + element("year", "\(year)"))
            }
            if let license = cr.license {
                collector.append(indent(indentLevel + 1) + element("license", license))
            }
            collector.append(i + "</copyright>")
        }

        for link in meta.links {
            writeLink(link, to: &collector, indentLevel: indentLevel)
        }

        if let time = meta.time {
            collector.append(i + element("time", formatDate(time)))
        }

        if let keywords = meta.keywords {
            collector.append(i + element("keywords", keywords))
        }

        if let bounds = meta.bounds {
            let attrs = [
                "minlat=\"\(formatCoordinate(bounds.southWest.latitude))\"",
                "minlon=\"\(formatCoordinate(bounds.southWest.longitude))\"",
                "maxlat=\"\(formatCoordinate(bounds.northEast.latitude))\"",
                "maxlon=\"\(formatCoordinate(bounds.northEast.longitude))\"",
            ].joined(separator: " ")
            collector.append(i + "<bounds \(attrs) />")
        }
    }

    private static func writePerson(
        _ person: GPXPerson,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)

        if let name = person.name { collector.append(i + element("name", name)) }
        if let email = person.email {
            // Email in GPX is <email id="..." domain="..."/>
            let parts = email.components(separatedBy: "@")
            if parts.count == 2 {
                collector.append(
                    i + "<email id=\"\(escapeXML(parts[0]))\""
                        + " domain=\"\(escapeXML(parts[1]))\" />")
            }
            else {
                collector.append(i + element("email", email))
            }
        }
        if let link = person.link {
            writeLink(link, to: &collector, indentLevel: indentLevel)
        }
    }

    private static func writeLink(
        _ link: GPXLink,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)

        if link.text != nil || link.type != nil {
            collector.append(i + "<link href=\"\(escapeXML(link.href))\">")
            if let text = link.text {
                collector.append(indent(indentLevel + 1) + element("text", text))
            }
            if let type = link.type {
                collector.append(indent(indentLevel + 1) + element("type", type))
            }
            collector.append(i + "</link>")
        }
        else {
            collector.append(i + "<link href=\"\(escapeXML(link.href))\" />")
        }
    }

    // MARK: - Waypoint

    private static func writeWaypoint(
        _ wp: GPXWaypoint,
        elementName: String,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)
        let latStr = formatCoordinate(wp.latitude)
        let lonStr = formatCoordinate(wp.longitude)
        collector.append(i + "<\(elementName) lat=\"\(latStr)\" lon=\"\(lonStr)\">")

        let ci = indent(indentLevel + 1)

        if let ele = wp.elevation { collector.append(ci + element("ele", formatCoordinate(ele))) }
        if let time = wp.time { collector.append(ci + element("time", formatDate(time))) }
        if let magvar = wp.magneticVariation { collector.append(ci + element("magvar", formatCoordinate(magvar))) }
        if let geoid = wp.geoidHeight { collector.append(ci + element("geoidheight", formatCoordinate(geoid))) }
        if let name = wp.name { collector.append(ci + element("name", name)) }
        if let cmt = wp.comment { collector.append(ci + element("cmt", cmt)) }
        if let desc = wp.description { collector.append(ci + element("desc", desc)) }
        if let src = wp.source { collector.append(ci + element("src", src)) }
        for link in wp.links { writeLink(link, to: &collector, indentLevel: indentLevel + 1) }
        if let sym = wp.symbol { collector.append(ci + element("sym", sym)) }
        if let type = wp.type { collector.append(ci + element("type", type)) }
        if let fix = wp.fix { collector.append(ci + element("fix", fix.rawValue)) }
        if let sat = wp.satellites { collector.append(ci + element("sat", "\(sat)")) }
        if let hdop = wp.horizontalDilution { collector.append(ci + element("hdop", formatCoordinate(hdop))) }
        if let vdop = wp.verticalDilution { collector.append(ci + element("vdop", formatCoordinate(vdop))) }
        if let pdop = wp.positionDilution { collector.append(ci + element("pdop", formatCoordinate(pdop))) }
        if let age = wp.ageOfDGPSData { collector.append(ci + element("ageofdgpsdata", formatCoordinate(age))) }
        if let dgpsid = wp.dgpsid { collector.append(ci + element("dgpsid", "\(dgpsid)")) }

        writeExtensions(wp.extensions, to: &collector, indentLevel: indentLevel + 1)

        collector.append(i + "</\(elementName)>")
    }

    // MARK: - Route meta

    private static func writeRouteMeta(
        _ rte: GPXRoute,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)

        if let name = rte.name { collector.append(i + element("name", name)) }
        if let cmt = rte.comment { collector.append(i + element("cmt", cmt)) }
        if let desc = rte.description { collector.append(i + element("desc", desc)) }
        if let src = rte.source { collector.append(i + element("src", src)) }
        for link in rte.links { writeLink(link, to: &collector, indentLevel: indentLevel) }
        if let num = rte.number { collector.append(i + element("number", "\(num)")) }
        if let type = rte.type { collector.append(i + element("type", type)) }
    }

    // MARK: - Track meta

    private static func writeTrackMeta(
        _ trk: GPXTrack,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)

        if let name = trk.name { collector.append(i + element("name", name)) }
        if let cmt = trk.comment { collector.append(i + element("cmt", cmt)) }
        if let desc = trk.description { collector.append(i + element("desc", desc)) }
        if let src = trk.source { collector.append(i + element("src", src)) }
        for link in trk.links { writeLink(link, to: &collector, indentLevel: indentLevel) }
        if let num = trk.number { collector.append(i + element("number", "\(num)")) }
        if let type = trk.type { collector.append(i + element("type", type)) }
    }

    // MARK: - Extensions

    private static func writeExtensions(
        _ extensions: [String: [String: Sendable]],
        to collector: inout [String],
        indentLevel: Int
    ) {
        guard !extensions.isEmpty else { return }
        let i = indent(indentLevel)

        collector.append(i + "<extensions>")

        for (prefix, elements) in extensions.sorted(by: { $0.key < $1.key }) {
            guard GPXExtensionNamespace.namespace(for: prefix) != nil else { continue }

            let needsWrapper: Bool = {
                if prefix == "gpxtpx" { return true }
                return elements.keys.allSatisfy { key in
                    !["Address", "Categories", "PhoneNumber", "rpt",
                      "WaypointExtension", "RouteExtension",
                      "TrackExtension", "TrackPointExtension",
                      "RoutePointExtension"].contains(key)
                }
            }()

            if needsWrapper {
                let w = extensionWrapperName(for: prefix) ?? "Extension"
                collector.append(indent(indentLevel + 1) + "<\(prefix):\(w)>")
                for (key, value) in elements.sorted(by: { $0.key < $1.key }) {
                    writeExtensionElement(
                        prefix: prefix, key: key, value: value,
                        to: &collector, indentLevel: indentLevel + 2)
                }
                collector.append(indent(indentLevel + 1) + "</\(prefix):\(w)>")
            }
            else {
                for (key, value) in elements.sorted(by: { $0.key < $1.key }) {
                    writeExtensionElement(
                        prefix: prefix, key: key, value: value,
                        to: &collector, indentLevel: indentLevel + 1)
                }
            }
        }

        collector.append(i + "</extensions>")
    }

    private static func writeExtensionElement(
        prefix: String,
        key: String,
        value: Sendable,
        to collector: inout [String],
        indentLevel: Int
    ) {
        let i = indent(indentLevel)

        switch value {
        case let dict as [String: Sendable]:
            collector.append(i + "<\(prefix):\(key)>")
            for (childKey, childValue) in dict.sorted(by: { $0.key < $1.key }) {
                if let arr = childValue as? [Sendable] {
                    for item in arr {
                        writeExtensionElement(
                            prefix: prefix, key: childKey,
                            value: item,
                            to: &collector, indentLevel: indentLevel + 1)
                    }
                }
                else {
                    writeExtensionElement(
                        prefix: prefix, key: childKey,
                        value: childValue,
                        to: &collector, indentLevel: indentLevel + 1)
                }
            }
            collector.append(i + "</\(prefix):\(key)>")

        case let arr as [Sendable]:
            for item in arr {
                if let itemDict = item as? [String: Sendable] {
                    let attrs = buildAttributes(from: itemDict, except: "value")
                    let textValue = itemDict["value"] as? String ?? ""
                    if attrs.isEmpty {
                        collector.append(i + "<\(prefix):\(key)>\(escapeXML(textValue))</\(prefix):\(key)>")
                    }
                    else {
                        collector.append(i + "<\(prefix):\(key) \(attrs)>\(escapeXML(textValue))</\(prefix):\(key)>")
                    }
                }
                else if let itemDict = item as? [String: Double] {
                    let lat = formatCoordinate(itemDict["lat"] ?? 0.0)
                    let lon = formatCoordinate(itemDict["lon"] ?? 0.0)
                    collector.append(i + "<\(prefix):\(key) lat=\"\(lat)\" lon=\"\(lon)\" />")
                }
                else if let str = item as? String {
                    collector.append(i + "<\(prefix):\(key)>\(escapeXML(str))</\(prefix):\(key)>")
                }
                else {
                    collector.append(i + "<\(prefix):\(key)>\(formatValue(item))</\(prefix):\(key)>")
                }
            }

        default:
            collector.append(i + "<\(prefix):\(key)>\(formatValue(value))</\(prefix):\(key)>")
        }
    }

    private static func buildAttributes(from dict: [String: Sendable], except: String) -> String {
        dict.filter { $0.key.lowercased() != except.lowercased() }
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\"\(escapeXML(formatValue($0.value)))\"" }
            .joined(separator: " ")
    }

    private static func formatValue(_ value: Sendable) -> String {
        switch value {
        case let d as Double: formatCoordinate(d)
        case let i as Int: "\(i)"
        case let b as Bool: b ? "true" : "false"
        case let s as String: escapeXML(s)
        default: escapeXML("\(value)")
        }
    }

    private static func extensionWrapperName(for prefix: String) -> String? {
        switch prefix {
        case "gpxtpx": "TrackPointExtension"
        case "gpxx": nil // gpxx elements vary by context
        default: nil
        }
    }

    // MARK: - Element builder

    private static func element(_ name: String, _ content: String) -> String {
        "<\(name)>\(escapeXML(content))</\(name)>"
    }

}
