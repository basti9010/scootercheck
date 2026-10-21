import Foundation

/// Einzelne FAQ-Antwortsegmente für lesbare Darstellung (Fließtext, Aufzählung, Hinweisbox).
enum FAQSegment: Hashable, Sendable {
    case paragraph(String)
    case bullets([String])
    case callout(String)
}

struct FAQItem: Identifiable, Hashable, Sendable {
    let id: String
    let question: String
    let segments: [FAQSegment]
    let keywords: [String]

    init(id: String, question: String, segments: [FAQSegment], keywords: [String] = []) {
        self.id = id
        self.question = question
        self.segments = segments
        self.keywords = keywords
    }

    /// Flacher Suchtext über Frage, Stichworte und Segmente.
    var searchableText: String {
        var parts = [question] + keywords
        for segment in segments {
            switch segment {
            case .paragraph(let t), .callout(let t):
                parts.append(t)
            case .bullets(let items):
                parts.append(contentsOf: items)
            }
        }
        return parts.joined(separator: " ").lowercased()
    }
}

struct FAQCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let items: [FAQItem]
}

/// Statische Wissensbasis — spiegelt den in der App implementierten Funktionsumfang wider.
enum FAQCatalog {
    static let categories: [FAQCategory] = [
        verstehen,
        grundlagen,
        finden,
        tuning,
        auslesen,
        register,
        bewertungen,
        grenzen,
        haeufige,
    ]

    static func filtered(query: String) -> [FAQCategory] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return categories }
        return categories.compactMap { category in
            let items = category.items.filter { $0.searchableText.contains(q) }
            guard !items.isEmpty else { return nil }
            return FAQCategory(
                id: category.id,
                title: category.title,
                symbolName: category.symbolName,
                items: items
            )
        }
    }
}

// MARK: - 1. ScooterCheck verstehen

private extension FAQCatalog {
    static let verstehen = FAQCategory(
        id: "verstehen",
        title: "ScooterCheck verstehen",
        symbolName: "info.circle",
        items: [
            FAQItem(
                id: "was-ist",
                question: "Was ist ScooterCheck?",
                segments: [
                    .paragraph("ScooterCheck ist eine Diagnose-App für unterstützte E-Scooter."),
                    .paragraph("Die App verbindet sich über Bluetooth mit dem Scooter und liest technisch verfügbare Informationen aus verschiedenen Steuergeräten aus. Die gefundenen Daten können miteinander verglichen und auf technische Auffälligkeiten geprüft werden."),
                    .paragraph("ScooterCheck verändert keine Einstellungen am Scooter und führt kein Tuning durch. Die App arbeitet grundsätzlich lesend:"),
                    .bullets([
                        "Lesen",
                        "Vergleichen",
                        "Bewerten",
                        "Dokumentieren (Prüfbericht als PDF und JSON)",
                    ]),
                    .paragraph("Unterstützte Modellfamilien (Stand App): Ninebot Max G2/G30/G3 (MAX3), ZT3 Pro, F2/F3 Pro, E-/D-Serie sowie Xiaomi Classic (M365/Pro 2/Essential/1S) und Xiaomi 3/4 — jeweils mit Marktprofilen (z. B. DE 20 km/h, EU 25 km/h, bei Max G3 zusätzlich US)."),
                ],
                keywords: ["diagnose", "bluetooth", "lesen", "pdf", "json", "ninebot", "xiaomi"]
            ),
            FAQItem(
                id: "veraendert",
                question: "Verändert ScooterCheck meinen Scooter?",
                segments: [
                    .paragraph("Nein. ScooterCheck ist als Read-Only-Diagnose ausgelegt."),
                    .paragraph("Die App soll keine Geschwindigkeitslimits ändern, keine Region ändern, keine Firmware flashen und keine Tuningparameter setzen."),
                    .paragraph("Eine Ausnahme ist das optionale Identifizieren (Piepton / Find-Funktion) bei unterstützten Ninebot-Geräten — das dient nur dem Auffinden des Scooters, nicht dem Ändern von Limits."),
                ],
                keywords: ["read-only", "schreiben", "flash", "limit", "sicher"]
            ),
            FAQItem(
                id: "ablauf",
                question: "Wie läuft eine Prüfung ab?",
                segments: [
                    .paragraph("Typischer Ablauf in der App:"),
                    .bullets([
                        "Geräte suchen und Scooter auswählen",
                        "Soll-Profil bestätigen (Familie und Markt, z. B. Max G3 DE)",
                        "Auslesen der verfügbaren Register und Boards",
                        "Automatische Bewertung und Evidenzmatrix",
                        "Optional: Vergleichstest (ohne/mit Geheimkombination + Persistenz nach Neustart)",
                        "Prüfbericht speichern und teilen",
                    ]),
                    .paragraph("Gespeicherte Prüfungen erscheinen unter „Prüfungen“ in der Übersicht und können später erneut geöffnet oder geteilt werden."),
                ],
                keywords: ["ablauf", "prüfung", "profil", "übersicht", "bericht"]
            ),
            FAQItem(
                id: "menue",
                question: "Was finde ich im linken Menü?",
                segments: [
                    .paragraph("Über das Seitenmenü erreichst du die Hauptbereiche der App:"),
                    .bullets([
                        "E-Scooter auslesen — Diagnose und Prüfbericht",
                        "Prüfungen — gespeicherte Berichte (Aktiv / Archiv)",
                        "E-Scooter finden — Radar, Wächter, Signal-Finder",
                        "FAQ & Wissensbasis",
                        "Datenschutz",
                        "Einstellungen — globale App-Darstellung (z. B. Schriftgröße)",
                    ]),
                    .callout("Feature-Einstellungen wie Radar oder Radarkarte bleiben am jeweiligen Zahnrad vor Ort. „Einstellungen“ im Menü gilt für die ganze App."),
                ],
                keywords: ["menü", "navigation", "einstellungen", "schriftgröße", "drawer", "seitenmenü"]
            ),
        ]
    )
}

// MARK: - 2. Grundlagen E-Scooter

private extension FAQCatalog {
    static let grundlagen = FAQCategory(
        id: "grundlagen",
        title: "Grundlagen E-Scooter",
        symbolName: "bolt.circle",
        items: [
            FAQItem(
                id: "aufbau",
                question: "Wie funktioniert ein moderner E-Scooter technisch?",
                segments: [
                    .paragraph("Ein moderner E-Scooter besteht aus mehreren elektronischen Komponenten (Boards), die über ein internes Protokoll miteinander kommunizieren. ScooterCheck liest – soweit das Modell es erlaubt – Daten von diesen Boards aus und vergleicht sie."),
                    .paragraph("MCU / Motorcontroller"),
                    .bullets([
                        "Steuert Motor und Leistungsabgabe",
                        "Kann je nach Modell Geschwindigkeits- und Fahrparameter verwalten",
                        "In ScooterCheck u. a. als MCU bzw. MCU-G3 abgebildet",
                    ]),
                    .paragraph("BLE / Dashboard"),
                    .bullets([
                        "Bluetooth-Kommunikation mit der App",
                        "Anzeige- und Kommunikationsfunktionen",
                        "In ScooterCheck u. a. als BLE bzw. BLE-Legacy",
                    ]),
                    .paragraph("BMS (Battery Management System)"),
                    .bullets([
                        "Überwacht Akku, Spannung, Temperatur und Ladezustand",
                        "In ScooterCheck u. a. als BMS bzw. BMS-G3",
                    ]),
                    .paragraph("VCU / weitere Steuergeräte"),
                    .bullets([
                        "Bei neueren Modellen (z. B. Max G3) zusätzliche Steuerung und Kommunikation",
                        "In ScooterCheck u. a. als VCU / VCU-G3 sowie Display (DIS) und ggf. TFT",
                    ]),
                    .paragraph("Unterschiede zwischen den Daten dieser Boards (z. B. Seriennummern oder Firmwarestände) können bei einer Prüfung besonders interessant sein."),
                ],
                keywords: ["mcu", "ble", "bms", "vcu", "dis", "board", "steuergerät"]
            ),
            FAQItem(
                id: "maerkte",
                question: "Was bedeuten die Marktprofile DE, EU und US?",
                segments: [
                    .paragraph("ScooterCheck arbeitet mit Soll-Profilen pro Modellfamilie und Markt. Typische Nenn-Höchstgeschwindigkeiten in der App:"),
                    .bullets([
                        "DE: 20 km/h (bauartbedingt / L1e-B-Orientierung)",
                        "EU: 25 km/h",
                        "US (Max G3): ca. 37 km/h",
                    ]),
                    .paragraph("Das gewählte Profil bestimmt, welche Grenzwerte bei der Bewertung als „über Soll“ oder „deutlich über Verdachtsschwelle“ gelten. Eine US-Seriennummer auf einem DE-Profil kann auffällig sein — muss aber nicht automatisch Manipulation bedeuten (z. B. Importgerät)."),
                ],
                keywords: ["region", "de", "eu", "us", "profil", "20", "25", "37"]
            ),
        ]
    )
}

// MARK: - 3. E-Scooter finden

private extension FAQCatalog {
    static let finden = FAQCategory(
        id: "finden",
        title: "E-Scooter finden",
        symbolName: "magnifyingglass",
        items: [
            FAQItem(
                id: "finden-was",
                question: "Was ist „E-Scooter finden“?",
                segments: [
                    .paragraph("„E-Scooter finden“ ist der zentrale Bereich für Radar, Überwachung und signalbasierte Annäherung."),
                    .paragraph("Im Hauptmenü öffnest du eine Übersicht mit drei Funktionen:"),
                    .bullets([
                        "E-Scooter-Radar — erkennt automatisch plausible E-Scooter in der Nähe",
                        "Geräte-Wächter — benachrichtigt dich, wenn gespeicherte Geräte wieder erkannt werden",
                        "Signal-Finder — untersucht Signalstärken, um dich einem Gerät anzunähern",
                    ]),
                    .paragraph("Zum technischen Auslesen nutzt du „E-Scooter auslesen“."),
                    .callout("ScooterCheck bestimmt keinen exakten Standort und ersetzt keine GPS-Ortung. Alle Suchfunktionen arbeiten mit Bluetooth-Signalen."),
                ],
                keywords: [
                    "e-scooter finden", "scooter finden", "scooter suchen", "finden", "suche", "hub", "übersicht",
                    "e-scooter auslesen", "auslesen", "radar", "wächter", "signal-finder", "ortung", "standort",
                ]
            ),
            FAQItem(
                id: "finden-radar",
                question: "Was ist der E-Scooter-Radar?",
                segments: [
                    .paragraph("Der E-Scooter-Radar sucht automatisch nach Bluetooth-Signalen, die zu unterstützten E-Scootern passen können."),
                    .paragraph("Bei plausiblen Treffern mit ausreichendem Signal kann eine Benachrichtigung erscheinen. Du brauchst kein Zielgerät vorzuwählen."),
                    .callout("Ein beliebiges BLE-Gerät (z. B. Smart-Home) wird nicht allein wegen eines Namensfragments als E-Scooter erkannt."),
                ],
                keywords: ["radar", "scooter-radar", "e-scooter-radar", "automatisch", "benachrichtigung", "alarm"]
            ),
            FAQItem(
                id: "finden-waechter",
                question: "Was ist der Geräte-Wächter?",
                segments: [
                    .paragraph("Der Geräte-Wächter (früher „BLE-Wächter“) überwacht ausgewählte Geräte im Hintergrund, soweit iOS das zulässt."),
                    .bullets([
                        "In der Geräte-Detailansicht aktivieren",
                        "Benachrichtigung, wenn das Gerät später wieder erkannt wird",
                        "Einstellungen zu Ton, Haptik, Mindestsignal und Abklingzeit",
                    ]),
                    .paragraph("Unter „E-Scooter finden → Geräte-Wächter“ siehst du alle aktiven Wächter. Manuelles Beenden der App kann die Hintergrundüberwachung stoppen."),
                ],
                keywords: ["wächter", "geräte-wächter", "ble-wächter", "benachrichtigung", "hintergrund", "überwachung"]
            ),
            FAQItem(
                id: "finden-signal-finder",
                question: "Was ist der Signal-Finder?",
                segments: [
                    .paragraph("Der Signal-Finder hilft bei der Annäherung an ein gewähltes Gerät anhand der Bluetooth-Signalstärke (RSSI) und deiner Bewegung."),
                    .paragraph("Vor der Auswahl kannst du filtern und sortieren:"),
                    .bullets([
                        "E-Scooter — nur als E-Scooter erkennbare Signale",
                        "Andere BLE-Geräte — alle übrigen Bluetooth-Signale",
                        "Sortierung nach Signalstärke oder Name",
                        "Optional: Geräte ohne Advertisement-Namen ausblenden",
                    ]),
                    .paragraph("Nach der Gerätewahl öffnet sich zuerst die Detailansicht (ähnlich einer Gerätefinder-App):"),
                    .bullets([
                        "Akustische Näherungssuche — Suchton am iPhone je nach Signalstärke",
                        "Heatmap / Live / AR — visuelle Annäherung",
                        "Optional: dokumentierte Geräteaktionen (Piepen / Blinken), falls erkannt",
                    ]),
                    .paragraph("Drei Ansichten derselben Messsitzung:"),
                    .bullets([
                        "Live — aktuelle Signalstärke, Trend und Kennzahlen",
                        "Heatmap — zweidimensionale Signalfläche, Nutzer zentriert",
                        "AR — AR Signal-Finder mit Kamera und bodenverankerten Signalflächen",
                    ]),
                    .paragraph("In Heatmap und AR zeigen Farben gemessene Signalstärken entlang deines Weges — mint/grün stärker, rot schwächer. Die AR-Minikarte öffnet per Tippen die Heatmap. Option „Suchton aktiv“ steuert das iPhone-Feedback."),
                    .callout("Keine GPS-Ortung des Scooters und keine BLE-Peilung — Messungen liegen am iPhone-Standort, nicht am Gerät. RSSI ist keine Meterangabe."),
                ],
                keywords: [
                    "signal-finder", "heatmap", "live", "ar", "ar signal-finder", "gerät aufspüren", "rssi", "signalstärke",
                    "wärmer", "kälter", "richtung", "annäherung", "karte", "andere ble", "filter", "minikarte",
                    "suchton", "näherungssuche", "piepen", "blinken",
                ]
            ),
            FAQItem(
                id: "finden-geraeteaktionen",
                question: "Kann ScooterCheck ein Gerät piepsen oder blinken lassen?",
                segments: [
                    .paragraph("Ja — aber nur bei dokumentierten, vom Gerät freigegebenen Schnittstellen und nach ausdrücklicher Bestätigung."),
                    .bullets([
                        "Ton am Gerät — Immediate Alert Service (SIG 0x1802 / Alert Level 0x2A06), wenn schreibbar",
                        "Gerät blinken lassen — nur bekannte dokumentierte LED-Profile (z. B. Nordic LED Button Service)",
                        "Akustische Näherungssuche — Suchton am iPhone anhand der RSSI, steuert das Fremdgerät nicht",
                    ]),
                    .paragraph("Vor den Geräteaktionen prüft ScooterCheck die GATT-Services. Unbekannte Characteristics werden nicht wahllos beschrieben."),
                    .callout("Ein erfolgreicher BLE-Schreibbefehl beweist keinen hörbaren Ton und kein sichtbares Blinken. Authentifizierung und Pairing-Grenzen werden respektiert."),
                ],
                keywords: [
                    "piepen", "blinken", "alarm", "immediate alert", "led", "finden", "airtag",
                    "ton am gerät", "näherungssuche", "suchton", "gatt",
                ]
            ),
            FAQItem(
                id: "finden-tipps",
                question: "Wie nutze ich den Signal-Finder am besten?",
                segments: [
                    .paragraph("Praktische Vorgehensweise:"),
                    .bullets([
                        "Gerät wählen und Messung starten",
                        "Langsam gehen und Signal + Trend beobachten",
                        "Blickrichtung und Wärmer/Kälter nutzen",
                        "Zu den grünen / starken Heatmap-Bereichen zurückkehren, wenn das Signal schwächer wird",
                        "iPhone frei halten (nicht stark mit dem Körper abschirmen)",
                        "Indoor: AR Signal-Finder oder Kamera-Tracking für räumliche Zuordnung nutzen",
                        "Bei AR langsam bewegen; bei Tracking-Hinweis neu ausrichten",
                    ]),
                    .callout("Systematisch absuchen ist zuverlässiger als einem einzelnen Pfeil zu folgen. BLE liefert keine exakte Richtung."),
                ],
                keywords: ["tipps", "schnell", "suche", "bewegen", "heatmap", "live", "kamera", "ar"]
            ),
            FAQItem(
                id: "finden-genauigkeit",
                question: "Wie genau sind Entfernung und Standort?",
                segments: [
                    .paragraph("Entfernung und Standort sind nicht exakt bestimmbar. Bluetooth-Signalstärken werden beeinflusst durch:"),
                    .bullets([
                        "Mauern, Fahrzeuge, Personen und Metall",
                        "Ausrichtung von Scooter und iPhone",
                        "Sendeleistung, Reflexionen und Funkstörungen",
                    ]),
                    .paragraph("Deshalb zeigt ScooterCheck Signalstufen (z. B. Schwach, Mittel, Stark) — keine vermeintlich präzisen Meter."),
                    .paragraph("Ein ausgeschalteter Scooter ohne BLE-Werbung kann nicht gefunden werden. Signale durch Wände sind möglich, aber oft stark abgeschwächt."),
                ],
                keywords: [
                    "entfernung", "genauigkeit", "meter", "gps", "exakt", "standort", "ortung",
                    "ausgeschaltet", "wand", "hindernis", "reichweite",
                ]
            ),
            FAQItem(
                id: "finden-erkennung",
                question: "Warum erscheint ein Fremdgerät als Scooter?",
                segments: [
                    .paragraph("ScooterCheck stuft Geräte nur anhand nachvollziehbarer Merkmale ein (Name, Dienste, Serien-/Modellmuster)."),
                    .paragraph("Zufällige Buchstaben in Geräte-IDs (z. B. „F3“ in einer Shelly-Hex-ID) reichen nicht für eine Scooter-Zuordnung."),
                    .bullets([
                        "Unbekanntes BLE-Gerät",
                        "Möglicher E-Scooter (Hinweis, keine Sicherheit)",
                        "Bestätigter Scooter erst nach erfolgreicher technischer Validierung",
                    ]),
                    .callout("Unter „Alle BLE-Geräte“ siehst du den echten Bluetooth-Namen. Dauerhaft gespeichert wird nur ein validierter Scooter."),
                ],
                keywords: [
                    "erkennung", "shelly", "fremdgerät", "falsch", "ninebot f3", "heuristik",
                    "möglicher scooter", "alle ble", "filter",
                ]
            ),
            FAQItem(
                id: "finden-identifikation",
                question: "Wie erkennt ScooterCheck unbekannte BLE-Geräte?",
                segments: [
                    .paragraph("Während der BLE-Suche analysiert ScooterCheck automatisch verfügbare Advertisement-Merkmale — für E-Scooter und für alle anderen BLE-Geräte, ohne zweiten Scan."),
                    .bullets([
                        "Hersteller über Bluetooth Company Identifier (SIG Assigned Numbers)",
                        "Geräteklasse (TV, Audio, Smartwatch, Beacon, Smart-Home, Sensor …) nur mit zusätzlichen Merkmalen — nie allein aus dem Hersteller",
                        "Modell nur bei dokumentierten Namens-/Protokollhinweisen",
                        "Fingerprint aus stabilen Advertising-Mustern (ohne RSSI als Identität)",
                    ]),
                    .paragraph("Unter „Andere BLE“ erscheinen z. B. „Samsung – Fernseher / Media“ oder „Mögliches Beacon“, sobald die Daten das tragen. In der Geräteanalyse: Evidenz, 30 s beobachten, optional Online (nur nach Zustimmung), nur-lesende GATT-Analyse."),
                    .callout("Ohne ausreichende Daten bleibt die Klasse „unbekannt“. Online-Treffer allein lösen keinen Radar-Alarm aus. iOS liefert keine fremden Bluetooth-MAC-Adressen."),
                ],
                keywords: [
                    "identifikation", "hersteller", "company identifier", "fingerprint", "gatt",
                    "online", "unbekanntes ble", "andere ble", "samsung", "fernseher", "beacon",
                    "smart-home", "ninebot", "analyse", "evidenz",
                ]
            ),
            FAQItem(
                id: "finden-nicht-gefunden",
                question: "Warum wird mein Scooter nicht gefunden?",
                segments: [
                    .paragraph("Häufige Ursachen:"),
                    .bullets([
                        "Scooter ausgeschaltet oder sendet kein BLE",
                        "Bluetooth-Berechtigung fehlt",
                        "zu große Entfernung oder Abschirmung",
                        "Modell / Advertisement weicht ab",
                        "Filter „Scooter“ blendet unsichere Treffer aus — prüfe „Alle BLE-Geräte“",
                    ]),
                ],
                keywords: ["nicht gefunden", "fehlt", "reichweite", "ausgeschaltet", "berechtigung", "filter"]
            ),
            FAQItem(
                id: "finden-schwankt",
                question: "Warum schwankt die Signalstärke?",
                segments: [
                    .paragraph("RSSI schwankt naturgemäß — durch Bewegung, Körperabschirmung, Reflexionen und Hindernisse."),
                    .paragraph("ScooterCheck glättet Messwerte, soweit sinnvoll. Im Signal-Finder bleiben bereits gemessene Bereiche möglichst farbstabil; neue Messungen ergänzen lokal."),
                ],
                keywords: ["schwankt", "rssi", "glättung", "reflexion", "störung", "signal", "farbe"]
            ),
        ]
    )
}

// MARK: - 4. Tuning verstehen

private extension FAQCatalog {
    static let tuning = FAQCategory(
        id: "tuning",
        title: "Tuning verstehen",
        symbolName: "wrench.and.screwdriver",
        items: [
            FAQItem(
                id: "was-tuning",
                question: "Was bedeutet E-Scooter-Tuning?",
                segments: [
                    .paragraph("Unter Tuning versteht man technische oder softwareseitige Änderungen, durch die ein Scooter vom vorgesehenen bzw. zugelassenen Zustand abweicht. Das kann z. B. betreffen:"),
                    .bullets([
                        "Geschwindigkeitsbegrenzung",
                        "Region",
                        "Fahrmodi / Gänge",
                        "Leistungsparameter",
                        "Firmware",
                        "Controller und andere Steuergeräte",
                        "Kommunikationsmodule",
                    ]),
                    .callout("Nicht jede Abweichung bedeutet automatisch Manipulation. Mögliche andere Ursachen: Softwareupdate, Reparatur, Ersatzteil, andere Hardwaregeneration, andere Region oder Modellvariante."),
                    .paragraph("ScooterCheck bewertet deshalb mehrere Informationen gemeinsam und leitet möglichst nicht aus einem einzigen Wert eine endgültige Aussage ab."),
                ],
                keywords: ["tuning", "manipulation", "abweichung"]
            ),
            FAQItem(
                id: "arten",
                question: "Welche Arten von Tuning gibt es?",
                segments: [
                    .paragraph("1. Änderung von Geschwindigkeitsparametern"),
                    .paragraph("Je nach Modell können Geschwindigkeitslimits oder Fahrmodusparameter als Konfigurationswerte gespeichert sein. Solche Parameter können bei Manipulation verändert werden. ScooterCheck liest – soweit vorhanden – konfigurierte Limits und Trip-Peaks aus und vergleicht sie mit dem Soll-Profil."),
                    .paragraph("2. Temporärer Soft Unlock"),
                    .paragraph("Ein Soft Unlock kann bei manchen Systemen nur während des laufenden Betriebs aktiv sein. Bestimmte Parameter können beispielsweise nur im Arbeitsspeicher verändert sein. Nach einem vollständigen Neustart können ursprüngliche Werte wieder vorhanden sein. Deshalb können temporäre Änderungen schwieriger nachweisbar sein. ScooterCheck bewertet nur Informationen, die bei der aktuellen Prüfung technisch verfügbar sind (siehe auch den Eintrag zu Soft Unlock)."),
                    .paragraph("3. Persistente / dauerhafte Änderung"),
                    .paragraph("Andere Änderungen werden dauerhaft gespeichert und können auch nach Ausschalten, Neustart oder Power-Cycle bestehen bleiben. Solche persistenten Änderungen können bei Vergleichstests leichter auffallen."),
                    .paragraph("4. Region Change"),
                    .paragraph("Scooter können für verschiedene Märkte (Deutschland, Europa, USA u. a.) unterschiedliche Konfigurationen besitzen — z. B. Geschwindigkeitsgrenzen, Fahrmodi und Konfigurationswerte. Eine abweichende Region allein ist kein sicherer Beweis für Tuning und soll gemeinsam mit weiteren Daten betrachtet werden."),
                    .paragraph("5. Firmware-Modifikation"),
                    .paragraph("Firmware ist die Software eines Steuergeräts. Eine veränderte Firmware kann Verhalten und Parameter beeinflussen. ScooterCheck kann, soweit unterstützt, Firmwareversionen auslesen, Boards vergleichen und ungewöhnliche bzw. bekannte auffällige Versionsstrings erkennen. Die App analysiert nicht automatisch den vollständigen Programmcode jeder Firmware."),
                    .paragraph("6. Custom Firmware"),
                    .paragraph("Custom Firmware ist eine speziell veränderte Firmware, die mehrere Parameter gleichzeitig ändern kann. Ob sie erkannt wird, hängt davon ab, welche Informationen der Scooter bereitstellt und welche Einträge ScooterCheck im Firmware-Katalog kennt."),
                    .paragraph("7. Lizenz- oder Code-basierte Freischaltung"),
                    .paragraph("Manche Lösungen aktivieren Änderungen über einen Code oder eine Lizenz. Technisch kann dahinter trotzdem eine Änderung von Konfiguration, Firmware, persistenten Parametern oder Laufzeitparametern stehen. ScooterCheck gibt keine Anleitung zur Nutzung solcher Dienste."),
                    .paragraph("8. Austausch von Steuergeräten"),
                    .paragraph("Werden Controller, BLE-/Dashboard-Modul, BMS oder VCU ersetzt, können Seriennummern und Firmwarestände zwischen Boards nicht mehr zusammenpassen. Deshalb vergleicht ScooterCheck Daten verschiedener Steuergeräte."),
                    .paragraph("9. Fremdcontroller / VESC"),
                    .paragraph("Bei tiefgreifenden Umbauten kann der originale Motorcontroller ersetzt werden. Dann kann ScooterCheck möglicherweise nur eingeschränkt oder gar nicht auf relevante Originaldaten zugreifen."),
                ],
                keywords: ["soft unlock", "region", "firmware", "custom", "vesc", "controller", "persistenz"]
            ),
            FAQItem(
                id: "soft-unlock",
                question: "Was ist Soft Unlock – und wie erkennt ScooterCheck ihn?",
                segments: [
                    .paragraph("Soft Unlock bezeichnet typischerweise eine temporäre Freischaltung während des Betriebs (z. B. nach einer Bedienungsgeste). Die Wirkung kann sich in auslesbaren Werten wie erhöhtem Geschwindigkeitslimit oder Trip-Peak zeigen und nach dem Ausschalten wieder verschwinden."),
                    .paragraph("In ScooterCheck ist die Soft-Unlock-Erkennung Teil der technischen Bewertung (Evidence). Erkannt wird die Wirkung: wenn Limit und/oder Trip-Peak eine Schwelle erreichen bzw. ein Session-Hinweis gesetzt ist. Es gibt keinen eingebauten Katalog geheimer Tastenkombinationen."),
                    .paragraph("Im Prüfbericht startet der geführte Vergleichstest diese Prüfung: Ausgangszustand (aktueller Bericht), Aktivierung mit Geheimkombination und erneute Auslese, danach optional die Persistenzprüfung nach Neustart. Erfolgreiche Kombinationen können pro Seriennummer gespeichert und später wieder geladen werden."),
                    .callout("ScooterCheck erklärt Soft Unlock nur zum Verständnis und zur Diagnose. Die App liefert keine Anleitung zum Manipulieren oder Entsperren eines Scooters."),
                ],
                keywords: ["soft unlock", "session", "geste", "rescan", "peak", "limit", "temporär"]
            ),
        ]
    )
}

// MARK: - 5. Was ScooterCheck auslesen kann

private extension FAQCatalog {
    static let auslesen = FAQCategory(
        id: "auslesen",
        title: "Was ScooterCheck auslesen kann",
        symbolName: "dot.radiowaves.left.and.right",
        items: [
            FAQItem(
                id: "tiefe",
                question: "Wie tief kann ScooterCheck auslesen?",
                segments: [
                    .paragraph("Die Auslese-Tiefe hängt vom Modell und der Firmware ab:"),
                    .bullets([
                        "Ninebot Max G3: Enc2-Auslese inkl. G3-Registerkarte und Firmware-Katalog (DE 1CGB / EU 1CGE / US 1CGC)",
                        "Ninebot F3 Pro: Enc2-Auslese mit derselben G3-Registerkarte (SN 1EFH… / VCU 1EFC…)",
                        "Ninebot Max G2, G30, ZT3 Pro, F-/E-/D-Serie: Enc2, Registerkarte ähnlich G30/Legacy; Firmware-Katalog ggf. eingeschränkt",
                        "Xiaomi Classic: Klartext-Protokoll (55 AA)",
                        "Xiaomi 3/4: oft verschlüsselt (55 AB) — Auslese dann eingeschränkt oder nicht möglich",
                    ]),
                ],
                keywords: ["enc2", "g3", "xiaomi", "auslese", "support"]
            ),
            FAQItem(
                id: "seriennummern",
                question: "Welche Seriennummern und Board-Kennungen liest ScooterCheck?",
                segments: [
                    .paragraph("Soweit vom Scooter bereitgestellt, wertet ScooterCheck Kennungen mehrerer Boards aus und vergleicht sie (Cross-Board):"),
                    .bullets([
                        "MCU / MCU-G3",
                        "BLE / BLE-Legacy",
                        "BMS / BMS-G3",
                        "VCU / VCU-G3",
                        "Display (DIS) und ggf. weitere Module",
                    ]),
                    .paragraph("Abweichende Seriennummern zwischen Boards können auf getauschte Module hinweisen — oder auf Reparaturen mit Ersatzteilen."),
                ],
                keywords: ["seriennummer", "cross-board", "mcu", "ble", "bms", "vcu"]
            ),
            FAQItem(
                id: "region-speed",
                question: "Welche Regions- und Geschwindigkeitswerte werden bewertet?",
                segments: [
                    .paragraph("Je nach Registerkarte und Modell können u. a. ausgewertet werden:"),
                    .bullets([
                        "Region / Marktbezug (z. B. über Serienpräfixe wie 1CGB/1CGE/1CGC bei Max G3 bzw. 1EFH/1EFC bei F3 Pro)",
                        "Konfiguriertes Geschwindigkeitslimit (Speed Limit)",
                        "Trip Peak / gespeicherte Spitzengeschwindigkeit (nicht dasselbe wie das konfigurierte Limit)",
                        "Session-/Soft-Unlock-Hinweise (Limit/Peak über Schwelle)",
                        "Fahrmodus / Gangstufe (z. B. freigeschaltete höhere Gänge)",
                    ]),
                    .paragraph("Grenzwerte für „über Soll“ und „deutlich auffällig“ hängen vom gewählten Profil ab (DE/EU/US)."),
                ],
                keywords: ["region", "limit", "peak", "trip", "gang", "modus", "geschwindigkeit"]
            ),
            FAQItem(
                id: "firmware",
                question: "Was prüft ScooterCheck bei der Firmware?",
                segments: [
                    .paragraph("ScooterCheck liest board-spezifische Firmwareversionen aus (z. B. MCU, VCU, BLE, BMS) und vergleicht sie miteinander sowie mit einem Stock-Firmware-Katalog (lokal und ggf. aktualisierbar)."),
                    .bullets([
                        "Bekannte Serienversionen im Katalog",
                        "Unbekannte Versionen (Katalogtreffer fehlt)",
                        "Auffällige Versionsstrings / Custom-Firmware-Hinweise (textuelle Marker, kein Binärvergleich der gesamten Firmware)",
                    ]),
                    .paragraph("Zusätzlich kann eine Attribution heuristisch möglichen Methoden zuordnen (z. B. Custom-FW, Session-Unlock, Regionswechsel) — das ändert die Hauptbewertung nicht und ist kein Beweis für ein bestimmtes Tool."),
                ],
                keywords: ["firmware", "katalog", "custom", "version", "attribution"]
            ),
            FAQItem(
                id: "marker",
                question: "Welche Marker und Statusflags kennt ScooterCheck?",
                segments: [
                    .paragraph("In der Evidenzmatrix können u. a. folgende Marker vorkommen (soweit die Auslese sie liefert):"),
                    .bullets([
                        "speed.limit — konfiguriertes Limit über Soll",
                        "speed.peak — Trip Peak über Soll",
                        "speed.session — Session-/Soft-Unlock-Hinweis",
                        "region.sn — Regions-/Serienhinweis vs. Profil",
                        "fw.custom / fw.unknown — Firmware-Auffälligkeiten",
                        "gear.max — freigeschaltete Gänge",
                        "safelock — SafeLock-Status (Soll: aktiv)",
                        "session.reset — früherer Unlock, Session-Hinweis inzwischen weg",
                        "serial.cross.* — Seriennummern-Konflikt zwischen Boards",
                    ]),
                    .paragraph("SafeLock kommt aus auslesbaren Statusregistern. Felder wie Panic-Modus oder Unbound/Rebound können in Berichten und Demo-/Track-Logik vorkommen; eine live ausgelesene Panic-/Unbound-Erkennung ist nicht als belastbare Dauerfunktion für alle Modelle vorgesehen."),
                ],
                keywords: ["marker", "safelock", "panic", "unbound", "evidence", "session"]
            ),
            FAQItem(
                id: "vergleichstest",
                question: "Was ist der Vergleichstest?",
                segments: [
                    .paragraph("Im Prüfbericht startet „Vergleichstest“ einen geführten Vorher/Nachher-Ablauf:"),
                    .bullets([
                        "Schritt 1 — Ausgangszustand: der aktuelle Prüfbericht als Baseline",
                        "Schritt 2 — Aktivierung: Geheimkombination am Scooter, erneute Auslese und Vergleich",
                        "Schritt 3 — Persistenz: Neustart (Power Cycle), erneute Auslese — bleibt die Änderung oder verschwindet sie?",
                    ]),
                    .paragraph("In Schritt 3 werden u. a. Limit, Trip Peak, Session-Flag, Region, Fahrmodus sowie Firmware-Angaben von MCU/VCU verglichen. So unterscheidet ScooterCheck typischerweise:"),
                    .bullets([
                        "Temporäre Änderung: verschwindet nach Neustart",
                        "Persistente Änderung: bleibt nach Neustart bestehen",
                    ]),
                    .paragraph("Die Persistenzprüfung kann übersprungen werden; Aktivierungs- und Detection-Logik bleiben erhalten."),
                ],
                keywords: ["vergleichstest", "power cycle", "neustart", "persistenz", "geheimkombination", "unlock"]
            ),
            FAQItem(
                id: "weitere",
                question: "Welche weiteren Messwerte können im Bericht stehen?",
                segments: [
                    .paragraph("Neben den zentralen Manipulationshinweisen können – modellabhängig – weitere Messwerte erscheinen, z. B.:"),
                    .bullets([
                        "Kilometerstand / Odometer",
                        "Akkuspannung / Ladezustand / Temperaturen",
                        "Fehlercodes und Statusbits",
                        "Protokoll-/Integrity-Hash und Boardliste",
                        "Rohdatenregister (Adresse, Name, Hexwert, Interpretation)",
                    ]),
                    .paragraph("Freiwillige Angaben wie Kennzeichen oder Alias fließen nicht in die technische Bewertung ein."),
                ],
                keywords: ["odometer", "akku", "fehler", "rohdaten", "kennzeichen"]
            ),
        ]
    )
}

// MARK: - 6. Register & Rohdaten

private extension FAQCatalog {
    static let register = FAQCategory(
        id: "register",
        title: "Register & Rohdaten",
        symbolName: "list.number",
        items: [
            FAQItem(
                id: "was-register",
                question: "Was ist ein Register?",
                segments: [
                    .paragraph("Ein Register kann vereinfacht als kleines Datenfeld innerhalb eines Steuergeräts verstanden werden. Darin können Informationen oder Zustände gespeichert bzw. bereitgestellt werden."),
                    .bullets([
                        "Geschwindigkeitslimit",
                        "Region",
                        "Statusbits",
                        "Fahrmodus",
                        "Versionsinformation",
                        "Konfigurationswerte",
                    ]),
                    .paragraph("Register besitzen häufig eine Adresse oder Kennung. ScooterCheck liest bei unterstützten Modellen solche Werte aus und interpretiert sie."),
                ],
                keywords: ["register", "adresse", "datenfeld"]
            ),
            FAQItem(
                id: "warum-register",
                question: "Warum sind Register bei einer Prüfung interessant?",
                segments: [
                    .paragraph("Ein einzelner Registerwert sagt oft wenig aus. Interessant wird es, wenn mehrere Werte miteinander verglichen werden."),
                    .paragraph("Beispiel: Die Region meldet Deutschland, gleichzeitig liefert ein anderer Wert ein Geschwindigkeitslimit, das dazu nicht passt — oder mehrere Steuergeräte liefern widersprüchliche Informationen. Solche Kombinationen können technisch auffällig sein."),
                ],
                keywords: ["vergleich", "widerspruch", "kombination"]
            ),
            FAQItem(
                id: "rohdaten",
                question: "Was sind Raw Data / Rohdaten?",
                segments: [
                    .paragraph("Rohdaten sind möglichst unverarbeitete Informationen direkt vom Steuergerät. ScooterCheck kann – soweit implementiert – Board, Register, Rohwert (Hex) und interpretierten Wert anzeigen bzw. im PDF unter den technischen Anhängen auflisten."),
                    .paragraph("Das erhöht die Nachvollziehbarkeit der Bewertung: Man sieht nicht nur das Endergebnis, sondern auch die zugrunde liegenden Messwerte."),
                ],
                keywords: ["raw", "rohdaten", "hex", "pdf"]
            ),
            FAQItem(
                id: "cross-board",
                question: "Warum vergleicht ScooterCheck verschiedene Steuergeräte?",
                segments: [
                    .paragraph("Eine Veränderung betrifft nicht zwingend alle Boards gleichzeitig. Beispielsweise kann ein Controller verändert, ein Dashboard ersetzt, eine Region geändert oder nur ein einzelner Parameter angepasst worden sein."),
                    .paragraph("Deshalb können widersprüchliche Informationen zwischen MCU, BLE, BMS, VCU und Display besonders interessant sein. ScooterCheck prüft u. a. Seriennummern-Konflikte und korreliert Regions-, Limit- und Firmware-Hinweise in der Evidenzmatrix."),
                ],
                keywords: ["cross-board", "korrelation", "boards", "seriennummer"]
            ),
            FAQItem(
                id: "warum-rohdaten-ui",
                question: "Warum zeigt ScooterCheck technische Rohdaten an?",
                segments: [
                    .paragraph("Damit Bewertungen nachvollziehbar bleiben. Der Nutzer soll nicht nur ein Endergebnis sehen, sondern – soweit möglich – verstehen können, welche technischen Informationen dazu geführt haben."),
                ],
                keywords: ["nachvollziehbarkeit", "transparenz"]
            ),
        ]
    )
}

// MARK: - 7. Bewertungen & Ergebnisse

private extension FAQCatalog {
    static let bewertungen = FAQCategory(
        id: "bewertungen",
        title: "Bewertungen & Ergebnisse",
        symbolName: "checkmark.seal",
        items: [
            FAQItem(
                id: "stufen",
                question: "Welche Bewertungsergebnisse gibt es?",
                segments: [
                    .paragraph("ScooterCheck verwendet technische Bewertungsstufen (keine rechtlichen Feststellungen):"),
                    .paragraph("Serienzustand"),
                    .paragraph("In den aktuell verfügbaren Daten wurden keine relevanten technischen Abweichungen festgestellt. Das bedeutet nicht zwingend, dass der Scooter in seiner gesamten Vergangenheit nie verändert war."),
                    .paragraph("Auffällig"),
                    .paragraph("Ein oder mehrere ungewöhnliche Werte wurden gefunden, reichen allein aber nicht für eine eindeutige technische Aussage."),
                    .paragraph("Manipulationshinweise"),
                    .paragraph("Mehrere technische Informationen können darauf hindeuten, dass der Scooter verändert wurde. Die Daten ergeben aber noch keine technisch eindeutige Gesamtbewertung."),
                    .paragraph("Technisch eindeutige Abweichung"),
                    .paragraph("Mehrere technische Informationen ergeben zusammen eine deutliche Abweichung vom erwarteten Serienzustand — oder es liegt mindestens ein klarer technischer Punkt vor (z. B. stark überhöhtes Limit oder bestätigte Custom-Firmware-Hinweise)."),
                    .callout("Diese Bewertung ist eine technische Bewertung der ausgelesenen Daten. Sie ist keine automatische rechtliche Feststellung."),
                ],
                keywords: ["serienzustand", "auffällig", "manipulationshinweise", "eindeutig", "verdict"]
            ),
            FAQItem(
                id: "interpretieren",
                question: "Wie soll ein Ergebnis interpretiert werden?",
                segments: [
                    .paragraph("Einfaches Drei-Schritte-Prinzip:"),
                    .bullets([
                        "Einzelwert ansehen — Was wurde konkret festgestellt?",
                        "Zusammenhang betrachten — Passen Region, Firmware, Seriennummern, Konfiguration und andere Boards zusammen?",
                        "Gesamtergebnis betrachten — Wie bewertet ScooterCheck die Kombination aller verfügbaren Informationen?",
                    ]),
                    .paragraph("Ein einzelner ungewöhnlicher Wert soll vorsichtiger bewertet werden als mehrere unabhängige Hinweise."),
                    .callout("Technische Auffälligkeiten können auch durch Reparaturen, Ersatzteile, Softwareupdates oder Modellvarianten entstehen und sollten immer im Gesamtzusammenhang betrachtet werden."),
                ],
                keywords: ["interpretation", "zusammenhang", "hinweis"]
            ),
            FAQItem(
                id: "score",
                question: "Was bedeutet der Score / die Seriennähe?",
                segments: [
                    .paragraph("Neben der Bewertungsstufe kann ein Score (Seriennähe) angezeigt werden. Die endgültige Stufe folgt regelbasierten Evidenzregeln — nicht allein dem Score."),
                    .paragraph("Neutralisierungen können einzelne Hinweise abschwächen (z. B. wenn ein US-Gerät bewusst am DE-Profil geprüft wird und die Daten dazu passen)."),
                ],
                keywords: ["score", "seriennähe", "neutralisierung"]
            ),
        ]
    )
}

// MARK: - 8. Grenzen

private extension FAQCatalog {
    static let grenzen = FAQCategory(
        id: "grenzen",
        title: "Grenzen von ScooterCheck",
        symbolName: "exclamationmark.triangle",
        items: [
            FAQItem(
                id: "nicht-alles",
                question: "Kann ScooterCheck jede Manipulation erkennen?",
                segments: [
                    .paragraph("Nein. ScooterCheck kann nur technisch verfügbare und auslesbare Hinweise bewerten. Die Erkennung hängt unter anderem davon ab:"),
                    .bullets([
                        "welches Modell verwendet wird",
                        "welche Firmware installiert ist",
                        "welche Daten das Fahrzeug bereitstellt",
                        "wie eine Veränderung durchgeführt wurde",
                        "ob die Veränderung aktuell aktiv ist",
                        "ob Werte persistent gespeichert wurden",
                        "ob eine Veränderung vollständig rückgängig gemacht wurde",
                    ]),
                    .callout("ScooterCheck bewertet die aktuell technisch auslesbaren Daten. Ein unauffälliges Ergebnis ist kein Beweis dafür, dass ein Fahrzeug zu keinem früheren Zeitpunkt verändert wurde."),
                ],
                keywords: ["grenzen", "erkennung", "nicht", "manipulation"]
            ),
            FAQItem(
                id: "vergangenheit",
                question: "Kann ScooterCheck feststellen, ob ein Scooter irgendwann früher einmal getunt war?",
                segments: [
                    .paragraph("Nicht sicher. Wenn eine frühere Veränderung vollständig rückgängig gemacht wurde und keine auslesbaren Spuren zurückgeblieben sind, kann ScooterCheck diese möglicherweise nicht feststellen."),
                    .callout("ScooterCheck zeigt, was technisch auslesbar ist – nicht, was theoretisch irgendwann am Fahrzeug passiert sein könnte."),
                ],
                keywords: ["historie", "früher", "spuren", "rückgängig"]
            ),
            FAQItem(
                id: "historische-speed",
                question: "Kann ScooterCheck historische Geschwindigkeiten rekonstruieren?",
                segments: [
                    .paragraph("Nur wenn das jeweilige Steuergerät entsprechende Werte tatsächlich gespeichert hat und diese auslesbar sind (z. B. Trip Peak). Nicht gespeicherte historische Werte können nicht nachträglich rekonstruiert werden."),
                ],
                keywords: ["historisch", "geschwindigkeit", "peak", "rekonstruieren"]
            ),
            FAQItem(
                id: "mechanisch",
                question: "Kann ScooterCheck mechanisches Tuning erkennen?",
                segments: [
                    .paragraph("Nicht zuverlässig. ScooterCheck analysiert elektronische und digital auslesbare Informationen. Rein mechanische Änderungen können damit nicht vollständig bewertet werden."),
                ],
                keywords: ["mechanisch", "hardware", "umbau"]
            ),
            FAQItem(
                id: "externe-hw",
                question: "Kann ScooterCheck externe Tuning-Hardware erkennen?",
                segments: [
                    .paragraph("Nicht in jedem Fall. Wenn zusätzliche Hardware zwischen Komponenten geschaltet wird oder Werte verändert bzw. plausibel simuliert werden, kann eine reine softwarebasierte Diagnose Grenzen haben."),
                ],
                keywords: ["externe", "hardware", "zwischenmodul"]
            ),
            FAQItem(
                id: "tausch",
                question: "Was passiert bei ausgetauschten Steuergeräten?",
                segments: [
                    .paragraph("Wenn Originalkomponenten ersetzt wurden, können andere Seriennummern, andere Firmwarestände, andere Kommunikationsdaten oder gar keine kompatiblen Daten vorliegen. Dadurch kann die Auswertung eingeschränkt sein — oder gerade durch Cross-Board-Vergleiche auffällig werden."),
                ],
                keywords: ["austausch", "ersatzteil", "steuergerät"]
            ),
            FAQItem(
                id: "forensik",
                question: "Ist ScooterCheck eine vollständige forensische Analyse?",
                segments: [
                    .paragraph("Nein. ScooterCheck ist keine Labor- oder Chipforensik. Die App:"),
                    .bullets([
                        "öffnet keine Steuergeräte",
                        "führt keine Chip-Off-Analyse durch",
                        "liest nicht automatisch vollständige Flash-Speicher aus",
                        "analysiert nicht jeden Bytecode einer Firmware",
                        "ersetzt keine tiefergehende Hardware- oder Speicherforensik",
                    ]),
                ],
                keywords: ["forensik", "chip", "labor", "flash"]
            ),
            FAQItem(
                id: "nicht-auslesen",
                question: "Was kann ScooterCheck bewusst nicht?",
                segments: [
                    .bullets([
                        "Keine Limit-, Regions- oder Firmware-Änderungen am Scooter",
                        "Kein Firmware-Flash und keine Unlock-Kombos ausliefern",
                        "Keine vollständige Erkennung rückgängig gemachter Manipulationen ohne Spuren",
                        "Keine zuverlässige Bewertung rein mechanischer Umbauten",
                        "Bei stark verschlüsselten Protokollen (z. B. manche Xiaomi 3/4) ggf. keine tiefe Auslese",
                    ]),
                ],
                keywords: ["kann nicht", "grenzen", "xiaomi"]
            ),
        ]
    )
}

// MARK: - 9. Häufige Fragen

private extension FAQCatalog {
    static let haeufige = FAQCategory(
        id: "haeufige",
        title: "Häufige Fragen",
        symbolName: "questionmark.circle",
        items: [
            FAQItem(
                id: "warum-profil",
                question: "Warum muss ich ein Profil bestätigen?",
                segments: [
                    .paragraph("Das Soll-Profil (Familie + Markt) legt fest, welche Nenngeschwindigkeit und Schwellen ScooterCheck erwartet. Ohne Profil wären Limit- und Regionsvergleiche nicht sinnvoll einzuordnen."),
                    .paragraph("Die App schlägt anhand von BLE-Namen und Serienhinweisen oft ein Profil vor — die endgültige Wahl liegt beim Nutzer."),
                ],
                keywords: ["profil", "bestätigen", "markt"]
            ),
            FAQItem(
                id: "bericht",
                question: "Was enthält der Prüfbericht?",
                segments: [
                    .paragraph("Der exportierte Bericht (PDF/JSON) dokumentiert u. a. Zusammenfassung, Messwerte, optionale Attribution, technische Anhänge (Rohregister, Boards, Firmware, Evidenzmatrix, Neutralisierungen, Power-Cycle, ggf. Unlock-Hinweise) sowie methodische Hinweise."),
                    .paragraph("Gespeicherte Prüfungen bleiben in der App unter „Prüfungen“ verfügbar."),
                ],
                keywords: ["bericht", "pdf", "json", "protokoll"]
            ),
            FAQItem(
                id: "unlock-rescan",
                question: "Wie hängt Soft Unlock mit dem Vergleichstest zusammen?",
                segments: [
                    .paragraph("Die frühere Unlock-Auslese ist jetzt Schritt 2 des Vergleichstests: Messung ohne und mit Geheimkombination. Anschließend prüft Schritt 3 nach Neustart die Persistenz."),
                    .paragraph("Der Vergleichstest liefert keine Anleitung zur Manipulation — er dokumentiert nur auslesbare Unterschiede."),
                ],
                keywords: ["unlock", "rescan", "soft unlock", "geste", "vergleichstest"]
            ),
            FAQItem(
                id: "bluetooth",
                question: "Warum findet ScooterCheck meinen Scooter nicht?",
                segments: [
                    .paragraph("Häufige Ursachen: Bluetooth-Berechtigung fehlt, Scooter ist aus oder bereits mit einem anderen Gerät verbunden, Name weicht stark ab, oder das Gerät sendet nicht als typischer Scooter."),
                    .paragraph("Bei Xiaomi 3/4 kann selbst nach erfolgreicher Verbindung die Auslese wegen Verschlüsselung eingeschränkt sein."),
                ],
                keywords: ["bluetooth", "finden", "suche", "verbinden"]
            ),
            FAQItem(
                id: "scooter-finden",
                question: "Was macht „E-Scooter finden“?",
                segments: [
                    .paragraph("„E-Scooter finden“ bündelt E-Scooter-Radar, Geräte-Wächter und Signal-Finder. Diagnose-Auslesen liegt unter „E-Scooter auslesen“."),
                    .bullets([
                        "Automatisches Radar",
                        "Hintergrund-Wächter mit Benachrichtigung",
                        "Signal-Finder mit Live-Heatmap zur Annäherung",
                    ]),
                    .callout("Details stehen im FAQ-Kapitel „E-Scooter finden“. Keine GPS-Ortung — nur Bluetooth-Signalhilfe."),
                ],
                keywords: ["finden", "e-scooter finden", "richtung", "rssi", "signal", "nähe", "wächter", "radar", "signal-finder", "auslesen"]
            ),
            FAQItem(
                id: "einstellungen-schrift",
                question: "Wo stelle ich die Schriftgröße ein?",
                segments: [
                    .paragraph("Im linken Menü unter „Einstellungen“ kannst du die Schriftgröße für die gesamte App wählen:"),
                    .bullets([
                        "Kompakt",
                        "Standard",
                        "Groß",
                        "Sehr groß",
                    ]),
                    .paragraph("Dort legst du auch Startwerte für „E-Scooter auslesen“ (Filter, Sortierung) und den Signal-Finder (Suchton/Haptik) fest sowie die App-Version."),
                    .paragraph("Die Werte werden lokal gespeichert. Radar- und Karten-Optionen bleiben am jeweiligen Zahnrad."),
                ],
                keywords: [
                    "einstellungen", "schriftgröße", "darstellung", "lesbarkeit", "textgröße", "barrierefreiheit",
                    "suchton", "haptik", "sortierung", "filter", "version",
                ]
            ),
        ]
    )
}
