import Foundation
import CoreData
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import XingjiCore
import XingjiData

struct Failure: Error, CustomStringConvertible { let description: String }
@main struct Verify {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ condition: Bool, _ message: String) throws { guard condition else { throw Failure(description:message) }; passed += 1; print("PASS \(message)") }
        let start = Date(timeIntervalSince1970:1_700_000_000)
        func point(_ t:Double,_ lat:Double = 31.23,_ accuracy:Double = 10) -> LocationSample { LocationSample(coordinate:Coordinate(lat,121.47),date:start.addingTimeInterval(t),accuracy:accuracy) }
        var detector = StopDetector()
        for t in stride(from:0,through:120,by:30) { _ = detector.ingest(point(Double(t))) }
        try check(detector.ingest(point(150,31.24)) == nil,"路过不生成到访")
        detector.reset()
        for t in stride(from:0,through:360,by:30) { _ = detector.ingest(point(Double(t))) }
        let stop = detector.ingest(point(390,31.24))
        try check(stop?.arrival == start && stop?.departure == start.addingTimeInterval(360),"超过五分钟停留生成正确时间")
        detector.reset(); _ = detector.ingest(point(0)); _ = detector.ingest(point(300)); _ = detector.ingest(point(600))
        try check(detector.completed() == nil,"定位缺口不能拼成停留")
        let gcj = Coordinate(31.23,121.47,system:.gcj02)
        let evidence = DetectedStop(coordinate:gcj,arrival:start,departure:start.addingTimeInterval(600),accuracy:10)
        let cafe = Place(id:"amap:1",name:"咖啡",address:"一楼",coordinate:gcj)
        let neighbor = Place(id:"amap:2",name:"咖啡",address:"二楼",coordinate:gcj)
        try check(PlaceMatcher.match(stop:evidence,candidates:[cafe,neighbor]).1 == .pending,"商场相邻店铺保留待确认")
        try check(PlaceMatcher.match(stop:evidence,candidates:[cafe]).0?.id == cafe.id,"明确匹配保留具体分店标识")
        try check(gcj.distance(to:Coordinate(31.23,121.47)).isInfinite,"不同坐标系不能直接比较")
        let uncertain = DetectedStop(coordinate:gcj,arrival:start,departure:start.addingTimeInterval(600),accuracy:80)
        try check(PlaceMatcher.match(stop:uncertain,candidates:[cafe]).1 == .pending,"精度不足不强行匹配")
        var route = RouteRecorder(); _ = route.append(point(0)); _ = route.append(point(10))
        let first = route.append(point(400))
        try check(first?.points.count == 2 && route.current.gapBefore != nil,"超过三分钟中断分段")
        try check(route.append(point(401,32))?.points.count == 1 && route.current.points.isEmpty,"GPS 跳变断开路线")
        _ = route.append(point(410)); let bad = route.append(point(420,31.23,500))
        try check(bad?.points.count == 1 && route.current.points.isEmpty,"精度过低不进入路线")
        _ = route.append(point(500)); _ = route.append(point(490))
        try check(route.current.points.count == 1,"乱序位置不写入")
        var bounded = RouteRecorder(); var emitted = 0
        for t in 0..<600 { if bounded.append(point(Double(t))) != nil { emitted += 1 } }
        try check(bounded.current.points.count <= 256 && emitted == 2,"长轨迹按 256 点分块")
        try check(Rating.average([nil,4,5]) == 4.5 && Rating.average([nil]) == nil,"平均分忽略未评分")
        try check(!Rating.isValid(0) && !Rating.isValid(3.2) && !Rating.isValid(.nan) && Rating.isValid(4.5),"只接受有效半星评分")
        var state = TrackingState(); state.resume(); try check(state.mode == .off,"无旅行时不能恢复旅游")
        state.startTrip(UUID()); state.pause(); state.resume(); state.finishTrip()
        try check(state.mode == .daily && state.tripID == nil,"旅游结束返回日常")
        let privateVisit = Visit(arrival:start,departure:start.addingTimeInterval(600),coordinate:Coordinate(31.23,121.47),place:cafe,rating:4.5,note:"原始感受")
        let snapshot = SharedSnapshot(visit:privateVisit)
        let dictionary = try JSONSerialization.jsonObject(with:JSONEncoder().encode(snapshot)) as! [String:Any]
        try check(dictionary["coordinate"] == nil && dictionary["arrival"] == nil && dictionary["departure"] == nil && dictionary["photoIDs"] == nil,"共享结构无坐标、精确时刻与私人照片引用")
        let trip = Trip(title:"A&B<旅行>",startedAt:start)
        let chunks = [TripChunk(tripID:trip.id,segment:RouteSegment(points:[point(0)])),TripChunk(tripID:trip.id,segment:RouteSegment(gapBefore:"暂停",points:[point(400)]))]
        let gpx = GPXExporter.render(trip:trip,chunks:chunks)
        try check(gpx.contains("A&amp;B&lt;旅行&gt;") && gpx.components(separatedBy:"<trkseg>").count == 3,"GPX 保留分段且正确转义")
        try check(snapshot.day == "2023-11-15", "共享日期固定按中国时区且不包含时刻")
        let longVisit = Visit(arrival: start.addingTimeInterval(-600), departure: start.addingTimeInterval(900), coordinate: Coordinate(31.23,121.47))
        let overlapping = DetectedStop(coordinate: Coordinate(31.23,121.47), arrival: start, departure: start.addingTimeInterval(600), accuracy: 10)
        try check(VisitDeduplicator.existing(for: overlapping, in: [longVisit])?.id == longVisit.id, "系统到访与旅游采样的重叠记录去重")
        let later = DetectedStop(coordinate: Coordinate(31.23,121.47), arrival: start.addingTimeInterval(3600), departure: start.addingTimeInterval(4200), accuracy: 10)
        try check(VisitDeduplicator.existing(for: later, in: [longVisit]) == nil, "同一天再次到访保留独立记录")
        let home = IgnoredPlace(coordinate: Coordinate(31.23,121.47), name: "家")
        try check(home.contains(Coordinate(31.2301,121.47)) && !home.contains(Coordinate(31.24,121.47)), "忽略地点仅覆盖指定半径")
        try check(ZipWriter.crc32(Data("123456789".utf8)) == 0xcbf43926,"ZIP CRC32 标准校验")
        let bitmap = CGContext(data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 12000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let imageBytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(imageBytes, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, bitmap.makeImage()!, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.23, kCGImagePropertyGPSLongitude: 121.47], kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:06 12:34:56"]] as CFDictionary)
        try check(CGImageDestinationFinalize(destination), "构建含定位元数据的测试照片")
        let cleaned = try PhotoSanitizer.sanitizedJPEG(imageBytes as Data)
        let cleanedSource = CGImageSourceCreateWithData(cleaned as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(cleanedSource, 0, nil)! as NSDictionary
        try check(properties[kCGImagePropertyGPSDictionary] == nil, "真实 JPEG 清除 GPS 元数据")
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        try check(exif?[kCGImagePropertyExifDateTimeOriginal] == nil, "共享照片不保留原始拍摄时间")
        try check((properties[kCGImagePropertyPixelWidth] as? Int) == 2048, "照片压缩限制最长边 2048")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XingjiVerify-\(UUID())")
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = try Persistence(directory:directory,inMemory:true)
        try store.saveVisit(privateVisit)
        var edited = privateVisit; edited.note="修改后"; try store.saveVisit(edited)
        let visits = try store.records("visit",as:Visit.self)
        try check(visits.count == 1 && visits[0].note == "修改后","Core Data 更新而非重复插入")
        var invalid=edited; invalid.rating=6
        var rejected=false
        do { try store.saveVisit(invalid) } catch { rejected=true }
        try check(rejected,"持久化拒绝无效评分")
        let otherTrip = Trip(title: "另一趟旅行")
        let otherChunk = TripChunk(tripID: otherTrip.id, segment: RouteSegment(points: [point(900)]))
        try store.put(chunks[0], kind: "chunk", id: chunks[0].id.uuidString, scope: trip.id.uuidString)
        try store.put(otherChunk, kind: "chunk", id: otherChunk.id.uuidString, scope: otherTrip.id.uuidString)
        let selectedChunks = try store.records("chunk", as: TripChunk.self, scope: trip.id.uuidString)
        try check(selectedChunks.count == 1 && selectedChunks[0].tripID == trip.id, "旅行路线按行程隔离查询")
        let photoID = try store.addPhoto(Data([1,2,3]),ownerID:privateVisit.id)
        try check(try store.photo(photoID) == Data([1,2,3]),"照片二进制正确往返")
        let list = try store.createList(title:"周末咖啡")
        try await store.publish(snapshot,photos:[Data([4,5])],to:list)
        guard let entry = store.entries(in:list).first else { throw Failure(description:"缺少共享条目") }
        try check(try store.snapshot(entry).note == "原始感受","私人修改不自动发布")
        try check(Set(entry.entity.relationshipsByName.keys) == ["list","photos"],"共享关系图与私人记录完全隔离")
        try check(store.sharedPhotos(entry) == [Data([4,5])],"共享照片使用独立副本")
        let participantList = NSEntityDescription.insertNewObject(forEntityName:"SharedList",into:store.context)
        store.context.assign(participantList,to:store.sharedStore!); try store.save()
        rejected=false
        do { try await store.publish(snapshot,photos:[],to:participantList) } catch { rejected=true }
        try check(rejected && !store.isOwner(participantList),"共享参与者无写入权限")
        store.context.delete(participantList); try store.save()
        try store.deleteVisit(privateVisit)
        try check(store.entries(in:list).isEmpty,"删除私人记录撤回拥有的共享副本")
        for entity in Persistence.model().entities {
            try check(entity.uniquenessConstraints.isEmpty && entity.relationshipsByName.values.allSatisfy { $0.isOptional && $0.inverseRelationship != nil },"CloudKit 模型兼容：\(entity.name!)")
        }
        try await store.deleteAll()
        try check(try store.lists().isEmpty && store.records("visit",as:Visit.self).isEmpty && store.photo(photoID) == nil,"全量删除记录、照片与清单")
        let zipURL=directory.appendingPathComponent("test.zip")
        let zip=try ZipWriter(url:zipURL); try zip.add(name:"路线.gpx",data:Data(gpx.utf8)); try zip.add(name:"photos/a.jpg",data:Data([1,2,3])); try zip.finish()
        let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/unzip"); process.arguments=["-tq",zipURL.path]
        try process.run(); process.waitUntilExit(); try check(process.terminationStatus == 0,"系统 unzip 校验导出 ZIP 与中文文件名")
        let unicodeCheck = Process(); unicodeCheck.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        unicodeCheck.arguments = ["-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.namelist()==['路线.gpx','photos/a.jpg']; assert z.testzip() is None", zipURL.path]
        try unicodeCheck.run(); unicodeCheck.waitUntilExit(); try check(unicodeCheck.terminationStatus == 0, "Python zipfile 确认 UTF-8 文件名与内容")
        let diskDirectory = directory.appendingPathComponent("disk")
        do { let disk = try Persistence(directory:diskDirectory); try disk.saveVisit(privateVisit) }
        let reopened = try Persistence(directory:diskDirectory)
        try check(try reopened.records("visit",as:Visit.self).count == 1,"SQLite 重启后记录仍存在")
        print("\n\(passed) checks passed. CloudKit networking, iOS UI and real GPS require signed device testing.")
    }
}
