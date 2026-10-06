import Foundation

public enum CoordinateSystem: String, Codable, Sendable { case wgs84, gcj02 }
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var system: CoordinateSystem
    public init(_ latitude: Double, _ longitude: Double, system: CoordinateSystem = .wgs84) {
        self.latitude = latitude; self.longitude = longitude; self.system = system
    }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    /// Distances are only meaningful within the same reference system.
    public func distance(to other: Coordinate) -> Double {
        guard isValid, other.isValid, system == other.system else { return .infinity }
        let r = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * r / 2), 2) + cos(latitude * r) * cos(other.latitude * r) * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6_371_000 * 2 * asin(min(1, sqrt(max(0, a))))
    }
}
public struct LocationSample: Codable, Equatable, Sendable {
    public var coordinate: Coordinate
    public var date: Date
    public var accuracy: Double
    public init(coordinate: Coordinate, date: Date, accuracy: Double) { self.coordinate = coordinate; self.date = date; self.accuracy = accuracy }
    public var isUsable: Bool { coordinate.isValid && accuracy.isFinite && accuracy >= 0 && accuracy <= 100 }
}
public struct Place: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var address: String
    public var coordinate: Coordinate
    public var category: String
    public init(id: String, name: String, address: String, coordinate: Coordinate, category: String = "") {
        self.id = id; self.name = name; self.address = address; self.coordinate = coordinate; self.category = category
    }
}
public enum VisitSource: String, Codable, Sendable { case automatic, manual }
public enum MatchStatus: String, Codable, CaseIterable, Sendable { case pending, inferred, confirmed }
public enum ExperienceKind: String, Codable, Sendable { case visit, takeaway }
public struct Visit: Identifiable, Codable, Sendable {
    public var id: UUID
    public var arrival: Date
    public var departure: Date?
    public var coordinate: Coordinate
    public var accuracy: Double
    public var place: Place?
    public var candidates: [Place]
    public var source: VisitSource
    public var status: MatchStatus
    public var kind: ExperienceKind
    public var rating: Double?
    public var note: String
    public var photoIDs: [UUID]
    public init(id: UUID = UUID(), arrival: Date, departure: Date? = nil, coordinate: Coordinate, accuracy: Double = 0, place: Place? = nil, candidates: [Place] = [], source: VisitSource = .automatic, status: MatchStatus = .pending, rating: Double? = nil, note: String = "", photoIDs: [UUID] = []) {
        self.id = id; self.arrival = arrival; self.departure = departure; self.coordinate = coordinate; self.accuracy = accuracy
        self.place = place; self.candidates = candidates; self.source = source; self.status = status; self.kind = .visit
        self.rating = rating; self.note = note; self.photoIDs = photoIDs
    }
    public var title: String { place?.name ?? "待确认的停留" }
    public var isValid: Bool {
        coordinate.isValid && accuracy.isFinite && accuracy >= 0 && (departure == nil || departure! >= arrival) && Rating.isValid(rating)
    }
}
public enum Rating {
    public static func isValid(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && (0.5...5).contains(value) && (value * 2).rounded() == value * 2
    }
    public static func average(_ values: [Double?]) -> Double? {
        let rated = values.compactMap { $0 }.filter { isValid($0) }
        return rated.isEmpty ? nil : rated.reduce(0, +) / Double(rated.count)
    }
}
public struct IgnoredPlace: Identifiable, Codable, Sendable {
    public var id: UUID
    public var coordinate: Coordinate
    public var radius: Double
    public var name: String
    public init(id: UUID = UUID(), coordinate: Coordinate, radius: Double = 100, name: String) {
        self.id = id; self.coordinate = coordinate; self.radius = radius; self.name = name
    }
    public func contains(_ point: Coordinate) -> Bool { coordinate.distance(to: point) <= radius }
}
public struct RouteSegment: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public var gapBefore: String?
    public var points: [LocationSample] = []
    public init(gapBefore: String? = nil, points: [LocationSample] = []) { self.gapBefore = gapBefore; self.points = points }
}
public struct Trip: Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public init(id: UUID = UUID(), title: String, startedAt: Date = Date()) { self.id = id; self.title = title; self.startedAt = startedAt }
}
/// Separate chunks prevent re-uploading an entire holiday whenever one point arrives.
public struct TripChunk: Identifiable, Codable, Sendable {
    public var id: UUID
    public var tripID: UUID
    public var segment: RouteSegment
    public init(tripID: UUID, segment: RouteSegment) { self.id = segment.id; self.tripID = tripID; self.segment = segment }
}
public struct SharedSnapshot: Identifiable, Codable, Sendable {
    public var id: UUID
    public var sourceVisitID: UUID
    public var title: String
    public var address: String
    public var day: String
    public var rating: Double?
    public var note: String
    public init(visit: Visit) {
        id = UUID(); sourceVisitID = visit.id; title = visit.title; address = visit.place?.address ?? ""
        // Share a calendar day only, never arrival/departure timestamps or coordinates.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        day = formatter.string(from: visit.arrival)
        rating = visit.rating; note = visit.note
    }
}
public enum TrackingMode: String, Codable, Sendable { case off, daily, touring, paused }
public struct TrackingState: Codable, Equatable, Sendable {
    public var mode: TrackingMode = .off
    public var tripID: UUID?
    public init(mode: TrackingMode = .off, tripID: UUID? = nil) { self.mode = mode; self.tripID = tripID }
    public mutating func startTrip(_ id: UUID) { mode = .touring; tripID = id }
    public mutating func pause() { if mode == .touring { mode = .paused } }
    public mutating func resume() { if mode == .paused && tripID != nil { mode = .touring } }
    public mutating func finishTrip() { tripID = nil; mode = .daily }
    public mutating func stop() { tripID = nil; mode = .off }
}
