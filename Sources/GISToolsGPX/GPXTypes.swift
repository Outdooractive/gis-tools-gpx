import Foundation

// MARK: - GPX Element Type

/// Identifies whether a ``Feature`` originated from a GPX waypoint,
/// route, or track element.
public enum GPXElementType: String, Equatable, Sendable {

    /// A waypoint (`<wpt>`).
    case waypoint = "wpt"

    /// A route (`<rte>`).
    case route = "rte"

    /// A track (`<trk>`).
    case track = "trk"

}

// MARK: - GPS Fix Type

/// Type of GPS fix as defined by the GPX 1.1 specification.
public enum GPSFixType: String, Equatable, Sendable {

    /// No GPS fix.
    case none

    /// 2-dimensional fix.
    case twoDimensional = "2d"

    /// 3-dimensional fix.
    case threeDimensional = "3d"

    /// Differential GPS fix.
    case dgps

    /// Precise Positioning Service (military signal).
    case pps

}

// MARK: - GPX Link

/// A link to an external resource associated with a GPX element.
public struct GPXLink: Equatable, Sendable {

    /// The URL of the link.
    public var href: String

    /// The `href` as a `URL`.
    public var url: URL? {
        URL(string: href)
    }

    /// Optional link text.
    public var text: String?

    /// Optional MIME type of the linked resource.
    public var type: String?

    public init(href: String, text: String? = nil, type: String? = nil) {
        self.href = href
        self.text = text
        self.type = type
    }

}

// MARK: - GPX Person

/// A person or organization associated with a GPX file.
public struct GPXPerson: Equatable, Sendable {

    /// Name of the person or organization.
    public var name: String?

    /// Email address.
    public var email: String?

    /// Optional link to a website.
    public var link: GPXLink?

    public init(name: String? = nil, email: String? = nil, link: GPXLink? = nil) {
        self.name = name
        self.email = email
        self.link = link
    }

}

// MARK: - GPX Copyright

/// Copyright and licensing information for a GPX file.
public struct GPXCopyright: Equatable, Sendable {

    /// The copyright holder.
    public var author: String

    /// The year of copyright.
    public var year: Int?

    /// A URL to the license agreement.
    public var license: String?

    public init(author: String, year: Int? = nil, license: String? = nil) {
        self.author = author
        self.year = year
        self.license = license
    }

}

// MARK: - GPX Address

/// A postal address stored in a GPX waypoint extension.
public struct GPXAddress: Equatable, Sendable {

    /// Street address lines (up to two).
    public var streetAddresses: [String]

    /// City or locality.
    public var city: String?

    /// State or province.
    public var state: String?

    /// Country name.
    public var country: String?

    /// Postal or ZIP code.
    public var postalCode: String?

    public init(
        streetAddresses: [String] = [],
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        postalCode: String? = nil
    ) {
        self.streetAddresses = streetAddresses
        self.city = city
        self.state = state
        self.country = country
        self.postalCode = postalCode
    }

}

// MARK: - GPX Phone Number

/// A phone number entry in a GPX waypoint extension.
public struct GPXPhoneNumber: Equatable, Sendable {

    /// The phone number.
    public var value: String

    /// Optional category (e.g. "Work", "Home", "Mobile").
    public var category: String?

    public init(value: String, category: String? = nil) {
        self.value = value
        self.category = category
    }

}
