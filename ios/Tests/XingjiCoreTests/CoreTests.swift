import XCTest
@testable import XingjiCore
final class CoreTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    func sample(_ seconds: Double, latitude: Double = 31.23, accuracy: Double = 10) -> LocationSample {
        LocationSample(coordinate: Coordinate(latitude, 121.47), date: start.addingTimeInterval(seconds), accuracy: accuracy)
    }
    func testShortPassDoesNotCreateVisit() {
        var detector = StopDetector()
        for second in stride(from: 0, through: 120, by: 30) { XCTAssertNil(detector.ingest(sample(Double(second)))) }
        XCTAssertNil(detector.ingest(sample(150, latitude: 31.24)))
    }
    func testStopAfterFiveMinutesAndMovement() {
        var detector = StopDetector()
        for second in stride(from: 0, through: 360, by: 30) { _ = detector.ingest(sample(Double(second))) }
        let stop = detector.ingest(sample(390, latitude: 31.24))
        XCTAssertEqual(stop?.arrival, start); XCTAssertEqual(stop?.departure, start.addingTimeInterval(360))
    }
    func testMissingSamplesCannotFabricateStop() {
        var detector = StopDetector()
        _ = detector.ingest(sample(0)); _ = detector.ingest(sample(300)); _ = detector.ingest(sample(600))
        XCTAssertNil(detector.completed())
    }
    func testMallCandidatesRemainPendingAndSystemsMustMatch() {
        let point = Coordinate(31.23, 121.47, system: .gcj02)
        let stop = DetectedStop(coordinate: point, arrival: start, departure: start.addingTimeInterval(600), accuracy: 10)
        let p = Place(id: "branch-1", name: "咖啡", address: "一楼", coordinate: point)
        let q = Place(id: "branch-2", name: "咖啡", address: "二楼", coordinate: point)
        XCTAssertEqual(PlaceMatcher.match(stop: stop, candidates: [p, q]).1, .pending)
        XCTAssertEqual(PlaceMatcher.match(stop: stop, candidates: [p]).0?.id, p.id)
        let raw = Place(id: "wrong-system", name: "店", address: "", coordinate: Coordinate(31.23, 121.47))
        XCTAssertEqual(PlaceMatcher.match(stop: stop, candidates: [raw]).1, .pending)
    }
    func testInaccurateSinglePOIIsNotAutoConfirmed() {
        let stop = DetectedStop(coordinate: Coordinate(31.23,121.47), arrival: start, departure: start.addingTimeInterval(600), accuracy: 80)
        let p = Place(id: "1", name: "店", address: "", coordinate: stop.coordinate)
        XCTAssertEqual(PlaceMatcher.match(stop: stop, candidates: [p]).1, .pending)
    }
    func testRouteSplitsOnGapJumpAndPoorAccuracy() {
        var route = RouteRecorder()
        _ = route.append(sample(0)); _ = route.append(sample(10))
        XCTAssertEqual(route.append(sample(400))?.points.count, 2)
        XCTAssertNotNil(route.current.gapBefore)
        XCTAssertEqual(route.append(sample(401, latitude: 32))?.points.count, 1)
        XCTAssertTrue(route.current.points.isEmpty)
        _ = route.append(sample(410)); XCTAssertEqual(route.append(sample(420, accuracy: 500))?.points.count, 1)
    }
    func testOutOfOrderRouteSampleIgnored() {
        var route = RouteRecorder(); _ = route.append(sample(10)); _ = route.append(sample(0))
        XCTAssertEqual(route.current.points.count, 1)
    }
    func testRatingOmitsUnratedAndRejectsNonHalfStars() {
        XCTAssertEqual(Rating.average([nil, 4, 5]), 4.5); XCTAssertNil(Rating.average([nil]))
        XCTAssertFalse(Rating.isValid(3.2)); XCTAssertFalse(Rating.isValid(0)); XCTAssertFalse(Rating.isValid(.nan))
    }
    func testModeTransitions() {
        var s = TrackingState(); s.resume(); XCTAssertEqual(s.mode, .off)
        let id = UUID(); s.startTrip(id); s.pause(); XCTAssertEqual(s.tripID, id)
        s.resume(); XCTAssertEqual(s.mode, .touring); s.finishTrip(); XCTAssertEqual(s.mode, .daily); XCTAssertNil(s.tripID)
        s.stop(); XCTAssertEqual(s.mode, .off)
    }
    func testSharedSnapshotCannotContainPrivateRouteOrTimes() throws {
        let v = Visit(arrival: start, departure: start.addingTimeInterval(600), coordinate: Coordinate(31.23,121.47), rating: 4.5)
        let data = try JSONEncoder().encode(SharedSnapshot(visit: v))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(dict["coordinate"]); XCTAssertNil(dict["departure"]); XCTAssertNil(dict["arrival"]); XCTAssertNil(dict["photoIDs"])
    }
    func testGPXPreservesSeparateSegmentsAndEscapesNames() {
        let t = Trip(title: "A&B<旅游>", startedAt: start)
        let chunks = [TripChunk(tripID: t.id, segment: RouteSegment(points: [sample(0)])), TripChunk(tripID: t.id, segment: RouteSegment(gapBefore: "pause", points: [sample(400)]))]
        let xml = GPXExporter.render(trip: t, chunks: chunks)
        XCTAssertEqual(xml.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertTrue(xml.contains("A&amp;B&lt;旅游&gt;"))
    }
    func testRevisitAndBranchesAreNotCollapsed() {
        let stop = DetectedStop(coordinate: Coordinate(31.23,121.47), arrival: start, departure: start.addingTimeInterval(600), accuracy: 10)
        let old = Visit(arrival: start.addingTimeInterval(-3600), coordinate: stop.coordinate)
        XCTAssertNil(VisitDeduplicator.existing(for: stop, in: [old]))
        let same = Visit(arrival: start, coordinate: stop.coordinate)
        XCTAssertEqual(VisitDeduplicator.existing(for: stop, in: [same])?.id, same.id)
    }
}
