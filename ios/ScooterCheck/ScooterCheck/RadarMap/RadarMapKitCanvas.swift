import SwiftUI
import MapKit

final class RadarSightingAnnotation: NSObject, MKAnnotation {
    let sighting: RadarSighting
    let repeatCount: Int
    let isHiddenDevice: Bool
    let sequenceIndex: Int?

    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(sighting: RadarSighting, repeatCount: Int, isHiddenDevice: Bool, sequenceIndex: Int?) {
        self.sighting = sighting
        self.repeatCount = repeatCount
        self.isHiddenDevice = isHiddenDevice
        self.sequenceIndex = sequenceIndex
        self.coordinate = sighting.location?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self.title = sighting.displayName
        let warn = sighting.approvalStatusRaw == GermanVehicleApprovalStatus.noGermanApprovalDocumented.rawValue
        self.subtitle = [
            sighting.signalLabel,
            repeatCount >= 2 ? "\(repeatCount)× erkannt" : nil,
            warn ? "Zulassung prüfen" : nil,
            isHiddenDevice ? "Ausgeblendet" : nil
        ].compactMap { $0 }.joined(separator: " · ")
        super.init()
    }
}

struct RadarMapKitCanvas: UIViewRepresentable {
    var sightings: [RadarSighting]
    var focusIdentityId: UUID?
    var showHeatmap: Bool
    var satellite: Bool
    var fitToken: Int
    var centerUserToken: Int
    var onSelect: (RadarSighting) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "radarSighting"
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        map.mapType = satellite ? .hybrid : .standard

        let existing = map.annotations.compactMap { $0 as? RadarSightingAnnotation }
        let ids = Set(sightings.map(\.id))
        for a in existing where !ids.contains(a.sighting.id) {
            map.removeAnnotation(a)
        }
        let present = Set(existing.map(\.sighting.id))
        let counts = Dictionary(grouping: sightings.compactMap(\.deviceIdentityId), by: { $0 })
            .mapValues(\.count)

        let ordered = focusIdentityId == nil
            ? sightings
            : sightings.filter { $0.deviceIdentityId == focusIdentityId }.sorted { $0.firstSeenAt < $1.firstSeenAt }

        for (idx, s) in ordered.enumerated() {
            guard s.hasLocation else { continue }
            let n = s.deviceIdentityId.flatMap { counts[$0] } ?? 1
            let hidden = false // caller filters; annotation flag from settings sheet path
            if present.contains(s.id) {
                if let old = existing.first(where: { $0.sighting.id == s.id }) {
                    map.removeAnnotation(old)
                }
            }
            let ann = RadarSightingAnnotation(
                sighting: s,
                repeatCount: n,
                isHiddenDevice: hidden,
                sequenceIndex: focusIdentityId != nil ? idx + 1 : nil
            )
            map.addAnnotation(ann)
        }

        // Heatmap overlays
        map.overlays.forEach { map.removeOverlay($0) }
        if showHeatmap {
            var buckets: [String: (lat: Double, lon: Double, n: Int)] = [:]
            for s in sightings {
                guard let loc = s.location, loc.isUsable else { continue }
                let key = "\(Int(loc.latitude * 200)):\(Int(loc.longitude * 200))"
                var b = buckets[key] ?? (loc.latitude, loc.longitude, 0)
                b.n += 1
                buckets[key] = b
            }
            let maxN = max(buckets.values.map(\.n).max() ?? 1, 1)
            for b in buckets.values {
                let t = Double(b.n) / Double(maxN)
                let circle = MKCircle(
                    center: CLLocationCoordinate2D(latitude: b.lat, longitude: b.lon),
                    radius: 40 + t * 120
                )
                context.coordinator.heatStrength[ObjectIdentifier(circle)] = 0.12 + t * 0.35
                map.addOverlay(circle)
            }
        }

        // Focus polyline (documented sites only)
        if focusIdentityId != nil {
            let coords = ordered.compactMap { $0.location?.coordinate }
            if coords.count >= 2 {
                map.addOverlay(MKPolyline(coordinates: coords, count: coords.count))
            }
        }

        if context.coordinator.lastFitToken != fitToken {
            context.coordinator.lastFitToken = fitToken
            fit(map)
        }
        if context.coordinator.lastCenterToken != centerUserToken {
            context.coordinator.lastCenterToken = centerUserToken
            if let loc = map.userLocation.location {
                map.setRegion(
                    MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 800, longitudinalMeters: 800),
                    animated: true
                )
            }
        }
    }

    private func fit(_ map: MKMapView) {
        let coords = sightings.compactMap { $0.location?.coordinate }
        guard let first = coords.first else { return }
        var rect = MKMapRect(
            origin: MKMapPoint(first),
            size: MKMapSize(width: 1, height: 1)
        )
        for c in coords.dropFirst() {
            let pt = MKMapPoint(c)
            rect = rect.union(MKMapRect(origin: pt, size: MKMapSize(width: 1, height: 1)))
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40), animated: true)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (RadarSighting) -> Void
        var lastFitToken = -1
        var lastCenterToken = -1
        var heatStrength: [ObjectIdentifier: CGFloat] = [:]

        init(onSelect: @escaping (RadarSighting) -> Void) {
            self.onSelect = onSelect
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? RadarSightingAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: "radarSighting",
                for: annotation
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "radarSighting")
            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = ann.isHiddenDevice
                ? .gray
                : (ann.sighting.approvalStatusRaw == GermanVehicleApprovalStatus.noGermanApprovalDocumented.rawValue
                    ? Theme.UI.danger
                    : Theme.UI.accent)
            if let seq = ann.sequenceIndex {
                view.glyphText = "\(seq)"
            } else if ann.repeatCount >= 2 {
                view.glyphText = "\(min(ann.repeatCount, 99))"
            } else {
                view.glyphImage = UIImage(systemName: "mappin")
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? RadarSightingAnnotation else { return }
            onSelect(ann.sighting)
            mapView.deselectAnnotation(ann, animated: true)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                let a = heatStrength[ObjectIdentifier(circle)] ?? 0.2
                r.fillColor = Theme.UI.accent.withAlphaComponent(a)
                r.strokeColor = .clear
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = Theme.UI.accent.withAlphaComponent(0.4)
                r.lineWidth = 2
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
