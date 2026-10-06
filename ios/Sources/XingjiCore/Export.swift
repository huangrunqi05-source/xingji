import Foundation
public enum GPXExporter {
    public static func render(trip: Trip, chunks: [TripChunk]) -> String {
        let formatter = ISO8601DateFormatter()
        let segments = chunks.filter { $0.tripID == trip.id }.sorted { ($0.segment.points.first?.date ?? .distantPast) < ($1.segment.points.first?.date ?? .distantPast) }
        let body = segments.map { chunk in
            let points = chunk.segment.points.filter { $0.coordinate.isValid && $0.coordinate.system == .wgs84 }.map {
                "<trkpt lat=\"\($0.coordinate.latitude)\" lon=\"\($0.coordinate.longitude)\"><time>\(formatter.string(from: $0.date))</time></trkpt>"
            }.joined(separator: "\n")
            return "<trkseg>\n\(points)\n</trkseg>"
        }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Xingji\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(escape(trip.title))</name>\n\(body)\n</trk></gpx>"
    }
    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;") }
}
