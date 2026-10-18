export const navLinks = [
  { href: "/#technologie", label: "Technologie" },
  { href: "/#funktionen", label: "Funktionen" },
  { href: "/#ablauf", label: "So funktioniert's" },
  { href: "/#faq", label: "FAQ" },
  { href: "/#app", label: "App entdecken" },
] as const;

export const models = [
  "Ninebot ZT3 Pro",
  "Ninebot Max G30",
  "Ninebot Max G3 / MAX3",
  "Ninebot F-Serie",
  "Ninebot D-Serie",
  "Xiaomi M365 / Pro 2",
  "Xiaomi Scooter 3 / 4",
] as const;

export const howSteps = [
  {
    title: "Kompatiblen E-Scooter suchen",
    text: "ScooterCheck listet BLE-Geräte in Reichweite — auch solche, die unter iPhone-Einstellungen → Bluetooth oft fehlen.",
  },
  {
    title: "Verbindung herstellen",
    text: "Nach Auswahl folgt der Handshake. Bei Ninebot Enc2 kann ein Tastendruck am Power-Knopf nötig sein.",
  },
  {
    title: "Verfügbare Daten analysieren",
    text: "Die App liest verfügbare Register aus und erkennt den BLE-Stack automatisch (Ninebot Enc2 / Xiaomi).",
  },
  {
    title: "Ergebnisse bewerten",
    text: "Auslesewerte werden mit Sollwerten des gewählten Profils verglichen — inkl. Erläuterung je Fakt.",
  },
  {
    title: "Prüfung dokumentieren",
    text: "Ergebnis als PDF und JSON speichern. Protokolle bleiben offline auf dem Gerät.",
  },
] as const;

export const diagnosticsItems = [
  {
    title: "Firmwareinformationen",
    text: "Ausgelesene Stände und Hinweise gegenüber typischen Stock-Konfigurationen.",
  },
  {
    title: "Seriennummernabgleich",
    text: "Zuordnung zu werkseitigen Präfixen und Modellfamilie, soweit verfügbar.",
  },
  {
    title: "Regionsinformationen",
    text: "Marktvarianten D 20 / E 25 km/h steuern Sollwerte und Bewertungsgrenzen.",
  },
  {
    title: "Geschwindigkeitsparameter",
    text: "Limit-bezogene Register im Vergleich zum Sollbereich des Profils.",
  },
  {
    title: "Technische Auffälligkeiten",
    text: "Systematische Bewertung: regelkonform, abweichend oder erheblich abweichend.",
  },
  {
    title: "Dokumentation",
    text: "PDF-Bericht und maschinenlesbares JSON für Akte oder Weitergabe.",
  },
] as const;

export const demoVerdicts = [
  {
    tone: "stock" as const,
    label: "Keine Auffälligkeit erkannt",
    hint: "Beispiel · Auslesewerte im Sollbereich",
  },
  {
    tone: "watch" as const,
    label: "Prüfung erforderlich",
    hint: "Beispiel · Abweichung, Bewertung unklar",
  },
  {
    tone: "tuned" as const,
    label: "Technische Abweichung festgestellt",
    hint: "Beispiel · Erhebliche Abweichung vom Soll",
  },
];

export const faqItems = [
  {
    q: "Was ist ScooterCheck?",
    a: "ScooterCheck ist eine native iOS-App zur nur lesenden Bluetooth-Diagnose gängiger E-Scooter. Sie sucht Geräte, liest verfügbare Daten aus, bewertet sie gegen Sollprofile und speichert Berichte als PDF und JSON.",
  },
  {
    q: "Welche E-Scooter werden unterstützt?",
    a: "Unter anderem Ninebot ZT3 Pro, Max G30, Max G3/MAX3, F- und D-Serie sowie Xiaomi M365/Pro 2 und Scooter 3/4. Der BLE-Stack wird automatisch erkannt. Neuere Xiaomi-Modelle mit 55 AB sind ggf. nicht auslesbar.",
  },
  {
    q: "Welche Daten können ausgelesen werden?",
    a: "Je nach Modell und Verbindungsstatus: Limit-bezogene Parameter, Seriennummernhinweise, Firmware-bezogene Informationen und weitere Register, die das Protokoll freigibt. Nicht jeder Wert ist bei jedem Gerät verfügbar.",
  },
  {
    q: "Wird der Scooter verändert?",
    a: "Nein. ScooterCheck ändert keine Limits, flasht keine Firmware und bietet keine Unlock-Funktionen. Die Verbindung dient dem Auslesen und Dokumentieren.",
  },
  {
    q: "Kann jede Manipulation erkannt werden?",
    a: "Nein. Die App bewertet verfügbare Auslesewerte gegen Sollprofile. Nicht jede Manipulation hinterlässt lesbare Spuren, und fehlende Daten werden als nicht feststellbar ausgewiesen — keine pauschale Garantie.",
  },
  {
    q: "Benötige ich eine Internetverbindung?",
    a: "Für die Prüfung und die Offline-Protokollhistorie auf dem Gerät nicht. Teilen/Export nutzt die iOS-Freigabe; eine Cloud-Synchronisation ist nicht Bestandteil der beschriebenen Funktionen.",
  },
  {
    q: "Wie werden Daten verarbeitet?",
    a: "Abgeschlossene Prüfungen werden offline auf dem Gerät gespeichert. Details zur Verarbeitung folgen in der Datenschutzerklärung — dort sind rechtliche Angaben verbindlich.",
  },
] as const;

export const techPoints = [
  { label: "Firmware", detail: "Versionen & Auffälligkeiten" },
  { label: "Controller", detail: "Register & Stack-Erkennung" },
  { label: "Batterie", detail: "Soweit über BLE lesbar" },
  { label: "Geschwindigkeit", detail: "Soll D 20 / E 25 km/h" },
] as const;
