import Foundation
import SwiftUI
import UIKit
import CoreData
import CloudKit
import XingjiCore
import XingjiData

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var visits: [Visit] = []
    @Published var trips: [Trip] = []
    @Published var activeRoute: [TripChunk] = []
    @Published var ignored: [IgnoredPlace] = []
    @Published var lists: [NSManagedObject] = []
    @Published var error: String?
    @Published var syncStatus = "本机保存"
    @Published var matchStatus = ""
    @Published var isBusy = false
    @Published var storageFailure: String?
    @Published var mapService = AMapPlaceService()
    let tracker = TrackingController()
    private(set) var store: Persistence?
    private var observers: [NSObjectProtocol] = []
    private var stopTask: Task<Void, Never>?
    private var generation = 0
    private var pendingShare: CKShare.Metadata?
    private init() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Xingji", isDirectory: true)
            store = try Persistence(directory: directory, cloudIdentifier: UserDefaults.standard.bool(forKey: "privacyAccepted") ? Configuration.cloudIdentifier : nil)
            reload()
        } catch { storageFailure = error.localizedDescription }
        tracker.onStop = { [weak self] stop in self?.enqueue(stop) }
        tracker.onChunk = { [weak self] chunk in self?.perform { try self?.requireStore().put(chunk, kind: "chunk", id: chunk.id.uuidString, scope: chunk.tripID.uuidString) } }
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reload() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in
                if let error = event.error { self?.syncStatus = "同步未完成：\(error.localizedDescription)" }
                else if event.endDate == nil { self?.syncStatus = "正在与 iCloud 同步…" }
                else { self?.syncStatus = "最近同步：\(event.endDate!.formatted(date: .omitted, time: .shortened))"; self?.reload() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in Task { await self?.refreshCloudStatus() } })
        if storageFailure == nil { tracker.restore() }
        if UserDefaults.standard.bool(forKey: "privacyAccepted") { UIApplication.shared.registerForRemoteNotifications(); Task { await refreshCloudStatus() } }
    }
    func requireStore() throws -> Persistence { guard let store else { throw StoreError.missingStore }; return store }
    func activatePrivacyConsent() {
        UserDefaults.standard.set(true, forKey: "privacyAccepted")
        do {
            if Configuration.cloudIdentifier != nil, store?.cloudIdentifier == nil {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Xingji", isDirectory: true)
                if let store { try store.save(); for persistentStore in store.container.persistentStoreCoordinator.persistentStores { try store.container.persistentStoreCoordinator.remove(persistentStore) } }
                store = try Persistence(directory: directory, cloudIdentifier: Configuration.cloudIdentifier)
            }
            mapService = AMapPlaceService(); tracker.restore(); reload(); UIApplication.shared.registerForRemoteNotifications()
            Task {
                await refreshCloudStatus()
                if let metadata = pendingShare { pendingShare = nil; await acceptShare(metadata) }
            }
        } catch { storageFailure = error.localizedDescription }
    }
    func reload() {
        do {
            let store = try requireStore()
            visits = try store.records("visit", as: Visit.self).sorted { $0.arrival > $1.arrival }
            trips = try store.records("trip", as: Trip.self).sorted { $0.startedAt > $1.startedAt }
            ignored = try store.records("ignored", as: IgnoredPlace.self)
            lists = try store.lists()
            activeRoute = try tracker.state.tripID.map { try store.records("chunk", as: TripChunk.self, scope: $0.uuidString) } ?? []
        } catch { self.error = error.localizedDescription }
    }
    func perform(_ operation: () throws -> Void) { do { try operation(); reload() } catch { self.error = error.localizedDescription } }
    func refreshCloudStatus() async {
        guard let id = Configuration.cloudIdentifier else { syncStatus = "仅保存在本机 · iCloud 未配置"; return }
        do {
            let status = try await CKContainer(identifier: id).accountStatus()
            switch status {
            case .available: syncStatus = "iCloud 可用 · 更改会自动同步"
            case .noAccount: syncStatus = "未登录 iCloud · 继续保存在本机"
            case .restricted: syncStatus = "iCloud 访问受限 · 继续保存在本机"
            default: syncStatus = "iCloud 暂不可用 · 继续保存在本机"
            }
        } catch { syncStatus = "iCloud 暂不可用：\(error.localizedDescription)" }
    }
    private func enqueue(_ stop: DetectedStop) {
        let previous = stopTask, expected = generation
        stopTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == expected else { return }
            await self.process(stop, generation: expected)
        }
    }
    private func process(_ stop: DetectedStop, generation expected: Int) async {
        let mapPoint = try? mapService.mapCoordinate(stop.coordinate)
        guard stop.isValid, !ignored.contains(where: { place in
            place.contains(stop.coordinate) || (mapPoint.map { place.contains($0) } ?? false)
        }) else { return }
        do {
            let store = try requireStore()
            if var previous = VisitDeduplicator.existing(for: stop, in: visits) {
                previous.arrival = min(previous.arrival, stop.arrival)
                previous.departure = max(previous.departure ?? stop.departure, stop.departure)
                try store.saveVisit(previous); reload(); return
            }
            var visit = Visit(arrival: stop.arrival, departure: stop.departure, coordinate: stop.coordinate, accuracy: stop.accuracy)
            try store.saveVisit(visit); reload()
            do {
                let candidates = try await mapService.nearby(stop.coordinate)
                guard generation == expected, let current = visits.first(where: { $0.id == visit.id }), current.status == .pending else { return }
                // Re-read after the request so an intervening user edit is never overwritten.
                visit = current
                let converted = try mapService.mapCoordinate(stop.coordinate)
                let result = PlaceMatcher.match(stop: DetectedStop(coordinate: converted, arrival: stop.arrival, departure: stop.departure, accuracy: stop.accuracy), candidates: candidates)
                visit.candidates = candidates; visit.place = result.0; visit.status = result.1
                try store.saveVisit(visit); matchStatus = ""
            } catch { matchStatus = "有停留尚未匹配店铺，可在回顾中重试。" }
            reload()
        } catch { self.error = error.localizedDescription }
    }
    func retryMatch(_ visit: Visit) async {
        do {
            let candidates = try await mapService.nearby(visit.coordinate)
            guard var current = visits.first(where: { $0.id == visit.id }) else { return }
            current.candidates = candidates
            try requireStore().saveVisit(current); reload()
        } catch { self.error = error.localizedDescription }
    }
    func saveVisit(_ visit: Visit, addedPhotos: [Data] = [], removedPhotos: [UUID] = []) throws {
        let store = try requireStore()
        guard visit.isValid else { throw StoreError.invalidRecord }
        var updated = visit, addedIDs: [UUID] = []
        do {
            for photo in addedPhotos {
                let id = try store.addPhoto(PhotoService.sanitizedJPEG(photo), ownerID: visit.id)
                addedIDs.append(id); updated.photoIDs.append(id)
            }
            updated.photoIDs.removeAll { removedPhotos.contains($0) }
            try store.saveVisit(updated)
        } catch { for id in addedIDs { try? store.removePhoto(id) }; throw error }
        for id in removedPhotos { try store.removePhoto(id) }
        reload()
    }
    func confirm(_ visit: Visit, place: Place) { var updated = visit; updated.place = place; updated.status = .confirmed; perform { try requireStore().saveVisit(updated) } }
    func ignore(_ visit: Visit) {
        perform {
            let ignored = IgnoredPlace(coordinate: visit.coordinate, name: visit.title)
            try requireStore().put(ignored, kind: "ignored", id: ignored.id.uuidString)
            try requireStore().deleteVisit(visit)
        }
    }
    func removeIgnored(_ place: IgnoredPlace) { perform { try requireStore().delete(kind: "ignored", id: place.id.uuidString) } }
    func startTrip() {
        guard tracker.state.tripID == nil else { return }
        perform {
            let trip = Trip(title: Date().formatted(date: .abbreviated, time: .omitted) + "的旅行")
            try requireStore().put(trip, kind: "trip", id: trip.id.uuidString); tracker.startTrip(trip.id)
        }
    }
    func finishTrip(turnOff: Bool = false) {
        perform {
            if let id = tracker.state.tripID, var trip = trips.first(where: { $0.id == id }) {
                trip.endedAt = Date(); try requireStore().put(trip, kind: "trip", id: trip.id.uuidString)
            }
            if turnOff { tracker.disable() } else { tracker.finish() }
        }
    }
    func chunks(for trip: Trip) throws -> [TripChunk] {
        try requireStore().records("chunk", as: TripChunk.self, scope: trip.id.uuidString).sorted { ($0.segment.points.first?.date ?? .distantPast) < ($1.segment.points.first?.date ?? .distantPast) }
    }
    func deleteTrip(_ trip: Trip) {
        if tracker.state.tripID == trip.id { finishTrip(turnOff: true) }
        perform {
            for chunk in try chunks(for: trip) { try requireStore().delete(kind: "chunk", id: chunk.id.uuidString) }
            try requireStore().delete(kind: "trip", id: trip.id.uuidString)
        }
    }
    func deleteAll() async {
        isBusy = true; defer { isBusy = false }
        tracker.disable(); generation += 1
        do { try await requireStore().deleteAll(); reload() } catch { self.error = error.localizedDescription }
    }
    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard UserDefaults.standard.bool(forKey: "privacyAccepted") else { pendingShare = metadata; return }
        do { try await requireStore().accept(metadata); reload() } catch { self.error = error.localizedDescription }
    }
    func export() throws -> URL {
        tracker.flush()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XingjiExports")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Export files contain private data: discard prior archives before producing another.
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
        let url = directory.appendingPathComponent("行迹-\(Date().formatted(.iso8601.year().month().day())).zip")
        let writer = try ZipWriter(url: url), encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try writer.add(name: "visits.json", data: encoder.encode(visits)); try writer.add(name: "trips.json", data: encoder.encode(trips))
        try writer.add(name: "README.txt", data: Data("行迹数据导出 v1\n时间使用 ISO 8601。照片位于 photos/，文件名对应 photoIDs。路线位于 routes/，每个 trkseg 为单独路线片段；片段间不代表连续路线。此文件包含私人记录，请谨慎分享。\n".utf8))
        for id in Set(visits.flatMap(\.photoIDs)) { if let data = try requireStore().photo(id) { try writer.add(name: "photos/\(id).jpg", data: data) } }
        for trip in trips { try writer.add(name: "routes/\(trip.id).gpx", data: Data(GPXExporter.render(trip: trip, chunks: try chunks(for: trip)).utf8)) }
        try writer.finish(); return url
    }
}
