import Foundation
import CoreLocation
import XingjiCore
#if canImport(AMapSearchKit) && canImport(MAMapKit)
import AMapSearchKit
import MAMapKit
import AMapFoundationKit
#endif

enum MapError: LocalizedError {
    case notConfigured, timeout, invalidCoordinate
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "地图尚未配置。开发者需接入高德 SDK 并填写应用 Key。"
        case .timeout: return "店铺查询超时，稍后可重新匹配。"
        case .invalidCoordinate: return "无法转换此地点的坐标。"
        }
    }
}
@MainActor protocol PlaceSearching {
    var available: Bool { get }
    func mapCoordinate(_ coordinate: Coordinate) throws -> Coordinate
    func nearby(_ coordinate: Coordinate) async throws -> [Place]
    func search(_ keyword: String) async throws -> [Place]
}

@MainActor final class AMapPlaceService: NSObject, PlaceSearching {
    var available: Bool {
        #if canImport(AMapSearchKit) && canImport(MAMapKit)
        return Configuration.hasMapKey
        #else
        return false
        #endif
    }
    #if canImport(AMapSearchKit) && canImport(MAMapKit)
    private var api: AMapSearchAPI?
    private struct Pending {
        let continuation: CheckedContinuation<[Place], Error>
        let request: AMapSearchObject
        let timeout: Task<Void, Never>
    }
    private var pending: [ObjectIdentifier: Pending] = [:]
    #endif
    override init() {
        super.init()
        #if canImport(AMapSearchKit) && canImport(MAMapKit)
        guard Configuration.hasMapKey, UserDefaults.standard.bool(forKey: "privacyAccepted") else { return }
        MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        MAMapView.updatePrivacyAgree(.didAgree)
        AMapSearchAPI.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapSearchAPI.updatePrivacyAgree(.didAgree)
        AMapServices.shared().regionLanguageType = .zhHans
        AMapServices.shared().apiKey = Configuration.amapKey
        api = AMapSearchAPI(); api?.delegate = self
        #endif
    }
    func mapCoordinate(_ coordinate: Coordinate) throws -> Coordinate {
        guard coordinate.isValid else { throw MapError.invalidCoordinate }
        if coordinate.system == .gcj02 { return coordinate }
        #if canImport(AMapSearchKit) && canImport(MAMapKit)
        let p = AMapCoordinateConvert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude), .GPS)
        return Coordinate(p.latitude, p.longitude, system: .gcj02)
        #else
        throw MapError.notConfigured
        #endif
    }
    func nearby(_ coordinate: Coordinate) async throws -> [Place] {
        #if canImport(AMapSearchKit) && canImport(MAMapKit)
        guard available, api != nil else { throw MapError.notConfigured }
        let p = try mapCoordinate(coordinate)
        let request = AMapPOIAroundSearchRequest()
        request.location = AMapGeoPoint.location(withLatitude: CGFloat(p.latitude), longitude: CGFloat(p.longitude))
        request.radius = 150; request.types = "050000|060000"; request.offset = 25; request.sortrule = 0
        return try await run(request) { self.api?.aMapPOIAroundSearch(request) }
        #else
        throw MapError.notConfigured
        #endif
    }
    func search(_ keyword: String) async throws -> [Place] {
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        #if canImport(AMapSearchKit) && canImport(MAMapKit)
        guard available, api != nil else { throw MapError.notConfigured }
        let request = AMapPOIKeywordsSearchRequest(); request.keywords = keyword; request.offset = 25
        return try await run(request) { self.api?.aMapPOIKeywordsSearch(request) }
        #else
        throw MapError.notConfigured
        #endif
    }
    #if canImport(AMapSearchKit) && canImport(MAMapKit)
    private func run(_ request: AMapSearchObject, start: () -> Void) async throws -> [Place] {
        let id = ObjectIdentifier(request)
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let item = self?.pending.removeValue(forKey: id) else { return }
                item.continuation.resume(throwing: MapError.timeout)
            }
            pending[id] = Pending(continuation: continuation, request: request, timeout: timeout)
            start()
        }
    }
    #endif
}
#if canImport(AMapSearchKit) && canImport(MAMapKit)
extension AMapPlaceService: AMapSearchDelegate {
    nonisolated func onPOISearchDone(_ request: AMapPOISearchBaseRequest!, response: AMapPOISearchResponse!) {
        guard let request else { return }
        let id = ObjectIdentifier(request)
        let places: [Place] = (response?.pois ?? []).compactMap { poi in
            guard let location = poi.location, let id = poi.uid, let name = poi.name else { return nil }
            return Place(id: "amap:\(id)", name: name, address: [poi.province,poi.city,poi.district,poi.address].compactMap { $0 }.joined(), coordinate: Coordinate(Double(location.latitude), Double(location.longitude), system: .gcj02), category: poi.type ?? "")
        }
        Task { @MainActor [weak self] in self?.complete(id, result: .success(places)) }
    }
    nonisolated func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
        guard let object = request as? AMapSearchObject else { return }
        let id = ObjectIdentifier(object), failure = error ?? MapError.timeout
        Task { @MainActor [weak self] in self?.complete(id, result: .failure(failure)) }
    }
    private func complete(_ id: ObjectIdentifier, result: Result<[Place], Error>) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timeout.cancel(); item.continuation.resume(with: result)
    }
}
#endif
