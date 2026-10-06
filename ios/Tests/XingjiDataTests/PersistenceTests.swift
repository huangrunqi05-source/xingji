import XCTest
import CoreData
import XingjiCore
@testable import XingjiData
final class PersistenceTests: XCTestCase {
    @MainActor func makeStore() throws -> Persistence {
        try Persistence(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), inMemory: true)
    }
    @MainActor func testRoundTripUpdatesAndUnrated() async throws {
        let store = try makeStore()
        var visit = Visit(arrival: Date(), coordinate: Coordinate(31,121), source: .manual)
        try store.saveVisit(visit); visit.note = "很好吃"; try store.saveVisit(visit)
        let visits = try store.records("visit", as: Visit.self)
        XCTAssertEqual(visits.count,1); XCTAssertEqual(visits.first?.note,"很好吃"); XCTAssertNil(visits.first?.rating)
        visit.rating = 6; XCTAssertThrowsError(try store.saveVisit(visit))
    }
    @MainActor func testSharedGraphDetachedAndSnapshotNotAutoUpdated() async throws {
        let store = try makeStore()
        var visit = Visit(arrival: Date(), coordinate: Coordinate(31,121), note: "旧评论")
        try store.saveVisit(visit)
        let list = try store.createList(title: "朋友清单")
        try await store.publish(SharedSnapshot(visit: visit), photos: [Data([1,2,3])], to: list)
        visit.note = "私人修改"; try store.saveVisit(visit)
        let entry = try XCTUnwrap(store.entries(in: list).first)
        XCTAssertEqual(try store.snapshot(entry).note,"旧评论")
        XCTAssertEqual(store.sharedPhotos(entry).count,1)
        XCTAssertEqual(Set(entry.entity.relationshipsByName.keys),["list","photos"])
        try store.deleteVisit(visit); XCTAssertTrue(store.entries(in: list).isEmpty)
        XCTAssertTrue(try store.records("visit", as: Visit.self).isEmpty)
    }
    @MainActor func testReadonlyParticipantCannotWrite() async throws {
        let store = try makeStore()
        let list = NSEntityDescription.insertNewObject(forEntityName: "SharedList", into: store.context)
        store.context.assign(list, to: try XCTUnwrap(store.sharedStore)); try store.save()
        XCTAssertFalse(store.isOwner(list))
        do {
            try await store.publish(SharedSnapshot(visit: Visit(arrival: Date(), coordinate: Coordinate(1,1))), photos: [], to: list)
            XCTFail("Participant must not publish")
        } catch { XCTAssertTrue(error is StoreError) }
    }
    @MainActor func testDeleteAllIncludesPhotosAndLists() async throws {
        let store = try makeStore()
        let v = Visit(arrival: Date(), coordinate: Coordinate(1,1))
        try store.saveVisit(v); let photo = try store.addPhoto(Data([1]), ownerID: v.id)
        _ = try store.createList(title: "清单"); try await store.deleteAll()
        XCTAssertTrue(try store.lists().isEmpty); XCTAssertNil(try store.photo(photo))
        XCTAssertTrue(try store.records("visit", as: Visit.self).isEmpty)
    }
    @MainActor func testCloudKitModelUsesOptionalInverseRelationships() async {
        let model = Persistence.model()
        for entity in model.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty)
            for relation in entity.relationshipsByName.values { XCTAssertTrue(relation.isOptional); XCTAssertNotNil(relation.inverseRelationship) }
        }
        let shared = model.entities(forConfigurationName: "Shared")!.compactMap(\.name)
        XCTAssertFalse(shared.contains("PrivateRecord")); XCTAssertFalse(shared.contains("PhotoBlob"))
    }
}
