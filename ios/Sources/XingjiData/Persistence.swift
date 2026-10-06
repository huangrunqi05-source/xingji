import Foundation
import CoreData
import CloudKit
import XingjiCore

public enum StoreError: LocalizedError {
    case invalidRecord, cloudNotConfigured, missingStore, permissionDenied
    public var errorDescription: String? {
        switch self {
        case .invalidRecord: return "记录内容无效，请检查时间和评分。"
        case .cloudNotConfigured: return "iCloud 共享尚未配置，记录已保存在本机。"
        case .missingStore: return "数据存储尚未准备好。"
        case .permissionDenied: return "你只有此清单的查看权限。"
        }
    }
}

@MainActor public final class Persistence {
    public let container: NSPersistentCloudKitContainer
    public let cloudIdentifier: String?
    public var context: NSManagedObjectContext { container.viewContext }
    public var privateStore: NSPersistentStore? { container.persistentStoreCoordinator.persistentStores.first { $0.configurationName == "Private" } }
    public var sharedStore: NSPersistentStore? { container.persistentStoreCoordinator.persistentStores.first { $0.configurationName == "Shared" } }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL, cloudIdentifier: String? = nil, inMemory: Bool = false) throws {
        self.cloudIdentifier = cloudIdentifier
        container = NSPersistentCloudKitContainer(name: "Xingji", managedObjectModel: Self.model())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptions = ["Private", "Shared"].map { name -> NSPersistentStoreDescription in
            let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("\(name).sqlite"))
            description.configuration = name
            if inMemory { description.type = NSInMemoryStoreType }
            #if os(iOS)
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication.rawValue as NSString, forKey: NSPersistentStoreFileProtectionKey)
            #endif
            description.shouldAddStoreAsynchronously = false
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if let cloudIdentifier, !inMemory {
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudIdentifier)
                options.databaseScope = name == "Private" ? .private : .shared
                description.cloudKitContainerOptions = options
            }
            return description
        }
        container.persistentStoreDescriptions = descriptions
        var loadError: Error?
        container.loadPersistentStores { _, error in if let error { loadError = error } }
        if let loadError { throw loadError }
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "Xingji"
        #if DEBUG
        if cloudIdentifier != nil, ProcessInfo.processInfo.environment["XINGJI_INITIALIZE_SCHEMA"] == "1" {
            try container.initializeCloudKitSchema(options: [])
        }
        #endif
    }

    public func save() throws { if context.hasChanges { try context.save() } }
    public func records<T: Decodable>(_ kind: String, as type: T.Type, scope: String? = nil) throws -> [T] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PrivateRecord")
        request.predicate = scope.map { NSPredicate(format: "kind == %@ AND scope == %@", kind, $0) } ?? NSPredicate(format: "kind == %@", kind)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        if let privateStore { request.affectedStores = [privateStore] }
        var seen = Set<String>()
        return try context.fetch(request).compactMap { object in
            guard let key = object.value(forKey: "key") as? String, seen.insert(key).inserted else { return nil }
            guard let data = object.value(forKey: "payload") as? Data else { throw StoreError.invalidRecord }
            return try decoder.decode(T.self, from: data)
        }
    }
    public func put<T: Encodable>(_ value: T, kind: String, id: String, scope: String? = nil) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PrivateRecord")
        request.predicate = NSPredicate(format: "kind == %@ AND key == %@", kind, id)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        if let privateStore { request.affectedStores = [privateStore] }
        let existing = try context.fetch(request)
        let object = try existing.first ?? insert("PrivateRecord")
        object.setValue(id, forKey: "key"); object.setValue(kind, forKey: "kind"); object.setValue(scope, forKey: "scope")
        object.setValue(try encoder.encode(value), forKey: "payload"); object.setValue(Date(), forKey: "updatedAt")
        for duplicate in existing.dropFirst() { context.delete(duplicate) }
        try save()
    }
    public func delete(kind: String, id: String) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PrivateRecord")
        request.predicate = NSPredicate(format: "kind == %@ AND key == %@", kind, id)
        if let privateStore { request.affectedStores = [privateStore] }
        for record in try context.fetch(request) { context.delete(record) }
        try save()
    }
    public func saveVisit(_ visit: Visit) throws {
        guard visit.isValid else { throw StoreError.invalidRecord }
        try put(visit, kind: "visit", id: visit.id.uuidString)
    }
    public func addPhoto(_ bytes: Data, ownerID: UUID) throws -> UUID {
        let id = UUID(), photo = try insert("PhotoBlob")
        photo.setValue(id.uuidString, forKey: "key"); photo.setValue(ownerID.uuidString, forKey: "ownerID"); photo.setValue(bytes, forKey: "bytes")
        try save(); return id
    }
    public func photo(_ id: UUID) throws -> Data? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PhotoBlob")
        request.predicate = NSPredicate(format: "key == %@", id.uuidString)
        request.fetchLimit = 1
        if let privateStore { request.affectedStores = [privateStore] }
        return try context.fetch(request).first?.value(forKey: "bytes") as? Data
    }
    public func removePhoto(_ id: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PhotoBlob")
        request.predicate = NSPredicate(format: "key == %@", id.uuidString)
        if let privateStore { request.affectedStores = [privateStore] }
        for photo in try context.fetch(request) { context.delete(photo) }
        try save()
    }
    public func deleteVisit(_ visit: Visit) throws {
        // Removing the private original also withdraws owned shared copies.
        for list in try lists() where isOwner(list) {
            for entry in entries(in: list) where (try? snapshot(entry).sourceVisitID) == visit.id { context.delete(entry) }
        }
        for id in visit.photoIDs { try removePhoto(id) }
        try delete(kind: "visit", id: visit.id.uuidString)
        try save()
    }
    public func lists() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SharedList")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }
    public func createList(title: String) throws -> NSManagedObject {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.invalidRecord }
        let list = try insert("SharedList")
        list.setValue(UUID().uuidString, forKey: "key"); list.setValue(title, forKey: "title"); list.setValue(Date(), forKey: "createdAt")
        try save(); return list
    }
    public func isOwner(_ object: NSManagedObject) -> Bool { object.objectID.persistentStore?.configurationName == "Private" }
    public func entries(in list: NSManagedObject) -> [NSManagedObject] {
        let entries = (list.value(forKey: "entries") as? Set<NSManagedObject>) ?? []
        return entries.sorted { (($0.value(forKey: "createdAt") as? Date) ?? .distantPast) > (($1.value(forKey: "createdAt") as? Date) ?? .distantPast) }
    }
    public func snapshot(_ entry: NSManagedObject) throws -> SharedSnapshot {
        guard let data = entry.value(forKey: "payload") as? Data else { throw StoreError.invalidRecord }
        return try decoder.decode(SharedSnapshot.self, from: data)
    }
    public func sharedPhotos(_ entry: NSManagedObject) -> [Data] {
        let photos = (entry.value(forKey: "photos") as? Set<NSManagedObject>) ?? []
        return photos.sorted { ($0.value(forKey: "key") as? String ?? "") < ($1.value(forKey: "key") as? String ?? "") }.compactMap { $0.value(forKey: "bytes") as? Data }
    }
    /// Only detached snapshots and re-encoded photo bytes may enter the shared graph.
    public func publish(_ snapshot: SharedSnapshot, photos: [Data], to list: NSManagedObject) async throws {
        guard isOwner(list) else { throw StoreError.permissionDenied }
        let entry = try insert("SharedEntry", store: list.objectID.persistentStore)
        entry.setValue(snapshot.id.uuidString, forKey: "key"); entry.setValue(Date(), forKey: "createdAt")
        entry.setValue(try encoder.encode(snapshot), forKey: "payload"); entry.setValue(list, forKey: "list")
        for data in photos {
            let photo = try insert("SharedPhoto", store: list.objectID.persistentStore)
            photo.setValue(UUID().uuidString, forKey: "key"); photo.setValue(data, forKey: "bytes"); photo.setValue(entry, forKey: "entry")
        }
        do {
            try save()
            if cloudIdentifier != nil, let share = try container.fetchShares(matching: [list.objectID])[list.objectID] {
                try await addToShare([entry], share: share)
            }
        } catch {
            context.delete(entry); try? save(); throw error
        }
    }
    public func removeEntry(_ entry: NSManagedObject) throws {
        guard isOwner(entry) else { throw StoreError.permissionDenied }
        context.delete(entry); try save()
    }
    public func deleteLocalList(_ list: NSManagedObject) throws {
        guard isOwner(list) else { throw StoreError.permissionDenied }
        context.delete(list); try save()
    }
    public func prepareShare(_ list: NSManagedObject) async throws -> CKShare {
        guard cloudIdentifier != nil else { throw StoreError.cloudNotConfigured }
        guard isOwner(list) else { throw StoreError.permissionDenied }
        if let existing = try container.fetchShares(matching: [list.objectID])[list.objectID] { return existing }
        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            container.share([list], to: nil) { _, share, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let share { continuation.resume(returning: share) }
                else { continuation.resume(throwing: StoreError.missingStore) }
            }
        }
        share[CKShare.SystemFieldKey.title] = list.value(forKey: "title") as? String
        share.publicPermission = .none
        for participant in share.participants where participant.role != .owner { participant.permission = .readOnly }
        try await persistShare(share, store: list.objectID.persistentStore)
        return share
    }
    private func addToShare(_ objects: [NSManagedObject], share: CKShare) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.share(objects, to: share) { _, _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    public func persistShare(_ share: CKShare, store: NSPersistentStore?) async throws {
        guard let store else { throw StoreError.missingStore }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.persistUpdatedShare(share, in: store) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    public func accept(_ metadata: CKShare.Metadata) async throws {
        guard cloudIdentifier != nil else { throw StoreError.cloudNotConfigured }
        guard let sharedStore else { throw StoreError.missingStore }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    /// Revokes a shared list (owner) or leaves it (participant), never purges the private default zone.
    public func leaveOrDeleteList(_ list: NSManagedObject) async throws {
        if cloudIdentifier != nil, let share = try container.fetchShares(matching: [list.objectID])[list.objectID], let store = list.objectID.persistentStore {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        } else { try deleteLocalList(list) }
    }
    public func deleteAll() async throws {
        for list in try lists() { try await leaveOrDeleteList(list) }
        for entity in ["PrivateRecord", "PhotoBlob"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            if let privateStore { request.affectedStores = [privateStore] }
            for object in try context.fetch(request) { context.delete(object) }
        }
        try save()
    }
    private func insert(_ entity: String, store: NSPersistentStore? = nil) throws -> NSManagedObject {
        guard let target = store ?? privateStore else { throw StoreError.missingStore }
        let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        context.assign(object, to: target); return object
    }

    public static func model() -> NSManagedObjectModel {
        func attr(_ name: String, _ type: NSAttributeType, external: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type; a.isOptional = true
            a.allowsExternalBinaryDataStorage = external; return a
        }
        func entity(_ name: String, _ properties: [NSPropertyDescription]) -> NSEntityDescription {
            let e = NSEntityDescription(); e.name = name; e.managedObjectClassName = "NSManagedObject"; e.properties = properties; return e
        }
        func relate(_ parent: NSEntityDescription, _ parentKey: String, _ child: NSEntityDescription, _ childKey: String) {
            let children = NSRelationshipDescription(); children.name = parentKey; children.destinationEntity = child; children.minCount = 0; children.maxCount = 0; children.isOptional = true; children.deleteRule = .cascadeDeleteRule
            let owner = NSRelationshipDescription(); owner.name = childKey; owner.destinationEntity = parent; owner.minCount = 0; owner.maxCount = 1; owner.isOptional = true; owner.deleteRule = .nullifyDeleteRule
            children.inverseRelationship = owner; owner.inverseRelationship = children
            parent.properties.append(children); child.properties.append(owner)
        }
        let record = entity("PrivateRecord", [attr("key", .stringAttributeType), attr("kind", .stringAttributeType), attr("scope", .stringAttributeType), attr("payload", .binaryDataAttributeType, external: true), attr("updatedAt", .dateAttributeType)])
        let photo = entity("PhotoBlob", [attr("key", .stringAttributeType), attr("ownerID", .stringAttributeType), attr("bytes", .binaryDataAttributeType, external: true)])
        let list = entity("SharedList", [attr("key", .stringAttributeType), attr("title", .stringAttributeType), attr("createdAt", .dateAttributeType)])
        let entry = entity("SharedEntry", [attr("key", .stringAttributeType), attr("payload", .binaryDataAttributeType), attr("createdAt", .dateAttributeType)])
        let sharedPhoto = entity("SharedPhoto", [attr("key", .stringAttributeType), attr("bytes", .binaryDataAttributeType, external: true)])
        relate(list, "entries", entry, "list"); relate(entry, "photos", sharedPhoto, "entry")
        let m = NSManagedObjectModel(); m.entities = [record, photo, list, entry, sharedPhoto]
        m.setEntities(m.entities, forConfigurationName: "Private")
        m.setEntities([list, entry, sharedPhoto], forConfigurationName: "Shared")
        return m
    }
}
