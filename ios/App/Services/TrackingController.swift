import Foundation
import CoreLocation
import Combine
import XingjiCore

@MainActor final class TrackingController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var state: TrackingState
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var status = "记录已关闭"
    @Published private(set) var latest: LocationSample?
    var onStop: ((DetectedStop) -> Void)?
    var onChunk: ((TripChunk) -> Void)?
    private let manager = CLLocationManager()
    private var detector = StopDetector()
    private var route = RouteRecorder()
    private var active = false
    private var captureStartedAt = UserDefaults.standard.object(forKey: "captureStartedAt") as? Date ?? Date()
    private var lastPersistedAt = Date.distantPast
    override init() {
        state = (UserDefaults.standard.data(forKey: "trackingState").flatMap { try? JSONDecoder().decode(TrackingState.self, from: $0) }) ?? TrackingState()
        super.init(); manager.delegate = self
        manager.activityType = .other; manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }
    func restore() { if UserDefaults.standard.bool(forKey: "privacyAccepted") { breakRoute("应用重启，路线从这里继续"); apply() } }
    func enableDaily() { markCaptureStart(); state = TrackingState(mode: .daily); persistState(); requestAndApply() }
    func startTrip(_ id: UUID) { if state.mode == .off { markCaptureStart() }; flushStop(); breakRoute("新的旅游行程"); state.startTrip(id); persistState(); requestAndApply() }
    func pause() { flushStop(); breakRoute("手动暂停"); state.pause(); persistState(); apply() }
    func resume() { markCaptureStart(); breakRoute("暂停后继续"); state.resume(); persistState(); requestAndApply() }
    func finish() { flushStop(); breakRoute("行程结束"); state.finishTrip(); persistState(); apply() }
    func disable() { flushStop(); breakRoute("记录已关闭"); state.stop(); persistState(); apply() }
    func requestAlways() { manager.requestAlwaysAuthorization() }
    func flush() {
        if let tripID = state.tripID, !route.current.points.isEmpty { onChunk?(TripChunk(tripID: tripID, segment: route.current)) }
    }
    func foregrounded() { authorization = manager.authorizationStatus; apply() }
    private func requestAndApply() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        apply()
    }
    private func apply() {
        manager.stopUpdatingLocation(); manager.stopMonitoringVisits(); manager.stopMonitoringSignificantLocationChanges()
        active = false
        guard state.mode != .off && state.mode != .paused else { status = state.mode == .paused ? "旅游记录已暂停" : "记录已关闭"; return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            status = "定位权限未开启，无法自动记录"; return
        }
        active = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = state.mode == .touring
        if state.mode == .touring {
            manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = 15
            manager.pausesLocationUpdatesAutomatically = false; manager.startUpdatingLocation(); manager.startMonitoringVisits()
            status = "旅游模式 · 正在记录路线"
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters; manager.distanceFilter = 100
            manager.pausesLocationUpdatesAutomatically = true
            manager.startMonitoringVisits(); manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation(); status = "日常模式 · 低功耗记录停留"
        }
        if manager.authorizationStatus != .authorizedAlways { status += " · 后台记录受限" }
        if manager.accuracyAuthorization == .reducedAccuracy { status += " · 仅有大致位置" }
    }
    private func markCaptureStart() { captureStartedAt = Date(); UserDefaults.standard.set(captureStartedAt, forKey: "captureStartedAt") }
    private func persistState() { if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "trackingState") } }
    private func flushStop() { if let stop = detector.completed() { onStop?(stop) }; detector.reset() }
    private func breakRoute(_ reason: String) {
        if let chunk = route.breakRoute(reason), let tripID = state.tripID { onChunk?(TripChunk(tripID: tripID, segment: chunk)) }
        if let tripID = state.tripID { onChunk?(TripChunk(tripID: tripID, segment: route.current)) }
        detector.reset()
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }
    private func authorizationChanged() {
        authorization = manager.authorizationStatus
        if authorization == .denied || authorization == .restricted { breakRoute("定位权限被关闭") }
        if UserDefaults.standard.bool(forKey: "privacyAccepted") { apply() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map { LocationSample(coordinate: Coordinate($0.coordinate.latitude,$0.coordinate.longitude), date: $0.timestamp, accuracy: $0.horizontalAccuracy) }
        Task { @MainActor [weak self] in self?.receive(samples) }
    }
    private func receive(_ samples: [LocationSample]) {
        guard active else { return }
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            guard abs(sample.date.timeIntervalSinceNow) < 60, sample.date >= captureStartedAt else { continue }
            latest = sample
            if state.mode == .touring, let tripID = state.tripID {
                if let done = route.append(sample) { onChunk?(TripChunk(tripID: tripID, segment: done)) }
                if sample.date.timeIntervalSince(lastPersistedAt) >= 15 { flush(); lastPersistedAt = sample.date }
                if let stop = detector.ingest(sample) { onStop?(stop) }
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard visit.departureDate != .distantFuture, visit.arrivalDate != .distantPast else { return }
        let stop = DetectedStop(coordinate: Coordinate(visit.coordinate.latitude,visit.coordinate.longitude), arrival: visit.arrivalDate, departure: visit.departureDate, accuracy: visit.horizontalAccuracy)
        Task { @MainActor [weak self] in self?.receiveVisit(stop) }
    }
    private func receiveVisit(_ value: DetectedStop) {
        guard active, state.mode == .daily || state.mode == .touring, value.departure > captureStartedAt else { return }
        var stop = value; stop.arrival = max(stop.arrival, captureStartedAt)
        if stop.isValid { onStop?(stop) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.breakRoute("定位暂时不可用"); self?.status = "定位暂时不可用：\(message)" }
    }
    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.breakRoute("系统暂停定位"); self?.status = "系统已暂停定位" }
    }
    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.breakRoute("系统恢复定位"); self?.status = "定位已恢复" }
    }
}
