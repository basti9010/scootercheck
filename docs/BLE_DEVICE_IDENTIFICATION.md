# BLE-Geräteidentifikation

Automatische, nachvollziehbare Identifikation von BLE-Geräten in ScooterCheck — lokal zuerst, Online nur nach Zustimmung.

## Architektur

```
BleClient.didDiscover
  → BLEIdentificationService.ingest(ScannedDevice)
      → BLEIdentificationEngine (lokal, synchron)
      → optional OnlineIdentificationProvider (Backend-URL)
      → IdentificationResultMerger
  → UI / Radar / Listen-Labels
```

Kein zweiter BLE-Scan. Dieselben Discovery-Events wie Scan, Radar, Wächter und Signal-Finder.

| Datei | Rolle |
|-------|--------|
| `BLEIdentity/BLEIdentificationModels.swift` | Result, Evidence, Confidence, Settings, Manufacturer-Parsing |
| `BLEIdentity/BluetoothCompanyCatalog.swift` | SIG Company-Identifier-Katalog + bekannte Service-UUIDs + Vendor-Pattern-Katalog |
| `BLEIdentity/BLEIdentificationEngine.swift` | Regelbasierte Offline-Klassifikation |
| `BLEIdentity/BLEIdentificationService.swift` | Cache, Opt-in-Online, Zeitbeobachtung, Listen-Hilfen, Merger |
| `BLEIdentity/OnlineIdentificationProvider.swift` | Datensparsames Backend (kein Scraping, keine Fake-Treffer) |
| `BLEIdentity/BLEGattDeepAnalysis.swift` | Nutzerausgelöste, nur-lesende GATT-Analyse |
| `BLEIdentity/BLEDeviceAnalysisView.swift` | Geräteanalyse-UI |
| `bluetooth_company_identifiers.json` | Bundled Company IDs (Bluetooth SIG Assigned Numbers) |
| `ble_vendor_patterns.json` | Versionierte, dokumentierte herstellerspezifische Muster |

## Identifikationsebenen

1. **Hersteller** — Company Identifier → SIG-Name (Organisation, nicht Produktklasse)
2. **Geräteklasse** — nur mit zusätzlichen technischen Merkmalen (nie nur aus Hersteller)
3. **Modell** — nur bei dokumentierten Namens-/Serial-Hinweisen (`BleModelHint`) oder belastbarer Kombi
4. **Kommunikationsprofil** — z. B. Ninebot UART, Nordic UART, Device Information

Confidence: `high` | `medium` | `low` | `unknown` (qualitativ, keine Pseudo-Prozentwerte).

## Fingerprint

`BLEDeviceFingerprint` / `BLEFingerprintService` (in `BLEAnalysisCore.swift`):

- Merkmale: Manufacturer Data (kompakt normalisiert), Company ID, Service UUIDs, Service Data, Advertising-Struktur, TX Power, Connectable, optional Name
- **RSSI ist kein Identitätsmerkmal**
- Ähnlichkeit: hoch / mittel / gering / keine
- Ähnlicher Fingerprint ≠ denselbe physische Gerät und ≠ Modellzuordnung
- Wächter nutzt Fingerprints zur Wiedererkennung, ohne Geräte automatisch zusammenzuführen

## Scooter / Radar

Radar-Alarme nur bei `radarEligibleScooter == true`:

- Ninebot-UART und/oder Ninebot-CID **plus** UART/Modell
- Xiaomi nur mit zusätzlichen Scooter-Hinweisen (nicht CID allein)
- Online-Scooter-Vorschlag allein **nie** radar-eligible

Samsung-/Apple-Organisation → nicht als Scooter.

## Online-Recherche

- Standard: **aus**
- Zustimmung erklärt übertragene Felder (CID, Service-UUIDs, Namenspräfix, Structure-Key)
- Endpoint: Info.plist `BLE_IDENTIFICATION_ENDPOINT` oder UserDefaults `bleIdentification.endpoint`
- Ohne Endpoint: ehrliche Meldung, keine simulierten Treffer
- Keine API-Keys in der App, kein Scraping, keine Standorte/Scan-Historien
- Cache mit Quelle/Datum; Einträge älter als 90 Tage werden verworfen

## Zeitliche Beobachtung

„30 Sekunden analysieren“ sammelt unterschiedliche Advertising-Signaturen desselben Peripheral-IDs und erzwingt danach eine Neuanalyse. Es werden keine Felder erfunden, die iOS nicht liefert.

## GATT-Analyse

Nur nach Nutzeraktion. Liest sichere Characteristics (u. a. Device Information). Keine Schreibbefehle, kein Auth-Bypass. Bei Ablehnung: Fehlermeldung, keine Geräteänderung.

## Datenschutz

Siehe `PrivacyContent` → Bluetooth → „BLE-Geräteidentifikation“. Cache löschbar in Signal-Finder-Optionen. Online-Identifikation und BLE-Suche sind unabhängig steuerbar.

## Tests

`BLEIdentificationTests`: Manufacturer-Parsing, Katalog, Samsung≠Scooter, Ninebot-UART, CID allein, generischer Nordic UART, Fingerprint-Spaces, UUID-Normalisierung, Online-Merge, Evidence, Vendor-Patterns, Fingerprint-Nicht-Zusammenführung.

## iOS-Einschränkungen

- Keine fremden Bluetooth-MACs — nur iOS-Peripheral-UUID (nicht globale Hardware-ID)
- Advertisement-Felder nur, wenn iOS sie liefert — nichts erfinden
- Manufacturer-Hex kann Leerzeichen enthalten (Parsing normalisiert)
- Overflow-/Solicited-Service-UUIDs nur, wenn CoreBluetooth sie im Advertisement bereitstellt

## Offene Voraussetzungen

- Produktiv nutzbare Online-Recherche erfordert ein konfiguriertes Backend (`BLE_IDENTIFICATION_ENDPOINT`); ohne Endpoint bleibt nur die lokale Engine aktiv
- SIG Company-JSON ist ein Snapshot und sollte periodisch aus den Assigned Numbers aktualisiert werden
