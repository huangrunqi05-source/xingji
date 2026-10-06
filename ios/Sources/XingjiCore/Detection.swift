import Foundation

public struct DetectedStop: Sendable {
    public var coordinate: Coordinate
    public var arrival: Date
    public var departure: Date
    public var accuracy: Double
    public init(coordinate: Coordinate, arrival: Date, departure: Date, accuracy: Double) {
        self.coordinate = coordinate; self.arrival = arrival; self.departure = departure; self.accuracy = accuracy
    }
    public var isValid: Bool { coordinate.isValid && accuracy >= 0 && accuracy <= 100 && departure.timeIntervalSince(arrival) >= 300 }
}
/// Deliberately conservative: uncertain evidence stays pending rather than inventing a shop.
public enum PlaceMatcher {
    public static func match(stop: DetectedStop, candidates: [Place]) -> (Place?, MatchStatus) {
        guard stop.isValid, stop.accuracy <= 35 else { return (nil, .pending) }
        let nearby = candidates.filter { $0.coordinate.distance(to: stop.coordinate) <= max(60, stop.accuracy * 2) }
        guard nearby.count == 1, let only = nearby.first,
              only.coordinate.distance(to: stop.coordinate) <= 30 else { return (nil, .pending) }
        return (only, .inferred)
    }
}
public struct StopDetector {
    private var anchor: LocationSample?
    private var latest: LocationSample?
    private var count = 0
    public init() {}
    public mutating func reset() { anchor = nil; latest = nil; count = 0 }
    public mutating func ingest(_ sample: LocationSample) -> DetectedStop? {
        guard sample.isUsable else { reset(); return nil }
        guard let first = anchor, let last = latest else { anchor = sample; latest = sample; count = 1; return nil }
        guard sample.date > last.date else { return nil }
        if sample.date.timeIntervalSince(last.date) > 180 { reset(); anchor = sample; latest = sample; count = 1; return nil }
        if first.coordinate.distance(to: sample.coordinate) <= 50 {
            latest = sample; count += 1; return nil
        }
        let result = completed()
        reset(); anchor = sample; latest = sample; count = 1
        return result
    }
    public func completed() -> DetectedStop? {
        guard let first = anchor, let last = latest, count >= 3, last.date.timeIntervalSince(first.date) >= 300 else { return nil }
        return DetectedStop(coordinate: first.coordinate, arrival: first.date, departure: last.date, accuracy: max(first.accuracy, last.accuracy))
    }
}
/// The caller persists each emitted chunk; the builder retains at most 256 points.
public struct RouteRecorder {
    public private(set) var current = RouteSegment()
    private var previous: LocationSample?
    public init() {}
    public mutating func breakRoute(_ reason: String) -> RouteSegment? {
        let finished = current.points.isEmpty ? nil : current
        current = RouteSegment(gapBefore: reason); previous = nil
        return finished
    }
    public mutating func append(_ sample: LocationSample) -> RouteSegment? {
        guard sample.isUsable else { return breakRoute("定位精度不足") }
        var completed: RouteSegment?
        if let previous {
            let dt = sample.date.timeIntervalSince(previous.date)
            guard dt > 0 else { return nil }
            if dt > 180 { completed = breakRoute("定位中断超过 3 分钟") }
            else if previous.coordinate.distance(to: sample.coordinate) / dt > 100 {
                return breakRoute("定位跳变，已断开路线")
            }
        }
        if current.points.count >= 256 {
            completed = current
            // One shared endpoint makes chunk boundaries visually continuous, not gaps.
            current = RouteSegment(points: current.points.suffix(1).map { $0 })
        }
        current.points.append(sample); previous = sample
        return completed
    }
}
public enum VisitDeduplicator {
    public static func existing(for stop: DetectedStop, in visits: [Visit]) -> Visit? {
        visits.first {
            guard $0.source == .automatic, $0.kind == .visit, $0.coordinate.distance(to: stop.coordinate) < 100 else { return false }
            if abs($0.arrival.timeIntervalSince(stop.arrival)) < 300 { return true }
            guard let end = $0.departure else { return false }
            let overlap = min(end, stop.departure).timeIntervalSince(max($0.arrival, stop.arrival))
            let shorter = min(end.timeIntervalSince($0.arrival), stop.departure.timeIntervalSince(stop.arrival))
            return overlap >= 300 && overlap >= shorter * 0.8
        }
    }
}
