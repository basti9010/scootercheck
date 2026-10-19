import Foundation
import Combine
import UIKit
import UserNotifications
import AudioToolbox
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Config

enum BLEWatchConfig {
    static let maxActiveTargets = 10
    /// Zeit ohne Sighting → signalLost / notSeen.
    static let lostAfterSeconds: TimeInterval = 45
    /// Fingerprint-Mindestscore für sichere Watch-Notification.
    static let secureMatchScore = 70
    /// Darunter: „mögliches Zielgerät“ (nur wenn Score ≥ diesem Wert).
    static let possibleMatchScore = 45
    static let processingThrottle: TimeInterval = 0.45
}

enum BLERadarConfig {
    static let deviceCooldownSeconds: TimeInterval = 45
    static let globalMinInterval: TimeInterval = 2.5
    static let minHitsForAlarm = 3
    static let hitWindowSeconds: TimeInterval = 4.0
    static let highlightSeconds: TimeInterval = 90
}

// MARK: - Watch target

enum BLEWatchStatus: String, Codable, Sendable {
    case watching
    case seen
    case notSeen
    case signalLost
    case foundAgain
    case paused

    var label: String {
        switch self {
        case .watching: return "Wird beobachtet"
        case .seen: return "Gerade erkannt"
        case .notSeen: return "Nicht erkannt"
        case .signalLost: return "Signal verloren"
        case .foundAgain: return "Wieder erkannt"
        case .paused: return "Pausiert"
        }
    }
}

struct BLEWatchTarget: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var deviceId: UUID
    var deviceName: String
    var isKnownScooter: Bool
    var fingerprint: BLEDeviceFingerprint?
    var enabled: Bool
    var notifyOnSeen: Bool
    var soundEnabled: Bool
    var hapticsEnabled: Bool
    /// Minimum signal class raw value (veryWeak…veryStrong); lost never notifies.
    var minimumSignalClass: String
    var cooldownSeconds: Int
    var lastSeenAt: Date?
    var lastNotificationAt: Date?
    var lastRSSI: Int?
    var lastSmoothedRssi: Double?
    var status: String
    var createdAt: Date
    var lostSince: Date?
    /// Timeline of watcher-relevant events (session-local, capped).
    var events: [BLESearchEvent]

    init(
        id: UUID = UUID(),
        deviceId: UUID,
        deviceName: String,
        isKnownScooter: Bool = false,
        fingerprint: BLEDeviceFingerprint? = nil,
        enabled: Bool = true,
        notifyOnSeen: Bool = true,
        soundEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        minimumSignalClass: BLESignalClass = .weak,
        cooldownSeconds: Int = 900,
        lastSeenAt: Date? = nil,
        lastNotificationAt: Date? = nil,
        lastRSSI: Int? = nil,
        lastSmoothedRssi: Double? = nil,
        status: BLEWatchStatus = .watching,
        createdAt: Date = Date(),
        lostSince: Date? = nil,
        events: [BLESearchEvent] = []
    ) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.isKnownScooter = isKnownScooter
        self.fingerprint = fingerprint
        self.enabled = enabled
        self.notifyOnSeen = notifyOnSeen
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.minimumSignalClass = minimumSignalClass.rawValue
        self.cooldownSeconds = cooldownSeconds
        self.lastSeenAt = lastSeenAt
        self.lastNotificationAt = lastNotificationAt
        self.lastRSSI = lastRSSI
        self.lastSmoothedRssi = lastSmoothedRssi
        self.status = status.rawValue
        self.createdAt = createdAt
        self.lostSince = lostSince
        self.events = events
    }

    var watchStatus: BLEWatchStatus {
        get { BLEWatchStatus(rawValue: status) ?? .watching }
        set { status = newValue.rawValue }
    }

    var minClass: BLESignalClass {
        get { BLESignalClass(rawValue: minimumSignalClass) ?? .weak }
        set { minimumSignalClass = newValue.rawValue }
    }

    static let cooldownOptions: [(label: String, seconds: Int)] = [
        ("1 Minute", 60),
        ("5 Minuten", 300),
        ("15 Minuten", 900),
        ("30 Minuten", 1_800),
        ("60 Minuten", 3_600)
    ]

    static let signalFilterOptions: [BLESignalClass] = [
        .veryWeak, .weak, .medium, .strong
    ]

    /// „jedes erkannte Signal“ → veryWeak als Untergrenze (lost ausgeschlossen).
    var filterLabel: String {
        switch minClass {
        case .veryWeak, .lost: return "jedes erkannte Signal"
        case .weak: return "mindestens schwach"
        case .medium: return "mindestens mittel"
        case .strong, .veryStrong: return "mindestens stark"
        }
    }
}

// MARK: - Watch store

@MainActor
final class BLEWatchStore: ObservableObject {
    static let shared = BLEWatchStore()
    private let key = "bleWatchTargets.v1"
    @Published private(set) var targets: [BLEWatchTarget] = []

    private init() { load() }

    var activeCount: Int { targets.filter(\.enabled).count }

    func target(forDeviceId id: UUID) -> BLEWatchTarget? {
        targets.first { $0.deviceId == id }
    }

    func upsert(_ target: BLEWatchTarget) {
        if let i = targets.firstIndex(where: { $0.id == target.id }) {
            targets[i] = target
        } else if let i = targets.firstIndex(where: { $0.deviceId == target.deviceId }) {
            var t = target
            t.id = targets[i].id
            targets[i] = t
        } else {
            guard targets.filter(\.enabled).count < BLEWatchConfig.maxActiveTargets || !target.enabled else {
                return
            }
            targets.insert(target, at: 0)
        }
        persist()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let i = targets.firstIndex(where: { $0.id == id }) else { return }
        if enabled, targets.filter(\.enabled).count >= BLEWatchConfig.maxActiveTargets, !targets[i].enabled {
            return
        }
        targets[i].enabled = enabled
        targets[i].watchStatus = enabled ? .watching : .paused
        persist()
    }

    func remove(id: UUID) {
        targets.removeAll { $0.id == id }
        persist()
    }

    func update(_ mutate: (inout BLEWatchTarget) -> Void, id: UUID) {
        guard let i = targets.firstIndex(where: { $0.id == id }) else { return }
        mutate(&targets[i])
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BLEWatchTarget].self, from: data) else {
            targets = []
            return
        }
        targets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Notifications

@MainActor
final class BLENotificationService: ObservableObject {
    static let shared = BLENotificationService()
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private init() {
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }

    func requestAuthorization() async -> Bool {
        do {
            let ok = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return ok
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    func post(
        id: String,
        title: String,
        body: String,
        userInfo: [AnyHashable: Any],
        sound: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        content.userInfo = userInfo
        let req = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Match result

enum BLEWatchMatchKind: Equatable {
    case exactId
    case secureFingerprint
    case possibleFingerprint
}

struct BLEWatchMatch: Equatable {
    var target: BLEWatchTarget
    var kind: BLEWatchMatchKind
    var score: Int
}

enum BLEWatchMatcher {
    static func match(device: ScannedDevice, targets: [BLEWatchTarget]) -> BLEWatchMatch? {
        let enabled = targets.filter(\.enabled)
        if let exact = enabled.first(where: { $0.deviceId == device.id }) {
            return BLEWatchMatch(target: exact, kind: .exactId, score: 100)
        }
        let fp = BLEDeviceFingerprint.from(device: device)
        var best: BLEWatchMatch?
        for t in enabled {
            guard let baseline = t.fingerprint else { continue }
            let result = BLEFingerprintService.compare(baseline, fp)
            // Name allein reicht nie — Score kommt aus Mfg/UUID/Struktur.
            if result.score >= BLEWatchConfig.secureMatchScore {
                let m = BLEWatchMatch(target: t, kind: .secureFingerprint, score: result.score)
                if best == nil || m.score > (best?.score ?? 0) { best = m }
            } else if result.score >= BLEWatchConfig.possibleMatchScore {
                let m = BLEWatchMatch(target: t, kind: .possibleFingerprint, score: result.score)
                if best == nil || (best?.kind == .possibleFingerprint && m.score > (best?.score ?? 0)) {
                    if best?.kind != .secureFingerprint { best = m }
                }
            }
        }
        return best
    }
}

// MARK: - Watch service

@MainActor
final class BLEWatchService: ObservableObject {
    static let shared = BLEWatchService()

    @Published private(set) var lastBanner: String?
    private let store = BLEWatchStore.shared
    private var processors: [UUID: BLESignalProcessor] = [:]
    private var bleCancellable: AnyCancellable?
    private var tickTimer: Timer?
    private var lastProcessAt = Date.distantPast
    private weak var ble: BleClient?
    private var isForeground = true

    private init() {}

    var hasActiveWatchers: Bool { store.activeCount > 0 }

    func attach(ble: BleClient) {
        self.ble = ble
        bleCancellable?.cancel()
        bleCancellable = ble.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.process(devices: devices)
            }
        if tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tickLost()
                    self?.updateBackgroundScanIfNeeded()
                }
            }
        }
        updateBackgroundScanIfNeeded()
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        updateBackgroundScanIfNeeded()
    }

    func updateBackgroundScanIfNeeded() {
        guard let ble else { return }
        if hasActiveWatchers {
            ble.ensureWatchScanRunning()
        } else if ble.phase == .scanning, ble.watchScanOnly {
            ble.stopWatchScanIfIdle()
        }
    }

    func enableWatcher(
        for device: ScannedDevice,
        isKnownScooter: Bool,
        notify: Bool = true,
        sound: Bool = true,
        haptics: Bool = true,
        minClass: BLESignalClass = .weak,
        cooldown: Int = 900
    ) {
        var target = store.target(forDeviceId: device.id) ?? BLEWatchTarget(
            deviceId: device.id,
            deviceName: device.bleListDisplayName,
            isKnownScooter: isKnownScooter,
            fingerprint: BLEDeviceFingerprint.from(device: device)
        )
        target.deviceName = device.bleListDisplayName
        target.isKnownScooter = isKnownScooter
        target.fingerprint = BLEDeviceFingerprint.from(device: device)
        target.enabled = true
        target.notifyOnSeen = notify
        target.soundEnabled = sound
        target.hapticsEnabled = haptics
        target.minClass = minClass
        target.cooldownSeconds = cooldown
        target.watchStatus = .watching
        appendEvent(&target, type: .searchStarted, title: "Wächter aktiviert")
        // reuse searchStarted as watcherEnabled surrogate in timeline types — add custom via metadata
        target.events[target.events.count - 1].metadata = ["kind": "watcherEnabled"]
        store.upsert(target)
        updateBackgroundScanIfNeeded()
        Task { _ = await BLENotificationService.shared.requestAuthorization() }
    }

    func disableWatcher(deviceId: UUID) {
        guard var t = store.target(forDeviceId: deviceId) else { return }
        t.enabled = false
        t.watchStatus = .paused
        appendEvent(&t, type: .searchEnded, title: "Wächter pausiert")
        t.events[t.events.count - 1].metadata = ["kind": "watcherDisabled"]
        store.upsert(t)
        updateBackgroundScanIfNeeded()
    }

    private func process(devices: [ScannedDevice]) {
        guard hasActiveWatchers else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProcessAt) >= BLEWatchConfig.processingThrottle else { return }
        lastProcessAt = now

        for device in devices {
            guard let match = BLEWatchMatcher.match(device: device, targets: store.targets) else { continue }
            handleSighting(match: match, device: device, at: now)
        }
    }

    private func handleSighting(match: BLEWatchMatch, device: ScannedDevice, at now: Date) {
        var target = match.target
        var proc = processors[target.id] ?? BLESignalProcessor()
        let smooth = proc.ingest(rawRssi: device.rssi, at: now)
        processors[target.id] = proc
        let signalClass = BLESignalClass.from(smoothedRssi: smooth, lost: false)

        let wasLost = target.lostSince != nil
            || target.watchStatus == .signalLost
            || target.watchStatus == .notSeen
        let lostDuration = target.lostSince.map { now.timeIntervalSince($0) }

        target.lastSeenAt = now
        target.lastRSSI = device.rssi
        target.lastSmoothedRssi = smooth
        target.deviceName = device.bleListDisplayName
        if target.fingerprint == nil {
            target.fingerprint = BLEDeviceFingerprint.from(device: device)
        }
        target.lostSince = nil

        if wasLost {
            target.watchStatus = .foundAgain
            let mins = Int((lostDuration ?? 0) / 60)
            appendEvent(
                &target,
                type: .signalRefound,
                title: "Wieder erkannt",
                description: mins > 0 ? "Nach \(mins) Minuten wieder empfangen." : "Signal wieder empfangen.",
                rssi: smooth
            )
        } else {
            target.watchStatus = .seen
            appendEvent(&target, type: .deviceFirstSeen, title: "Gerät erkannt", rssi: smooth, minInterval: 30)
        }

        let meetsThreshold = classMeets(signalClass, minimum: target.minClass)
        let cooldownOK = target.lastNotificationAt.map {
            now.timeIntervalSince($0) >= TimeInterval(target.cooldownSeconds)
        } ?? true
        let shouldNotify = target.notifyOnSeen
            && meetsThreshold
            && (cooldownOK || wasLost)
            && match.kind != .possibleFingerprint // unsicher → kein „sicher“-Alarm

        if shouldNotify {
            sendNotification(for: target, signalClass: signalClass, possible: false)
            target.lastNotificationAt = now
            appendEvent(&target, type: .searchStarted, title: "Benachrichtigung gesendet", minInterval: 5)
            target.events[target.events.count - 1].metadata = ["kind": "notificationSent"]
            if isForeground {
                lastBanner = target.isKnownScooter
                    ? "Bekannter Scooter erkannt: \(target.deviceName)"
                    : "Beobachtetes BLE-Gerät erkannt: \(target.deviceName)"
                if target.hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                if target.soundEnabled {
                    AudioServicesPlaySystemSound(1057)
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.lastBanner?.contains(target.deviceName) == true {
                        self.lastBanner = nil
                    }
                }
            }
        } else if match.kind == .possibleFingerprint, meetsThreshold, cooldownOK, target.notifyOnSeen {
            // Unsichere Treffer: nur Banner im Vordergrund, keine „sichere“ Notification-Flut
            if isForeground {
                lastBanner = "Mögliches Zielgerät erkannt: \(target.deviceName)"
            }
        }

        store.upsert(target)
    }

    private func tickLost() {
        let now = Date()
        for t in store.targets where t.enabled {
            guard let last = t.lastSeenAt else {
                if t.watchStatus != .notSeen && t.watchStatus != .paused {
                    var u = t
                    u.watchStatus = .notSeen
                    store.upsert(u)
                }
                continue
            }
            let since = now.timeIntervalSince(last)
            if since >= BLEWatchConfig.lostAfterSeconds {
                var u = t
                if u.lostSince == nil {
                    u.lostSince = last
                    appendEvent(&u, type: .signalLost, title: "Signal verloren")
                }
                u.watchStatus = .signalLost
                store.upsert(u)
            }
        }
    }

    private func sendNotification(for target: BLEWatchTarget, signalClass: BLESignalClass, possible: Bool) {
        let title: String = {
            if possible { return "Mögliches Zielgerät erkannt" }
            return target.isKnownScooter ? "Bekannter Scooter erkannt" : "Beobachtetes BLE-Gerät erkannt"
        }()
        let body = "\(target.deviceName) wurde in Bluetooth-Reichweite erkannt. Signal: \(signalClass.label)."
        BLENotificationService.shared.post(
            id: "watch-\(target.id.uuidString)-\(Int(Date().timeIntervalSince1970))",
            title: title,
            body: body,
            userInfo: [
                "type": "bleWatch",
                "targetId": target.id.uuidString,
                "deviceId": target.deviceId.uuidString
            ],
            sound: target.soundEnabled
        )
    }

    private func classMeets(_ value: BLESignalClass, minimum: BLESignalClass) -> Bool {
        rank(value) >= rank(minimum) && value != .lost
    }

    private func rank(_ c: BLESignalClass) -> Int {
        switch c {
        case .veryStrong: return 5
        case .strong: return 4
        case .medium: return 3
        case .weak: return 2
        case .veryWeak: return 1
        case .lost: return 0
        }
    }

    private func appendEvent(
        _ target: inout BLEWatchTarget,
        type: BLESearchEventType,
        title: String,
        description: String? = nil,
        rssi: Double? = nil,
        minInterval: TimeInterval = 8
    ) {
        if let last = target.events.last,
           last.type == type,
           Date().timeIntervalSince(last.timestamp) < minInterval {
            return
        }
        target.events.append(BLESearchEvent(
            type: type,
            title: title,
            description: description,
            rssi: rssi
        ))
        if target.events.count > 80 {
            target.events.removeFirst(target.events.count - 80)
        }
    }
}

// MARK: - Radar

enum BLEScooterConfidence: String, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "niedrig"
        case .medium: return "mittel"
        case .high: return "hoch"
        }
    }
}

@MainActor
enum BLEScooterClassifier {
    /// Nutzt bestehende Heuristik — Name allein reicht nicht für medium+.
    static func confidence(for device: ScannedDevice) -> BLEScooterConfidence {
        let hasService = !device.serviceUUIDs.isEmpty && device.looksLikeScooter
        let hasMfg = device.manufacturerDataHex != nil
        let hasModel = device.modelLabel != nil
        let nameLikely = BleClient.isLikelyScooterName(
            device.cryptoName.isEmpty ? device.name : device.cryptoName
        )
        // Starke Indikatoren
        if hasModel && (hasService || nameLikely) { return .high }
        if hasService && (hasMfg || nameLikely) { return .high }
        if device.looksLikeScooter && (hasService || hasModel || (nameLikely && hasMfg)) {
            return .medium
        }
        if device.looksLikeScooter && nameLikely && !hasService && !hasMfg && !hasModel {
            return .low // Name-only
        }
        if device.looksLikeScooter { return .low }
        return .low
    }

    static func isRadarEligible(_ device: ScannedDevice) -> Bool {
        // Identifikations-Engine: nur belastbare Scooter-Klassifikation → Radar.
        if let id = BLEIdentificationService.shared.result(for: device.id) {
            return id.radarEligibleScooter
        }
        return confidence(for: device) != .low && device.looksLikeScooter
    }
}

struct BLERadarHit: Identifiable, Equatable {
    var id: UUID
    var deviceName: String
    var signalClass: BLESignalClass
    var confidence: BLEScooterConfidence
    var at: Date
}

@MainActor
final class BLERadarService: ObservableObject {
    static let shared = BLERadarService()

    @Published var isEnabled = false
    @Published var minimumSignalClass: BLESignalClass = .medium
    @Published var soundEnabled = true
    @Published var hapticsEnabled = true
    @Published private(set) var recentHits: [BLERadarHit] = []
    @Published private(set) var highlightDeviceIds: Set<UUID> = []
    @Published private(set) var banner: String?
    @Published private(set) var timelineEvents: [BLESearchEvent] = []

    private var processors: [UUID: BLESignalProcessor] = [:]
    private var hitTimes: [UUID: [Date]] = [:]
    private var lastAlarmAt: [UUID: Date] = [:]
    private var lastGlobalAlarm = Date.distantPast
    private var pendingBundle: [BLERadarHit] = []
    private var bundleFlushTask: Task<Void, Never>?
    private var sessionActive = false
    private var bleCancellable: AnyCancellable?
    private weak var ble: BleClient?

    private init() {}

    func attach(ble: BleClient) {
        self.ble = ble
        bleCancellable?.cancel()
        bleCancellable = ble.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.ingest(devices)
            }
    }

    func startSession(enableRadar: Bool = false) {
        sessionActive = true
        if enableRadar {
            setEnabled(true)
        }
    }

    func endSession() {
        setEnabled(false)
        sessionActive = false
        processors = [:]
        hitTimes = [:]
        recentHits = []
        highlightDeviceIds = []
        banner = nil
        pendingBundle = []
        bundleFlushTask?.cancel()
        BLESearchLiveActivityController.shared.end()
    }

    func setEnabled(_ on: Bool) {
        guard isEnabled != on else { return }
        isEnabled = on
        let event = BLESearchEvent(
            type: on ? .coarseMode : .searchEnded,
            title: on ? "E-Scooter-Radar aktiviert" : "E-Scooter-Radar deaktiviert"
        )
        timelineEvents.append(event)
        if timelineEvents.count > 100 {
            timelineEvents.removeFirst(timelineEvents.count - 100)
        }
        if !on {
            banner = nil
            pendingBundle = []
        } else {
            Task { _ = await BLENotificationService.shared.requestAuthorization() }
        }
    }

    private func ingest(_ devices: [ScannedDevice]) {
        guard isEnabled, sessionActive else { return }
        let now = Date()
        // Highlight expiry
        highlightDeviceIds = Set(recentHits.filter {
            now.timeIntervalSince($0.at) < BLERadarConfig.highlightSeconds
        }.map(\.id))

        var candidates: [(ScannedDevice, BLESignalClass, BLEScooterConfidence)] = []
        for device in devices {
            guard BLEScooterClassifier.isRadarEligible(device) else { continue }
            let conf = BLEScooterClassifier.confidence(for: device)
            guard conf == .medium || conf == .high else { continue }

            var proc = processors[device.id] ?? BLESignalProcessor()
            let smooth = proc.ingest(rawRssi: device.rssi, at: now)
            processors[device.id] = proc
            let cls = BLESignalClass.from(smoothedRssi: smooth, lost: false)
            guard rank(cls) >= rank(minimumSignalClass), cls != .lost else { continue }

            var times = (hitTimes[device.id] ?? []).filter {
                now.timeIntervalSince($0) <= BLERadarConfig.hitWindowSeconds
            }
            times.append(now)
            hitTimes[device.id] = times
            guard times.count >= BLERadarConfig.minHitsForAlarm else { continue }

            let last = lastAlarmAt[device.id]
            let cooldownOK = last.map { now.timeIntervalSince($0) >= BLERadarConfig.deviceCooldownSeconds } ?? true
            guard cooldownOK else { continue }

            candidates.append((device, cls, conf))
        }

        guard !candidates.isEmpty else { return }
        guard now.timeIntervalSince(lastGlobalAlarm) >= BLERadarConfig.globalMinInterval else {
            // queue for bundle
            for c in candidates {
                enqueueHit(c.0, cls: c.1, conf: c.2, at: now)
            }
            return
        }

        if candidates.count > 1 {
            for c in candidates {
                enqueueHit(c.0, cls: c.1, conf: c.2, at: now)
            }
            flushBundle(force: true)
        } else if let c = candidates.first {
            fireSingle(c.0, cls: c.1, conf: c.2, at: now)
        }
    }

    private func enqueueHit(_ device: ScannedDevice, cls: BLESignalClass, conf: BLEScooterConfidence, at now: Date) {
        lastAlarmAt[device.id] = now
        let hit = BLERadarHit(
            id: device.id,
            deviceName: device.modelLabel ?? (device.looksLikeScooter ? "Möglicher E-Scooter" : device.bleListDisplayName),
            signalClass: cls,
            confidence: conf,
            at: now
        )
        pendingBundle.append(hit)
        recentHits.insert(hit, at: 0)
        if recentHits.count > 30 { recentHits = Array(recentHits.prefix(30)) }
        highlightDeviceIds.insert(device.id)
        bundleFlushTask?.cancel()
        bundleFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            flushBundle(force: false)
        }
    }

    private func fireSingle(_ device: ScannedDevice, cls: BLESignalClass, conf: BLEScooterConfidence, at now: Date) {
        lastAlarmAt[device.id] = now
        lastGlobalAlarm = now
        let name = device.modelLabel ?? "Möglicher E-Scooter"
        let hit = BLERadarHit(id: device.id, deviceName: name, signalClass: cls, confidence: conf, at: now)
        recentHits.insert(hit, at: 0)
        highlightDeviceIds.insert(device.id)
        timelineEvents.append(BLESearchEvent(
            type: .deviceFirstSeen,
            title: "E-Scooter erkannt",
            description: "\(name) · Signal: \(cls.label)",
            rssi: Double(device.rssi),
            metadata: ["kind": "scooterDetected"]
        ))
        presentAlarm(title: "E-Scooter erkannt", body: "\(name) · Signal: \(cls.label)")
        BLENotificationService.shared.post(
            id: "radar-\(device.id.uuidString)-\(Int(now.timeIntervalSince1970))",
            title: "E-Scooter erkannt",
            body: "\(name) wurde mit Signal „\(cls.label)“ erkannt.",
            userInfo: [
                "type": "bleRadar",
                "deviceId": device.id.uuidString
            ],
            sound: soundEnabled
        )
    }

    private func flushBundle(force: Bool) {
        guard !pendingBundle.isEmpty else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastGlobalAlarm) < BLERadarConfig.globalMinInterval {
            return
        }
        let bundle = pendingBundle
        pendingBundle = []
        lastGlobalAlarm = now
        let strong = bundle.filter { rank($0.signalClass) >= rank(.strong) }.count
        let title = "\(bundle.count) E-Scooter erkannt"
        var body = bundle.map(\.deviceName).prefix(3).joined(separator: ", ")
        if strong > 0 { body += " · \(strong) mit starkem Signal" }
        timelineEvents.append(BLESearchEvent(
            type: .deviceFirstSeen,
            title: title,
            description: body,
            metadata: ["kind": "scooterDetected", "count": "\(bundle.count)"]
        ))
        presentAlarm(title: title, body: body)
        BLENotificationService.shared.post(
            id: "radar-bundle-\(Int(now.timeIntervalSince1970))",
            title: title,
            body: body,
            userInfo: ["type": "bleRadar", "bundled": true],
            sound: soundEnabled
        )
    }

    private func presentAlarm(title: String, body: String) {
        banner = "\(title)\n\(body)"
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        if soundEnabled {
            AudioServicesPlaySystemSound(1007)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self.banner == "\(title)\n\(body)" { self.banner = nil }
        }
    }

    private func rank(_ c: BLESignalClass) -> Int {
        switch c {
        case .veryStrong: return 5
        case .strong: return 4
        case .medium: return 3
        case .weak: return 2
        case .veryWeak: return 1
        case .lost: return 0
        }
    }
}

// MARK: - Live Activity bridge
// Volle Lock-Screen-/Dynamic-Island-UI benötigt ein Widget-Extension-Target.
// Controller hält Session-State und ist bereit für ActivityKit-Anbindung.

@MainActor
final class BLESearchLiveActivityController: ObservableObject {
    static let shared = BLESearchLiveActivityController()

    @Published private(set) var isActive = false
    @Published private(set) var deviceName: String = ""
    @Published private(set) var statusText: String = ""
    @Published private(set) var signalLabel: String = ""
    @Published private(set) var lastSeenText: String = ""

    func start(deviceName: String) {
        self.deviceName = deviceName
        statusText = "Signal aktiv"
        signalLabel = "—"
        lastSeenText = "gerade eben"
        isActive = true
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            // Widget-Extension registriert Attributes; ohne Extension kein sichtbares UI.
            _ = ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
    }

    func update(status: String, signal: String, lastSeen: String, deviceName: String? = nil) {
        guard isActive else { return }
        statusText = status
        signalLabel = signal
        lastSeenText = lastSeen
        if let deviceName { self.deviceName = deviceName }
    }

    func end() {
        isActive = false
        deviceName = ""
        statusText = ""
        signalLabel = ""
        lastSeenText = ""
    }
}

// MARK: - Deep link routing

enum BLEDeepLink: Equatable {
    case watch(targetId: UUID)
    case radar(deviceId: UUID?)
    case find

    static func parse(_ url: URL) -> BLEDeepLink? {
        // scootercheck://watch/<uuid> | scootercheck://radar(/<uuid>) | scootercheck://find
        guard url.scheme == "scootercheck" else { return nil }
        let host = url.host ?? ""
        let pathId = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
        switch host {
        case "watch":
            if let id = pathId ?? UUID(uuidString: url.lastPathComponent) {
                return .watch(targetId: id)
            }
        case "radar":
            return .radar(deviceId: pathId)
        case "find":
            return .find
        default:
            break
        }
        return nil
    }
}
