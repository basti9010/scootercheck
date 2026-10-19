import Foundation

/// Datenschutz-Inhalte aus dem tatsächlichen Codepfad abgeleitet — keine erfundenen Server-/SDK-Claims.
enum PrivacyContent {
    /// Aus App-Copyright ersichtlich; Anschrift/E-Mail sind in der App nicht hinterlegt.
    static let copyrightHolderName = "Bastian Ellinghausen"

    /// Stand der dokumentierten Implementierung (App-Quellcode).
    static let documentVersionLabel: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        return "Stand der technischen Beschreibung: \(f.string(from: Date()))"
    }()

    static let hubSubtitle = "Deine Daten. Transparent erklärt."

    static let atAGlanceTitle = "Deine Daten und Kontrollen"

    static let atAGlanceBody = """
    ScooterCheck speichert Prüfungsdaten, Fotos und zugehörige Protokolldateien lokal auf diesem iPhone (App-Sandbox / Application Support).

    Es gibt in dieser App-Version kein Benutzerkonto und keinen App-eigenen Server, der deine Prüfungen oder Fotos entgegennimmt.

    Einzige vom Code ausgehende Netzwerkabfrage: optionaler Download einer öffentlichen Firmware-Sollkatalog-Datei von GitHub (raw.githubusercontent.com). Dabei werden keine Prüfungs- oder Fotodaten hochgeladen.

    Standort- und Bewegungsdaten werden nur während „E-Scooter finden“ im Arbeitsspeicher ausgewertet und nicht in die Prüfungsablage geschrieben.
    """

    // MARK: - Hub navigation

    enum Topic: String, CaseIterable, Identifiable, Hashable {
        case policy
        case processedData
        case localStorage
        case camera
        case bluetooth
        case location
        case externalServices
        case sharing
        case retention
        case permissions
        case rights

        var id: String { rawValue }

        var title: String {
            switch self {
            case .policy: return "Datenschutzerklärung"
            case .processedData: return "Verarbeitete Daten"
            case .localStorage: return "Lokale Daten"
            case .camera: return "Kamera & Fotos"
            case .bluetooth: return "Bluetooth"
            case .location: return "Standort"
            case .externalServices: return "Externe Dienste"
            case .sharing: return "Daten teilen"
            case .retention: return "Speicherung & Löschen"
            case .permissions: return "App-Berechtigungen"
            case .rights: return "Deine Datenschutzrechte"
            }
        }

        var symbolName: String {
            switch self {
            case .policy: return "doc.text"
            case .processedData: return "list.bullet.rectangle"
            case .localStorage: return "internaldrive"
            case .camera: return "camera"
            case .bluetooth: return "antenna.radiowaves.left.and.right"
            case .location: return "location"
            case .externalServices: return "network"
            case .sharing: return "square.and.arrow.up"
            case .retention: return "trash"
            case .permissions: return "switch.2"
            case .rights: return "person.crop.circle.badge.questionmark"
            }
        }
    }

    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let paragraphs: [String]
    }

    static func sections(for topic: Topic) -> [Section] {
        switch topic {
        case .policy: return policySections
        case .processedData: return processedDataSections
        case .localStorage: return localStorageSections
        case .camera: return cameraSections
        case .bluetooth: return bluetoothSections
        case .location: return locationSections
        case .externalServices: return externalServicesSections
        case .sharing: return sharingSections
        case .retention: return retentionSections
        case .permissions: return permissionsSections
        case .rights: return rightsSections
        }
    }

    // MARK: - Datenschutzerklärung (Art. 13-orientiert, nur belegte Fakten)

    private static let policySections: [Section] = [
        Section(
            title: "Verantwortlicher",
            paragraphs: [
                "Aus dem App-Copyright ergibt sich als Anbieterhinweis: \(copyrightHolderName).",
                "Vollständige Kontaktdaten gemäß Art. 13 Abs. 1 lit. a DSGVO (Anschrift, erreichbare E-Mail oder vergleichbarer Kontakt) sind in dieser App-Version nicht hinterlegt und dürfen hier nicht erfunden werden.",
                "Sobald Anschrift und Kontakt feststehen, sind sie hier nachzutragen. Bis dahin: Kontaktaufnahme über die Kontaktmöglichkeit des App-Anbieters im Apple App Store.",
                "Ein Datenschutzbeauftragter ist in der App nicht ausgewiesen."
            ]
        ),
        Section(
            title: "Zwecke der Verarbeitung",
            paragraphs: [
                "Auslesen und Bewerten technischer Daten kompatibler E-Scooter per Bluetooth (nur lesend).",
                "Lokale Speicherung von Prüfberichten (PDF/JSON), optionaler Zuordnung (z. B. Kennzeichen/Name) und Fotos zur Dokumentation und Wiedererkennung.",
                "Wiedererkennung zuvor geprüfter Scooter über lokal gespeicherte Serien-/Advertisement- und BLE-Peripheral-Kennungen.",
                "Optionale Richtungsschätzung unter „E-Scooter finden“ anhand von Bluetooth-Signalstärke sowie Standort-/Bewegungssensoren während der aktiven Suche.",
                "Optionaler Abruf eines öffentlichen Firmware-Sollkatalogs zur Aktualisierung von Vergleichsdaten."
            ]
        ),
        Section(
            title: "Kategorien personenbezogener Daten",
            paragraphs: [
                "Technische Scooter-/Diagnosedaten (u. a. Seriennummern, Firmwarestände, Register-/Board-Werte, BLE-Gerätenamen und -UUIDs), soweit auslesbar.",
                "Optionale Subject-Angaben, die du eingibst (Kennzeichen, Name, Geburtsdatum).",
                "Fotos, die du einer Prüfung zuordnest (Kamera oder Mediathek).",
                "App-Einstellungen und lokal gespeicherte Notizen zu Soft-Unlock-Kombinationen (UserDefaults), sofern genutzt.",
                "Während „E-Scooter finden“: Standort-, Heading- und Bewegungsdaten nur im Arbeitsspeicher der laufenden Sitzung.",
                "Keine Benutzerkonten; keine serverseitigen Profil-/Account-Daten in dieser App-Version."
            ]
        ),
        Section(
            title: "Rechtsgrundlagen",
            paragraphs: [
                "Nutzung der App-Funktionen auf deine Veranlassung (Vertrag bzw. vorvertragliche Maßnahmen bzw. berechtigtes Interesse an der technischen Diagnose — konkrete Einordnung hängt vom Einsatzkontext ab, z. B. privat oder beruflich).",
                "Geräteberechtigungen (Bluetooth, Kamera, Fotos, Standort, Bewegung) werden über das iOS-System erteilt; ohne Freigabe bleiben die betreffenden Funktionen eingeschränkt oder deaktiviert.",
                "Eine gesonderte Einwilligung für Analytics, Tracking oder KI-Cloud-Verarbeitung ist nicht vorgesehen, weil diese Dienste in der App nicht eingebunden sind."
            ]
        ),
        Section(
            title: "Empfänger / Auftragsverarbeiter / Drittländer",
            paragraphs: [
                "Prüfungsdaten und Fotos werden nicht an einen App-Backend-Server übermittelt.",
                "Beim Abruf des Firmware-Katalogs kontaktiert die App den Host raw.githubusercontent.com (GitHub). Es werden Katalogdaten heruntergeladen; Prüfungs-/Fotodaten werden dabei nicht hochgeladen. GitHub kann Server außerhalb der EU/des EWR betreiben; Details ergeben sich aus den Angaben von GitHub.",
                "Wenn du „Teilen“ nutzt, entscheidest du selbst über Empfänger (AirDrop, Mail, Dateien, andere Apps). Das ist keine automatische Weitergabe durch die App.",
                "Weitere Analytics-, Crash-Reporting-, Authentifizierungs- oder KI-SDKs sind im Xcode-Projekt nicht eingebunden."
            ]
        ),
        Section(
            title: "Speicherdauer",
            paragraphs: [
                "Lokale Prüfungen und Fotos bleiben gespeichert, bis du sie in der App endgültig löschst oder die App bzw. deren Daten vom Gerät entfernst.",
                "Archivieren entfernt Daten nicht; es blendet Einträge nur aus der aktiven Liste aus.",
                "Standort-/Bewegungswerte der Scootersuche werden nicht dauerhaft in der Prüfungsablage gespeichert.",
                "iCloud-/Geräte-Backups des Betriebssystems können App-Daten mit sichern, sofern auf dem Gerät aktiviert — das steuert Apple/iOS, nicht ein App-Upload."
            ]
        ),
        Section(
            title: "Pflicht zur Bereitstellung",
            paragraphs: [
                "Die App ist ohne Konto nutzbar. Bluetooth ist für „E-Scooter auslesen“ und „E-Scooter finden“ erforderlich; Kamera/Fotos nur für Bildfunktionen; Standort/Bewegung nur für die Find-Funktionen.",
                "Ohne die jeweilige Berechtigung funktionieren andere Bereiche der App weiter, soweit sie die Berechtigung nicht benötigen."
            ]
        ),
        Section(
            title: "Automatisierte Entscheidungen / Profiling",
            paragraphs: [
                "Die App bewertet ausgelesene Scooter-Daten lokal anhand fester Regeln/Kataloge und zeigt ein Ergebnis an. Es findet keine automatisierte Entscheidung mit Rechtswirkung im Sinne von Art. 22 DSGVO über dich als Person statt und kein Profiling zu Werbe-/Tracking-Zwecken."
            ]
        ),
        Section(
            title: "Herkunft der Daten",
            paragraphs: [
                "Daten stammen von dir (Eingaben, Fotos), vom verbundenen Scooter (BLE-Auslese) bzw. — beim Katalogabruf — aus der öffentlichen JSON-Datei im GitHub-Repository."
            ]
        ),
        Section(
            title: "Betroffenenrechte & Beschwerde",
            paragraphs: [
                "Dir stehen die Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit (soweit einschlägig), Widerspruch (soweit einschlägig) sowie Widerruf erteilter Einwilligungen zu.",
                "Du hast das Recht, dich bei einer Datenschutzaufsichtsbehörde zu beschweren. Die konkret zuständige Behörde richtet sich nach dem Sitz des Verantwortlichen — dieser Sitz ist in der App derzeit nicht angegeben; daher wird hier keine Behörde fest eingetragen.",
                "Siehe auch den Bereich „Deine Datenschutzrechte“."
            ]
        )
    ]

    private static let processedDataSections: [Section] = [
        Section(
            title: "Kontroll-/Prüfungsdaten",
            paragraphs: [
                "Enthalten u. a. Protokollnummer, Zeitstempel, Profil/Modellfamilie, Bewertungsergebnis, Score, optionale Zuordnungstexte.",
                "Zweck: Dokumentation und erneutes Öffnen/Teilen der Prüfung.",
                "Speicherort: lokal auf dem Gerät. Verlassen das Gerät nur, wenn du teilst."
            ]
        ),
        Section(
            title: "Fahrzeug-/Scooterdaten",
            paragraphs: [
                "Seriennummern, Firmwarestände, Register/Boards, BLE-Name, BLE-Peripheral-UUID, technische Messwerte — soweit auslesbar.",
                "Zweck: Diagnose, Vergleich mit Sollwerten, Wiedererkennung bekannter Scooter.",
                "Speicherort: lokal in der Prüfungsablage bzw. Einstellungen. Kein Upload an ein App-Backend."
            ]
        ),
        Section(
            title: "Bilder",
            paragraphs: [
                "Kamera- oder Mediathek-Fotos inkl. Titelbild/Vorschaubild und JPEG-Dateien im Prüfungsordner.",
                "Zweck: visuelle Dokumentation und Wiedererkennung in der Übersicht.",
                "Speicherort: lokal. Kein automatischer Upload."
            ]
        ),
        Section(
            title: "Standort & Bewegung",
            paragraphs: [
                "Während „E-Scooter finden“: genauer Standort (When-In-Use), Heading, Schritt-/Motion-Daten zur Richtungsschätzung.",
                "Zweck: Signalstärke-Änderung während deiner Bewegung auswerten.",
                "Speicherung: nur flüchtig während der aktiven Suche — nicht als Teil der Prüfungsablage.",
                "Keine Übertragung an App-Server."
            ]
        ),
        Section(
            title: "Diagnose-/Nutzungsanalytik & KI",
            paragraphs: [
                "In dieser App-Version sind keine Analytics-, Crash-Reporting- oder KI-Cloud-Dienste eingebunden.",
                "Es werden daher keine Nutzungsprofile an solche Anbieter gesendet und keine Bilder an KI-Dienste übertragen."
            ]
        )
    ]

    private static let localStorageSections: [Section] = [
        Section(
            title: "Was lokal gespeichert wird",
            paragraphs: [
                "Prüfungsindex und Session-/Protokollpakete unter Application Support (ScooterCheck/History), inkl. PDF/JSON und Fotoordner.",
                "UserDefaults: u. a. Soft-Unlock-Einstellungen/-Kombos, optionaler BLE-Session-Schlüssel, Metadaten zum Firmware-Katalog-Cache.",
                "Cache der heruntergeladenen Firmware-Katalog-JSON."
            ]
        ),
        Section(
            title: "Archivieren vs. Löschen",
            paragraphs: [
                "Archivieren setzt nur ein Archiv-Flag — alle Daten und Fotos bleiben erhalten und sind unter „Archiv“ sichtbar.",
                "Endgültiges Löschen entfernt den Eintrag und den zugehörigen Ordner (inkl. Fotos und Protokolldateien) aus dem aktiven App-Datenbestand."
            ]
        ),
        Section(
            title: "Backups",
            paragraphs: [
                "Wenn auf dem iPhone Geräte- oder iCloud-Backup aktiv ist, kann iOS App-Daten mit sichern. Das ist keine von ScooterCheck initiierte Cloud-Synchronisation von Prüfungen."
            ]
        )
    ]

    private static let cameraSections: [Section] = [
        Section(
            title: "Warum Kamera & Fotos?",
            paragraphs: [
                "Damit du Fotos zu einer Prüfung hinzufügen und ein Titelbild für die Übersicht festlegen kannst.",
                "Zugriff erst nach iOS-Berechtigung. Ohne Freigabe bleiben Auslese und Prüfungen ohne Bildfunktion nutzbar."
            ]
        ),
        Section(
            title: "Speicherung",
            paragraphs: [
                "Bilder werden der jeweiligen Prüfung lokal zugeordnet (Original + Vorschaubild).",
                "Kein automatischer Upload. Teilen von Bildern erfolgt nur über die von dir gestartete Teilen-Funktion."
            ]
        )
    ]

    private static let bluetoothSections: [Section] = [
        Section(
            title: "Verwendung",
            paragraphs: [
                "Core Bluetooth erkennt und verbindet kompatible Scooter, liest Diagnosedaten und unterstützt Identifizieren/Finden.",
                "Gespeichert werden können u. a. BLE-Peripheral-UUID und Advertisement-/Serienname zur lokalen Wiedererkennung nach erfolgreicher Validierung sowie Diagnosedaten in der Prüfung.",
                "Bluetooth wird nicht für Tracking oder Werbung genutzt."
            ]
        ),
        Section(
            title: "BLE-Geräteidentifikation",
            paragraphs: [
                "Während der BLE-Suche wertet ScooterCheck lokal verfügbare Advertisement-Merkmale aus (u. a. Company Identifier, Service-UUIDs, Namensmuster).",
                "Die lokale Herstellerliste basiert auf Bluetooth-SIG Assigned Numbers. Eine Company Identifier benennt die registrierte Organisation — nicht automatisch Geräteklasse oder Modell.",
                "Online-Identifikation ist optional und standardmäßig aus. Erst nach ausdrücklicher Zustimmung werden datensparsame technische Kennungen an ein konfiguriertes Backend gesendet — keine Standorte, keine vollständigen Scan-Historien, keine ungefragte Übertragung aller Geräte.",
                "Ohne konfiguriertes Backend findet keine Online-Recherche statt; die lokale Analyse bleibt nutzbar.",
                "Gespeicherte Online-Cache-Einträge und Analyseergebnisse kannst du in den App-Daten bzw. über „Analyse-Cache löschen“ entfernen."
            ]
        )
    ]

    private static let locationSections: [Section] = [
        Section(
            title: "Wann wird Standort genutzt?",
            paragraphs: [
                "Nur während der Funktion „E-Scooter finden“ (When In Use), mit hoher Genauigkeit zur Auswertung von Positions-/Heading-Änderungen zusammen mit RSSI.",
                "Ohne Standortfreigabe ist die Richtungsschätzung eingeschränkt; die übrige App bleibt nutzbar.",
                "Standortdaten werden nicht in die Prüfungsablage geschrieben und nicht an App-Server gesendet."
            ]
        )
    ]

    private static let externalServicesSections: [Section] = [
        Section(
            title: "Eingebundene Frameworks (Apple)",
            paragraphs: [
                "Core Bluetooth, Core Location, Core Motion, PhotosUI / UIKit-Kamera — Systemframeworks, keine Drittanbieter-Analytics-SDKs."
            ]
        ),
        Section(
            title: "GitHub (Firmware-Katalog)",
            paragraphs: [
                "Anbieter/Hosting: GitHub (raw.githubusercontent.com), Abruf von catalogs/stock-firmware.json.",
                "Zweck: optionale Aktualisierung von Soll-Firmwareständen.",
                "Verarbeitete Daten beim Abruf: übliche Verbindungsdaten (IP usw.) auf Seiten des Hosts; die App lädt nur die Katalogdatei und sendet keine Prüfungsinhalte.",
                "Datenschutzhinweise des Anbieters: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement",
                "Keine weiteren Analytics-, Crash-, Auth-, Cloud-Storage- oder KI-Anbieter im Projekt verknüpft."
            ]
        )
    ]

    private static let sharingSections: [Section] = [
        Section(
            title: "iOS Share Sheet",
            paragraphs: [
                "Über „Teilen“ öffnet ScooterCheck den nativen iOS-Share-Sheet (PDF/JSON und ggf. Fotos).",
                "Eine Weitergabe erfolgt erst, wenn du selbst „Teilen“ tippst und einen Empfänger oder eine andere App wählst (z. B. AirDrop, Nachrichten, Mail, Dateien).",
                "Die App teilt Kontrolldaten nicht automatisch im Hintergrund."
            ]
        ),
        Section(
            title: "Datenweitergabe im Übrigen",
            paragraphs: [
                "Abgesehen vom optionalen Katalog-Download und von dir ausgelösten Teilen gibt es keine Weitergabe von Prüfungsdaten an Dritte durch die App."
            ]
        )
    ]

    private static let retentionSections: [Section] = [
        Section(
            title: "Speicherung",
            paragraphs: [
                "Speicherung ist nutzergesteuert: Einträge bleiben, bis du sie löschst oder App-Daten entfernst.",
                "Archivieren = ausblenden aus „Aktiv“, keine Löschung.",
                "Löschen = dauerhaftes Entfernen inkl. zugehöriger Bilder/Dateien aus dem App-Datenbestand (Backups des Betriebssystems können älter sein)."
            ]
        )
    ]

    private static let permissionsSections: [Section] = [
        Section(
            title: "Bluetooth",
            paragraphs: [
                "Zweck: Scooter erkennen, verbinden, Diagnosedaten lesen, Wiederfinden unterstützen."
            ]
        ),
        Section(
            title: "Kamera",
            paragraphs: [
                "Zweck: Fotos zu einer Prüfung aufnehmen."
            ]
        ),
        Section(
            title: "Fotos / Mediathek",
            paragraphs: [
                "Zweck: bestehende Bilder einer Prüfung hinzufügen."
            ]
        ),
        Section(
            title: "Standort (When In Use)",
            paragraphs: [
                "Zweck: nur „E-Scooter finden“ — Signaländerungen während der Bewegung auswerten."
            ]
        ),
        Section(
            title: "Bewegung / Motion",
            paragraphs: [
                "Zweck: Richtungsschätzung während „E-Scooter finden“ robuster machen."
            ]
        )
    ]

    private static let rightsSections: [Section] = [
        Section(
            title: "Deine Rechte",
            paragraphs: [
                "Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit (soweit einschlägig), Widerspruch (soweit einschlägig), Widerruf von Einwilligungen, Beschwerde bei einer Aufsichtsbehörde.",
                "Lokale Prüfungsdaten kannst du in der App einsehen, korrigieren (Zuordnung), archivieren oder endgültig löschen.",
                "Für Anfragen an den Verantwortlichen: Kontaktdaten sind in der App noch nicht hinterlegt — nutze die Kontaktmöglichkeit im App-Store-Eintrag des Anbieters, bis hier eine erreichbare Adresse ergänzt ist."
            ]
        )
    ]
}
