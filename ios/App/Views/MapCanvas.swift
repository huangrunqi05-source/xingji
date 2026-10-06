import SwiftUI
import CoreLocation
import XingjiCore
#if canImport(MAMapKit)
import MAMapKit
#endif

struct MapCanvas: View {
    let visits: [Visit]
    var chunks: [TripChunk] = []
    let service: AMapPlaceService
    var onSelect: (Visit) -> Void = { _ in }
    var body: some View {
        #if canImport(MAMapKit)
        if service.available { NativeMap(visits:visits,chunks:chunks,service:service,onSelect:onSelect) }
        else { unavailable }
        #else
        unavailable
        #endif
    }
    private var unavailable: some View {
        ContentUnavailableView { Label("地图等待连接",systemImage:"map") } description: { Text("接入高德 SDK 并配置应用 Key 后显示真实地图。\n你的本机记录仍可在「回顾」中查看。") }.background(Theme.cream)
    }
}
#if canImport(MAMapKit)
private final class VisitAnnotation: MAPointAnnotation { var visitID: UUID? }
private struct NativeMap: UIViewRepresentable {
    let visits: [Visit]
    let chunks: [TripChunk]
    let service: AMapPlaceService
    let onSelect: (Visit) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> MAMapView {
        let map = MAMapView(frame:.zero)
        map.delegate = context.coordinator; map.showsUserLocation = false
        map.isRotateEnabled = false; map.isRotateCameraEnabled = false
        map.showsCompass = true; map.showsScale = true
        // High-level mainland overview until real records are available.
        map.setCenter(CLLocationCoordinate2D(latitude:35,longitude:105),animated:false); map.setZoomLevel(4,animated:false)
        return map
    }
    func updateUIView(_ map:MAMapView,context:Context) {
        context.coordinator.parent = self
        let signature = visits.map { "\($0.id)-\($0.title)-\($0.place?.coordinate.latitude ?? $0.coordinate.latitude)-\($0.place?.coordinate.longitude ?? $0.coordinate.longitude)" }.joined() + chunks.map { "\($0.id)-\($0.segment.points.count)" }.joined()
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        if let annotations = map.annotations { map.removeAnnotations(annotations) }
        if let overlays = map.overlays { map.removeOverlays(overlays) }
        var annotations: [VisitAnnotation] = []
        for visit in visits {
            guard let c = try? service.mapCoordinate(visit.place?.coordinate ?? visit.coordinate) else { continue }
            let a = VisitAnnotation(); a.visitID = visit.id; a.coordinate = CLLocationCoordinate2D(latitude:c.latitude,longitude:c.longitude); a.title = visit.title; a.subtitle = visit.status.label
            annotations.append(a)
        }
        map.addAnnotations(annotations)
        for chunk in chunks {
            var points = chunk.segment.points.compactMap { sample -> CLLocationCoordinate2D? in
                guard let p = try? service.mapCoordinate(sample.coordinate) else { return nil }
                return CLLocationCoordinate2D(latitude:p.latitude,longitude:p.longitude)
            }
            guard points.count >= 2, points.count == chunk.segment.points.count else { continue }
            if let line = MAPolyline(coordinates:&points,count:UInt(points.count)) { map.add(line) }
        }
        if !context.coordinator.didFit, !annotations.isEmpty || !chunks.isEmpty {
            context.coordinator.didFit = true
            if let overlays = map.overlays, !overlays.isEmpty { map.showOverlays(overlays,edgePadding:UIEdgeInsets(top:40,left:30,bottom:40,right:30),animated:false) }
            else if !annotations.isEmpty { map.showAnnotations(annotations,edgePadding:UIEdgeInsets(top:40,left:40,bottom:60,right:40),animated:false) }
            else if let sample = chunks.flatMap({ $0.segment.points }).first, let point = try? service.mapCoordinate(sample.coordinate) {
                map.setCenter(CLLocationCoordinate2D(latitude:point.latitude,longitude:point.longitude),animated:false); map.setZoomLevel(16,animated:false)
            } else { context.coordinator.didFit = false }
        }
    }
    final class Coordinator: NSObject, MAMapViewDelegate {
        var parent: NativeMap; var signature = "initial"; var didFit = false
        init(_ parent:NativeMap) { self.parent = parent }
        func mapView(_ mapView:MAMapView!,viewFor annotation:MAAnnotation!) -> MAAnnotationView! {
            guard let annotation = annotation as? VisitAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier:"visit") as? MAPinAnnotationView) ?? MAPinAnnotationView(annotation:annotation,reuseIdentifier:"visit")!
            view.annotation = annotation; view.canShowCallout = true
            view.pinColor = parent.visits.first(where:{$0.id == annotation.visitID})?.status == .pending ? .purple : .green
            view.rightCalloutAccessoryView = UIButton(type:.detailDisclosure)
            return view
        }
        func mapView(_ mapView:MAMapView!,annotationView view:MAAnnotationView!,calloutAccessoryControlTapped control:UIControl!) {
            guard let annotation = view.annotation as? VisitAnnotation, let visit = parent.visits.first(where:{$0.id == annotation.visitID}) else { return }
            parent.onSelect(visit)
        }
        func mapView(_ mapView:MAMapView!,rendererFor overlay:MAOverlay!) -> MAOverlayRenderer! {
            guard let line = overlay as? MAPolyline else { return nil }
            let renderer = MAPolylineRenderer(polyline:line)!
            renderer.lineWidth = 5; renderer.strokeColor = UIColor(Theme.green); return renderer
        }
    }
}
#endif
