import SwiftUI
import ARKit
import SceneKit
import UIKit

/// Vollbild AR Signal-Finder — eine gemeinsame ARSession mit dem IndoorVisualTracker.
struct BLESearchARContainer: View {
    @ObservedObject var engine: BLESearchEngine
    @Binding var settings: ARSignalFinderSettings
    var onOpenHeatmap: () -> Void
    var onShowOptions: () -> Void
    var onEnd: () -> Void

    @State private var showOnboarding = !ARSignalFinderOnboarding.isDone
    @State private var onboardingStep = 0

    var body: some View {
        ZStack {
            BLESearchARSceneRepresentable(engine: engine, settings: settings)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                arBottomBar
            }

            if showOnboarding {
                onboardingOverlay
            }
        }
        .preferredColorScheme(.dark)
    }

    private var arBottomBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rssiLine)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text(engine.arGuidance.text)
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 220, alignment: .leading)

                HStack(spacing: Theme.Space.sm) {
                    compactAction("Pause", systemImage: engine.isSearchPaused ? "play.fill" : "pause.fill") {
                        engine.setSearchPaused(!engine.isSearchPaused)
                    }
                    compactAction("Ende", systemImage: "xmark") { onEnd() }
                    compactAction("Optionen", systemImage: "slider.horizontal.3") { onShowOptions() }
                }
            }

            Spacer(minLength: 0)

            if settings.showMinimap {
                Button(action: onOpenHeatmap) {
                    ARMinimapView(
                        pathSnapshot: engine.pathSnapshot,
                        breadcrumbs: engine.breadcrumbs,
                        bestZone: engine.arBestZone,
                        headingDegrees: engine.visualTracker.headingDegrees
                            ?? engine.pathSnapshot.current?.headingDegrees
                    )
                    .frame(width: 112, height: 112)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minikarte — Heatmap öffnen")
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.lg)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var rssiLine: String {
        if settings.showRawRssi, let raw = engine.rawRssi {
            return "\(raw) dBm"
        }
        if let rssi = engine.smoothedRssi, engine.signalClass != .lost {
            return "\(Int(rssi.rounded())) dBm"
        }
        return "— dBm"
    }

    private func compactAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.surfaceSecondary.opacity(0.92))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: Theme.Control.hairline))
        }
        .buttonStyle(.plain)
    }

    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: Theme.Space.xl) {
                Text("AR Signal-Finder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(onboardingText)
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.xl)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i == onboardingStep ? Theme.accent : Theme.textMuted.opacity(0.4))
                            .frame(width: i == onboardingStep ? 18 : 8, height: 6)
                    }
                }

                Button {
                    if onboardingStep < 2 {
                        onboardingStep += 1
                    } else {
                        ARSignalFinderOnboarding.isDone = true
                        showOnboarding = false
                        engine.setCameraTrackingEnabled(true)
                        engine.visualTracker.setPlaneDetectionEnabled(true)
                    }
                } label: {
                    Text(onboardingStep < 2 ? "Weiter" : "Suche starten")
                        .font(Theme.secondary.weight(.semibold))
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
                .padding(.horizontal, Theme.Space.xxl)
            }
            .padding(.vertical, Theme.Space.xxl)
        }
    }

    private var onboardingText: String {
        switch onboardingStep {
        case 0: return "Bewege dein iPhone langsam, damit die Umgebung erkannt wird."
        case 1: return "Gehe durch den Bereich. ScooterCheck misst die Bluetooth-Signalstärke entlang deines Weges."
        default: return "Die Farben zeigen, wo du bisher stärkere oder schwächere Signale gemessen hast."
        }
    }
}

// MARK: - ARSCNView bridge

struct BLESearchARSceneRepresentable: UIViewRepresentable {
    @ObservedObject var engine: BLESearchEngine
    var settings: ARSignalFinderSettings

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.rendersCameraGrain = false
        view.scene = SCNScene()
        view.backgroundColor = .black

        let heat = SCNNode()
        heat.name = "arHeatPlane"
        view.scene.rootNode.addChildNode(heat)

        let path = SCNNode()
        path.name = "arPath"
        view.scene.rootNode.addChildNode(path)

        let best = SCNNode()
        best.name = "arBestZone"
        view.scene.rootNode.addChildNode(best)

        context.coordinator.heatNode = heat
        context.coordinator.pathNode = path
        context.coordinator.bestNode = best
        context.coordinator.engine = engine
        context.coordinator.settings = settings

        engine.visualTracker.bindSceneView(view)
        engine.visualTracker.setPlaneDetectionEnabled(true)
        if !engine.cameraTrackingEnabled {
            engine.setCameraTrackingEnabled(true)
        }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.engine = engine
        context.coordinator.settings = settings
        engine.visualTracker.bindSceneView(uiView)
        context.coordinator.refreshContent(in: uiView)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.engine?.visualTracker.bindSceneView(nil)
        coordinator.engine?.visualTracker.setPlaneDetectionEnabled(false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        weak var engine: BLESearchEngine?
        var settings = ARSignalFinderSettings()
        var heatNode: SCNNode?
        var pathNode: SCNNode?
        var bestNode: SCNNode?
        private var lastTextureAt: Date = .distantPast
        private var lastSampleCount = 0
        private var lastEpoch = -1
        /// Letzter ENU-Punkt, für den schon ein AR-Segment gezeichnet wurde (kein Voll-Rebuild → kein Flackern).
        private var lastPathENU: (x: Double, y: Double)?
        private var lastPathEpoch = -1
        private var pathTipNode: SCNNode?

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Leichtgewichtig — schwere Texture nur in refreshContent
        }

        @MainActor
        func refreshContent(in view: ARSCNView) {
            guard let engine else { return }
            let now = Date()
            let samples = engine.arSpatialSamples
            let epoch = engine.visualTracker.sessionEpoch
            let dirty = samples.count != lastSampleCount
                || epoch != lastEpoch
                || now.timeIntervalSince(lastTextureAt) > 0.55

            updateHeatPlane(engine: engine, dirty: dirty)
            updatePath(engine: engine)
            updateBestZone(engine: engine)

            if dirty {
                lastTextureAt = now
                lastSampleCount = samples.count
                lastEpoch = epoch
            }
        }

        @MainActor
        private func updateHeatPlane(engine: BLESearchEngine, dirty: Bool) {
            guard let heatNode else { return }
            heatNode.isHidden = !settings.showHeatmap
            guard settings.showHeatmap else { return }
            guard dirty else {
                // Höhe der Ebene weiterhin an Boden anpassen
                if let y = engine.visualTracker.floorWorldY, let plane = heatNode.childNode(withName: "plane", recursively: false) {
                    plane.position.y = y
                }
                return
            }

            let samples = engine.arSpatialSamples.filter { $0.sessionEpoch == engine.visualTracker.sessionEpoch }
            guard samples.count >= 2 else {
                heatNode.enumerateChildNodes { child, _ in child.removeFromParentNode() }
                return
            }

            let xs = samples.map(\.x)
            let ys = samples.map(\.y)
            let minX = xs.min()! - 2
            let maxX = xs.max()! + 2
            let minY = ys.min()! - 2
            let maxY = ys.max()! + 2
            let span = max(8, max(maxX - minX, maxY - minY))
            let cx = (minX + maxX) / 2
            let cy = (minY + maxY) / 2

            guard let image = ARFloorHeatmapRenderer.makeTexture(
                samples: samples,
                centerX: cx,
                centerY: cy,
                spanMeters: span,
                opacity: settings.heatmapOpacity
            ) else { return }

            heatNode.enumerateChildNodes { child, _ in child.removeFromParentNode() }

            let plane = SCNPlane(width: CGFloat(span), height: CGFloat(span))
            let mat = SCNMaterial()
            mat.diffuse.contents = image
            mat.isDoubleSided = true
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            mat.blendMode = .alpha
            plane.materials = [mat]

            let node = SCNNode(geometry: plane)
            node.name = "plane"
            // SCNPlane liegt in XY; auf XZ (Boden) drehen
            node.eulerAngles.x = -.pi / 2
            if let world = engine.visualTracker.worldPosition(east: cx, north: cy) {
                node.position = SCNVector3(world.x, world.y + 0.02, world.z)
            }
            heatNode.addChildNode(node)
        }

        @MainActor
        private func updatePath(engine: BLESearchEngine) {
            guard let pathNode else { return }
            pathNode.isHidden = !settings.showPath
            guard settings.showPath else {
                clearPathNodes(in: pathNode)
                return
            }

            let epoch = engine.visualTracker.sessionEpoch
            let raw: [(x: Double, y: Double)] = {
                let p = engine.pathSnapshot.smoothedPolyline
                if p.count >= 2 { return p }
                return engine.pathSnapshot.points.map { ($0.x, $0.y) }
            }()
            let poly = Self.samplePathByDistance(raw, minSpacing: 0.32)

            // Neuausrichten / erster Aufbau: einmal aufbauen, danach nur anhängen (kein Flackern).
            if epoch != lastPathEpoch || lastPathENU == nil {
                clearPathNodes(in: pathNode)
                lastPathEpoch = epoch
                lastPathENU = nil
                guard poly.count >= 2 else { return }
                for i in 0..<(poly.count - 1) {
                    appendPathSegment(from: poly[i], to: poly[i + 1], engine: engine, into: pathNode)
                }
                if let tip = poly.last {
                    lastPathENU = tip
                    updatePathTip(at: tip, engine: engine, into: pathNode)
                }
                return
            }

            guard let tip = poly.last else { return }
            guard let prev = lastPathENU else {
                lastPathENU = tip
                updatePathTip(at: tip, engine: engine, into: pathNode)
                return
            }
            let step = hypot(tip.x - prev.x, tip.y - prev.y)
            if step >= 0.28 {
                appendPathSegment(from: prev, to: tip, engine: engine, into: pathNode)
                lastPathENU = tip
            }
            // Endpunkt nur verschieben — Segment-Geometrie bleibt stehen.
            updatePathTip(at: tip, engine: engine, into: pathNode)
        }

        @MainActor
        private func clearPathNodes(in pathNode: SCNNode) {
            pathNode.enumerateChildNodes { child, _ in child.removeFromParentNode() }
            pathTipNode = nil
            lastPathENU = nil
            lastPathEpoch = -1
        }

        @MainActor
        private func appendPathSegment(
            from aENU: (x: Double, y: Double),
            to bENU: (x: Double, y: Double),
            engine: BLESearchEngine,
            into pathNode: SCNNode
        ) {
            guard let aw = engine.visualTracker.worldPosition(east: aENU.x, north: aENU.y),
                  let bw = engine.visualTracker.worldPosition(east: bENU.x, north: bENU.y) else { return }
            let a = SCNVector3(aw.x, aw.y + 0.05, aw.z)
            let b = SCNVector3(bw.x, bw.y + 0.05, bw.z)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let dz = b.z - a.z
            let length = CGFloat(sqrt(dx * dx + dy * dy + dz * dz))
            guard length > 0.02 else { return }

            let mid = SCNVector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
            let accent = UIColor(Theme.accent)
            let underlay = UIColor.black.withAlphaComponent(0.55)
            let core = accent.withAlphaComponent(0.95)
            let up = SCNVector3(0, 1, 0)

            func segment(radius: CGFloat, color: UIColor) -> SCNNode {
                let cyl = SCNCylinder(radius: radius, height: length)
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.lightingModel = .constant
                mat.writesToDepthBuffer = false
                cyl.materials = [mat]
                let node = SCNNode(geometry: cyl)
                node.position = mid
                node.look(at: b, up: up, localFront: SCNVector3(0, 1, 0))
                return node
            }

            pathNode.addChildNode(segment(radius: 0.028, color: underlay))
            pathNode.addChildNode(segment(radius: 0.018, color: core))
        }

        @MainActor
        private func updatePathTip(
            at enu: (x: Double, y: Double),
            engine: BLESearchEngine,
            into pathNode: SCNNode
        ) {
            guard let w = engine.visualTracker.worldPosition(east: enu.x, north: enu.y) else { return }
            let pos = SCNVector3(w.x, w.y + 0.05, w.z)
            if let tip = pathTipNode {
                tip.position = pos
                return
            }
            let sphere = SCNSphere(radius: 0.028)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(Theme.accent)
            mat.lightingModel = .constant
            sphere.materials = [mat]
            let tip = SCNNode(geometry: sphere)
            tip.name = "arPathTip"
            tip.position = pos
            pathNode.addChildNode(tip)
            pathTipNode = tip
        }

        /// Abstandsbasiert ausdünnen — frühere Punkte bleiben stabil (kein Neu-Sampling).
        private static func samplePathByDistance(
            _ pts: [(x: Double, y: Double)],
            minSpacing: Double
        ) -> [(x: Double, y: Double)] {
            guard let first = pts.first else { return [] }
            var out: [(x: Double, y: Double)] = [first]
            for p in pts.dropFirst() {
                guard let last = out.last else { continue }
                if hypot(p.x - last.x, p.y - last.y) >= minSpacing {
                    out.append(p)
                }
            }
            if let last = pts.last, let tip = out.last,
               hypot(last.x - tip.x, last.y - tip.y) > 0.05 {
                out.append(last)
            }
            return out
        }

        @MainActor
        private func updateBestZone(engine: BLESearchEngine) {
            guard let bestNode else { return }
            bestNode.isHidden = !settings.showBestZone
            bestNode.enumerateChildNodes { child, _ in child.removeFromParentNode() }
            guard settings.showBestZone, let zone = engine.arBestZone else { return }
            guard let world = engine.visualTracker.worldPosition(east: zone.x, north: zone.y) else { return }

            let ring = SCNTube(innerRadius: 0.28, outerRadius: 0.34, height: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(Theme.accent).withAlphaComponent(0.85)
            mat.lightingModel = .constant
            ring.materials = [mat]
            let ringNode = SCNNode(geometry: ring)
            ringNode.position = SCNVector3(world.x, world.y + 0.05, world.z)
            bestNode.addChildNode(ringNode)

            let cross = SCNNode()
            let arm: CGFloat = 0.22
            for angle in [0.0, Double.pi / 2] {
                let box = SCNBox(width: angle == 0 ? arm * 2 : 0.025, height: 0.015, length: angle == 0 ? 0.025 : arm * 2, chamferRadius: 0)
                let m = SCNMaterial()
                m.diffuse.contents = UIColor.white.withAlphaComponent(0.8)
                m.lightingModel = .constant
                box.materials = [m]
                let n = SCNNode(geometry: box)
                cross.addChildNode(n)
            }
            cross.position = SCNVector3(world.x, world.y + 0.06, world.z)
            bestNode.addChildNode(cross)

            let label = SCNText(string: "Bester Messbereich", extrusionDepth: 0.01)
            label.font = UIFont.systemFont(ofSize: 0.12, weight: .semibold)
            label.flatness = 0.2
            let lm = SCNMaterial()
            lm.diffuse.contents = UIColor.white.withAlphaComponent(0.9)
            lm.lightingModel = .constant
            label.materials = [lm]
            let labelNode = SCNNode(geometry: label)
            labelNode.scale = SCNVector3(0.35, 0.35, 0.35)
            let (minB, maxB) = labelNode.boundingBox
            labelNode.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, minB.y, 0)
            labelNode.position = SCNVector3(world.x, world.y + 0.28, world.z)
            labelNode.constraints = [SCNBillboardConstraint()]
            bestNode.addChildNode(labelNode)
        }
    }
}

// MARK: - Circular minimap

struct ARMinimapView: View {
    let pathSnapshot: BLESearchPathSnapshot
    let breadcrumbs: [BLEBreadcrumb]
    let bestZone: ARBestZone?
    let headingDegrees: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.72))
            Circle()
                .stroke(Theme.border, lineWidth: 1)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let span = max(pathSnapshot.viewport.spanMeters, 12)
                let cx = pathSnapshot.current?.x ?? pathSnapshot.viewport.centerX
                let cy = pathSnapshot.current?.y ?? pathSnapshot.viewport.centerY
                let heading = headingDegrees ?? 0
                // Heading-up: Welt drehen, Nutzer bleibt mittig
                let rot = -heading * .pi / 180

                func project(_ x: Double, _ y: Double) -> CGPoint {
                    let dx = x - cx
                    let dy = y - cy
                    let rx = dx * cos(rot) - dy * sin(rot)
                    let ry = dx * sin(rot) + dy * cos(rot)
                    let px = center.x + CGFloat(rx / span) * size.width
                    // Screen Y down; north should go toward top of heading-up map
                    let py = center.y - CGFloat(ry / span) * size.height
                    return CGPoint(x: px, y: py)
                }

                // Soft heatmap dots (frozen RSSI colors)
                for crumb in breadcrumbs.suffix(80) {
                    let p = project(crumb.x, crumb.y)
                    let color = ARSignalColorScale.swiftUIColor(forRssi: crumb.rssi).opacity(0.45)
                    let r: CGFloat = 5
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                        with: .color(color)
                    )
                }

                let poly = pathSnapshot.smoothedPolyline.count >= 2
                    ? pathSnapshot.smoothedPolyline
                    : pathSnapshot.points.map { ($0.x, $0.y) }
                if poly.count >= 2 {
                    var path = Path()
                    for (i, pt) in poly.enumerated() {
                        let p = project(pt.x, pt.y)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(
                        path,
                        with: .color(Color.black.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                    )
                    context.stroke(
                        path,
                        with: .color(Theme.accent.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
                    )
                }

                if let zone = bestZone {
                    let p = project(zone.x, zone.y)
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
                    context.stroke(ring, with: .color(Theme.accent), lineWidth: 1.5)
                }

                // User puck + heading wedge (always center; wedge points up)
                var wedge = Path()
                wedge.move(to: center)
                wedge.addLine(to: CGPoint(x: center.x - 7, y: center.y - 16))
                wedge.addLine(to: CGPoint(x: center.x + 7, y: center.y - 16))
                wedge.closeSubpath()
                context.fill(wedge, with: .color(Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.35)))
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                    with: .color(Color(red: 0.04, green: 0.52, blue: 1.0))
                )
            }
            .clipShape(Circle())
        }
    }
}
