#!/usr/bin/env python3
"""Generate ScooterCheck police technical training PowerPoint (16:9)."""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_AUTO_SHAPE_TYPE, MSO_CONNECTOR
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
OUT = ROOT / "ScooterCheck_Technikschulung_Polizei.pptx"

# ScooterCheck CI
BG = RGBColor(0x12, 0x16, 0x1C)
ACCENT = RGBColor(0x6B, 0xDB, 0xC2)
TEXT = RGBColor(0xF5, 0xF7, 0xF8)
MUTED = RGBColor(0x8B, 0x94, 0x9E)
CARD = RGBColor(0x20, 0x26, 0x2D)
BORDER = RGBColor(0x2C, 0x34, 0x3D)
WARN = RGBColor(0xF2, 0x6B, 0x66)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)

SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)


def _set_run(run, size=18, bold=False, color=TEXT, name="Helvetica Neue"):
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = name


def _fill_solid(shape, color: RGBColor):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()


def _card(slide, left, top, width, height, fill=CARD):
    s = slide.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE, left, top, width, height)
    _fill_solid(s, fill)
    s.line.color.rgb = BORDER
    s.line.width = Pt(1)
    # soft radius
    try:
        s.adjustments[0] = 0.08
    except Exception:
        pass
    return s


def _textbox(slide, left, top, width, height, text, size=18, bold=False, color=TEXT, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP):
    box = slide.shapes.add_textbox(left, top, width, height)
    tf = box.text_frame
    tf.word_wrap = True
    tf.auto_size = None
    try:
        tf._txBody.bodyPr.set(qn("a:anchor"), "t" if anchor == MSO_ANCHOR.TOP else "ctr")
    except Exception:
        pass
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    _set_run(run, size=size, bold=bold, color=color)
    return box


def _add_para(tf, text, size=16, bold=False, color=TEXT, space_before=6, align=PP_ALIGN.LEFT):
    p = tf.add_paragraph()
    p.alignment = align
    p.space_before = Pt(space_before)
    run = p.add_run()
    run.text = text
    _set_run(run, size=size, bold=bold, color=color)
    return p


def _notes(slide, text: str):
    notes = slide.notes_slide
    notes.notes_text_frame.text = text.strip()


def _bg(slide):
    fill = slide.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.RECTANGLE, 0, 0, SLIDE_W, SLIDE_H)
    _fill_solid(fill, BG)
    # send to back
    spTree = slide.shapes._spTree
    sp = fill._element
    spTree.remove(sp)
    spTree.insert(2, sp)


def _footer(slide, page: int, total: int):
    _textbox(slide, Inches(0.6), Inches(7.05), Inches(8), Inches(0.3),
             "ScooterCheck · Technische Fortbildung", size=10, color=MUTED)
    _textbox(slide, Inches(11.2), Inches(7.05), Inches(1.5), Inches(0.3),
             f"{page} / {total}", size=10, color=MUTED, align=PP_ALIGN.RIGHT)


def _logo(slide, left=Inches(11.6), top=Inches(0.28), w=Inches(1.2)):
    logo = ASSETS / "logo.png"
    if logo.exists():
        slide.shapes.add_picture(str(logo), left, top, width=w)


def _chip(slide, left, top, w, h, label, fill=None, text_color=BG):
    s = slide.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE, left, top, w, h)
    _fill_solid(s, fill or ACCENT)
    try:
        s.adjustments[0] = 0.35
    except Exception:
        pass
    tf = s.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    run = p.add_run()
    run.text = label
    _set_run(run, size=12, bold=True, color=text_color)
    return s


def _bullet_card(slide, left, top, width, height, title, bullets, title_size=16):
    _card(slide, left, top, width, height)
    box = _textbox(slide, left + Inches(0.22), top + Inches(0.18), width - Inches(0.4), Inches(0.4),
                   title, size=title_size, bold=True, color=ACCENT)
    tf = box.text_frame
    for b in bullets:
        _add_para(tf, "•  " + b, size=13, color=TEXT, space_before=8)


def new_slide(prs):
    blank = prs.slide_layouts[6]  # blank
    slide = prs.slides.add_slide(blank)
    _bg(slide)
    return slide


def build():
    prs = Presentation()
    prs.slide_width = SLIDE_W
    prs.slide_height = SLIDE_H
    slides_meta = []  # (builder fn) — we'll build sequentially and track total after

    # We'll collect note texts and page numbers as we go
    built = []

    def finish(slide, notes, title_for_toc=None):
        built.append(slide)
        _notes(slide, notes)
        return slide

    # ——— 1 Title ———
    s = new_slide(prs)
    if (ASSETS / "appicon.png").exists():
        s.shapes.add_picture(str(ASSETS / "appicon.png"), Inches(0.7), Inches(0.55), width=Inches(0.85))
    _logo(s)
    _textbox(s, Inches(0.7), Inches(2.1), Inches(12), Inches(1.2),
             "E-Scooter-Tuning verstehen,\nManipulationen erkennen und analysieren",
             size=36, bold=True, color=TEXT)
    _textbox(s, Inches(0.7), Inches(4.5), Inches(11), Inches(0.5),
             "Technische Fortbildung für den Polizeidienst", size=20, color=ACCENT)
    _textbox(s, Inches(0.7), Inches(5.2), Inches(11), Inches(0.6),
             "ScooterCheck · Bluetooth-gestützte Diagnose & EvidenceEngine\n45–60 Minuten inkl. Live-Demo",
             size=14, color=MUTED)
    finish(s, """
Begrüßung. Rahmen: reine Technikschulung — keine Rechtsbelehrung.
Ziel: Nachvollziehbarkeit technischer Zusammenhänge (Motorsteuerung, Firmware, BLE, Persistenz) und realistische Einordnung der ScooterCheck-Analyse.
Betonen: Keine Anleitung zum Tuning. Fokus Erkennung, Spurenlage, Grenzen.
""")

    # ——— 2 Ziele ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.4), Inches(11), Inches(0.6), "Lernziele", size=32, bold=True)
    goals = [
        ("Verstehen", "Wie Geschwindigkeit elektronisch begrenzt wird"),
        ("Unterscheiden", "Software-, Firmware-, Session-, Lizenz- und Hardware-Tuning"),
        ("Einordnen", "Flüchtige vs. persistente Veränderungen"),
        ("Analysieren", "Was BLE leisten kann — und was nicht"),
        ("Anwenden", "ScooterCheck strukturiert Suche, Diagnose und Dokumentation"),
    ]
    for i, (t, d) in enumerate(goals):
        y = Inches(1.3) + Inches(i * 0.95)
        _card(s, Inches(0.7), y, Inches(11.9), Inches(0.82))
        _textbox(s, Inches(1.0), y + Inches(0.15), Inches(2.2), Inches(0.5), t, size=18, bold=True, color=ACCENT)
        _textbox(s, Inches(3.4), y + Inches(0.2), Inches(8.8), Inches(0.5), d, size=16, color=TEXT)
    finish(s, """
Kurz die fünf Lernziele vorlesen. Ankündigen: Zuerst Physik/Elektronik, dann Tuningarten, dann BLE, dann Tool.
Frage an die Runde: Wer hat schon mit Scooter-Apps oder Diagnosegeräten gearbeitet?
""")

    # ——— 3 Opening ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(2.0), Inches(12), Inches(1.5),
             "Was passiert technisch,\nwenn ein E-Scooter plötzlich schneller fährt\nals vorgesehen?",
             size=30, bold=True, color=TEXT)
    _textbox(s, Inches(0.7), Inches(5.2), Inches(11), Inches(0.6),
             "Die Antwort liegt selten in „mehr Leistung“ allein —\nmeist in veränderten Steuerparametern, Firmware oder Hardware.",
             size=16, color=MUTED)
    finish(s, """
Einstiegsfrage stehen lassen (5–10 Sekunden). Dann: Der Motor kann oft mehr, als die Straße erlaubt — die Begrenzung ist elektronisch.
Überleitung: Um Manipulation zu verstehen, muss man den Regelkreis kennen.
""")

    # ——— 4 Divider Aufbau ———
    s = new_slide(prs)
    _chip(s, Inches(0.7), Inches(2.8), Inches(1.6), Inches(0.4), "Kapitel 1")
    _textbox(s, Inches(0.7), Inches(3.4), Inches(12), Inches(1),
             "Technischer Aufbau eines E-Scooters", size=34, bold=True)
    finish(s, "Kurzer Kapiteltrenner. Betonen: Architekturen unterscheiden sich (Ninebot/Segway, Xiaomi, KuKirin u. a.).")

    # ——— 5 Block diagram ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Typische Architektur (vereinfacht)", size=28, bold=True)

    boxes = [
        (0.7, 1.3, "Smartphone\nScooterCheck"),
        (3.3, 1.3, "BLE-Modul"),
        (5.9, 1.3, "MCU /\nController"),
        (8.5, 1.3, "BMS"),
        (11.0, 1.3, "Akku"),
        (5.9, 3.6, "Leistungs-\nstufe"),
        (5.9, 5.3, "Motor"),
        (2.5, 3.6, "Display /\nVCU*"),
        (9.3, 3.6, "Sensorik\n(Hall, Strom)"),
    ]
    for x, y, label in boxes:
        sh = slide_box = s.shapes.add_shape(
            MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(2.0), Inches(1.0)
        )
        _fill_solid(slide_box, CARD)
        slide_box.line.color.rgb = ACCENT
        slide_box.line.width = Pt(1.5)
        tf = slide_box.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.add_run()
        run.text = label
        _set_run(run, size=12, bold=True, color=TEXT)

    # arrows as text labels
    _textbox(s, Inches(2.7), Inches(1.55), Inches(0.6), Inches(0.4), "→", size=22, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(5.3), Inches(1.55), Inches(0.6), Inches(0.4), "→", size=22, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(7.95), Inches(1.55), Inches(0.6), Inches(0.4), "↔", size=22, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(10.5), Inches(1.55), Inches(0.5), Inches(0.4), "↔", size=22, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(6.5), Inches(2.5), Inches(0.6), Inches(0.9), "↓", size=22, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(6.5), Inches(4.7), Inches(0.6), Inches(0.5), "↓", size=22, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(0.7), Inches(6.5), Inches(11), Inches(0.4),
             "* VCU/Display nicht bei allen Modellen getrennt · Busse: UART / CAN / proprietär",
             size=12, color=MUTED)
    finish(s, """
Diagramm erklären von links nach rechts: App spricht nur mit BLE; BLE spricht mit MCU; MCU regelt Motor und tauscht mit BMS.
Varianten: Manche Billig-Scooter haben BLE und MCU auf einer Platine; Premium-Modelle trennen VCU/Display.
Frage: „Wo sitzt die Geschwindigkeitsbegrenzung?“ → typisch MCU-Firmware/Parameter, manchmal zusätzlich App-seitig.
""")

    # ——— 6 Components ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5), "Komponenten & Rollen", size=28, bold=True)
    items = [
        ("MCU / Controller", "Drehzahl, Strom, Fahrmodi, Limits, Kommunikation"),
        ("BMS", "Zellschutz, Ladezustand, oft eigene Firmware"),
        ("BLE-Modul", "Advertising, GATT, App-Protokoll — oft eigener Chip"),
        ("Firmware", "Programmcode auf MCU/BMS/BLE — versioniert"),
        ("Sensorik", "Hall/Encoder, Stromsensor, Temperatursensoren"),
        ("Display / VCU", "UI und ggf. zweite Steuerungsebene"),
    ]
    for i, (t, d) in enumerate(items):
        col = i % 2
        row = i // 2
        x = Inches(0.7) + Inches(col * 6.2)
        y = Inches(1.15) + Inches(row * 1.7)
        _card(s, x, y, Inches(5.9), Inches(1.45))
        _textbox(s, x + Inches(0.3), y + Inches(0.25), Inches(5.3), Inches(0.4), t, size=16, bold=True, color=ACCENT)
        _textbox(s, x + Inches(0.3), y + Inches(0.7), Inches(5.3), Inches(0.55), d, size=14, color=TEXT)
    finish(s, """
Wichtig: Firmware existiert oft mehrfach (MCU, BLE, BMS). Eine „Firmware“ in der App kann eine dieser Ebenen meinen.
BMS-Manipulation ist seltener Thema bei Geschwindigkeit, aber relevant bei Kapazitäts-/Sicherheitsanzeigen.
""")

    # ——— 7 Divider Speed ———
    s = new_slide(prs)
    _chip(s, Inches(0.7), Inches(2.8), Inches(1.6), Inches(0.4), "Kapitel 2")
    _textbox(s, Inches(0.7), Inches(3.4), Inches(12), Inches(1),
             "Wie wird Geschwindigkeit begrenzt?", size=34, bold=True)
    finish(s, "Überleitung: Begrenzung ≠ Motorleistung.")

    # ——— 8 Speed limit chain ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Regelkreis der Geschwindigkeitsbegrenzung", size=26, bold=True)
    steps = [
        "Soll-Limit\n(Firmware /\nParameter)",
        "Drehzahl-\nIstwert\n(Hall)",
        "Regler\n(MCU)",
        "Strom /\nPWM",
        "Motor &\nRad",
    ]
    for i, label in enumerate(steps):
        x = Inches(0.6) + Inches(i * 2.5)
        sh = s.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE, x, Inches(2.2), Inches(2.2), Inches(2.0))
        _fill_solid(sh, CARD)
        sh.line.color.rgb = ACCENT
        tf = sh.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.add_run()
        run.text = label
        _set_run(run, size=13, bold=True, color=TEXT)
        if i < len(steps) - 1:
            _textbox(s, x + Inches(2.15), Inches(2.9), Inches(0.4), Inches(0.4), "→", size=20, bold=True, color=ACCENT)
    _textbox(s, Inches(0.7), Inches(4.8), Inches(11.8), Inches(1.5),
             "Zusätzlich: Radumfang-Kalibrierung · Strom-/Leistungsgrenzen · Fahrmodus · regionale Profile.\n"
             "Die App sieht oft nur das Ergebnis (Limit-Parameter), nicht den gesamten Regelkreis.",
             size=15, color=MUTED)
    finish(s, """
Geschwindigkeit ≈ Drehzahl × Radumfang. Tuning ändert meist das Soll-Limit oder die Firmware-Logik, nicht den Radumfang.
Regionale Konfigurationen (EU/US/…) können unterschiedliche Limits speichern — das ist herstellerseitig vorgesehen, aber missbrauchbar.
""")

    # ——— 9 Three layers ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Drei Ebenen — nicht verwechseln", size=28, bold=True)
    layers = [
        ("Maximale Motorleistung", "Physikalisch möglich\n(Akku, Controller, Motor)", MUTED),
        ("Elektronisches Limit", "Firmware-/Parametergrenze\n(Sollwert im Regler)", ACCENT),
        ("Tatsächlich gefahren", "Umgebung, Last, Akku,\nFahrbahn, Nutzer", TEXT),
    ]
    for i, (t, d, c) in enumerate(layers):
        x = Inches(0.7) + Inches(i * 4.1)
        _card(s, x, Inches(1.5), Inches(3.9), Inches(4.2))
        _textbox(s, x + Inches(0.25), Inches(1.9), Inches(3.4), Inches(1.0), t, size=18, bold=True, color=c)
        _textbox(s, x + Inches(0.25), Inches(3.2), Inches(3.4), Inches(2.0), d, size=15, color=TEXT)
    finish(s, """
Kernbotschaft: Ein starker Motor ohne Limit-Änderung fährt nicht automatisch unzulässig schnell — und ein Limit-Wert in der Diagnose ist nicht die gefahrene Geschwindigkeit.
Peak-Werte in der Historie brauchen Kontext (Hang, Messung, Referenzprofil).
""")

    # ——— 10 Divider Tuning ———
    s = new_slide(prs)
    _chip(s, Inches(0.7), Inches(2.8), Inches(1.6), Inches(0.4), "Kapitel 3")
    _textbox(s, Inches(0.7), Inches(3.4), Inches(12), Inches(1),
             "Arten von E-Scooter-Tuning", size=34, bold=True)
    _textbox(s, Inches(0.7), Inches(4.5), Inches(11), Inches(0.5),
             "Methoden getrennt betrachten — keine Vermischung", size=16, color=MUTED)
    finish(s, "Ankündigen: fünf methodische Kästen. Keine Schritt-für-Schritt-Anleitungen.")

    # ——— 11 Software ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "1 · Software- / Parameter-Tuning", size=26, bold=True, color=ACCENT)
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(5.9), Inches(5.2), "Was & wo", [
        "Änderung von Konfigurationswerten",
        "Geschwindigkeitslimits, Modi, Region",
        "Ort: NVM / Flash der MCU (oder App-Spiegel)",
        "Firmware-Binärcode oft unverändert",
    ])
    _bullet_card(s, Inches(6.8), Inches(1.2), Inches(5.9), Inches(5.2), "Persistenz & Spuren", [
        "Häufig dauerhaft nach Neustart",
        "BLE: Limit-/Region-Parameter lesbar, wenn Protokoll es erlaubt",
        "Kein Custom-FW-Fingerprint nötig",
        "Modellabhängig — nicht pauschalisieren",
    ])
    finish(s, """
Parameter-Tuning ist die „leiseste“ Form: gleiche Firmware-Version, andere Werte.
ScooterCheck: Vergleich gegen Modellprofil (Soll-Limits). Score allein ≠ Beweis.
""")

    # ——— 12 Firmware ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "2 · Firmware-Tuning", size=26, bold=True, color=ACCENT)
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(5.9), Inches(5.2), "Was & wo", [
        "Modifizierter Programmcode (Flash)",
        "Custom Firmware / gepatchte Images",
        "Kann Checks, Limits, Auth umgehen",
        "Oft eigene Versionsstrings / Builds",
    ])
    _bullet_card(s, Inches(6.8), Inches(1.2), Inches(5.9), Inches(5.2), "Persistenz & Spuren", [
        "Persistent bis zum erneuten Flash",
        "Versions-/Build-Abweichungen möglich",
        "BLE-Verhalten kann abweichen",
        "Referenz: bekannte Serien-Firmware",
    ])
    finish(s, """
Custom FW kann Diagnose erschweren oder erleichtern (andere GATT-Antworten).
Nie behaupten: „Version X = immer Tuning“ ohne Modellreferenz.
""")

    # ——— 13 Session ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "3 · Temporäre Freischaltungen (Session / Soft-Unlock)", size=24, bold=True, color=ACCENT)
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(5.9), Inches(5.2), "Was & wo", [
        "Änderung oft nur im RAM",
        "Während aktiver Sitzung wirksam",
        "Nach Reset / Akku-Trennung weg",
        "Kein dauerhafter Flash nötig",
    ])
    _bullet_card(s, Inches(6.8), Inches(1.2), Inches(5.9), Inches(5.2), "Nachweisbarkeit", [
        "Nach Neustart: Spuren oft dünn",
        "Während Session: Limit ggf. lesbar",
        "Historische Peaks können bleiben",
        "Nicht mit Flash-Tuning gleichsetzen",
    ])
    finish(s, """
Didaktisch zentral: „Jetzt schnell“ ≠ „immer manipuliert gespeichert“.
EvidenceEngine gewichtet flüchtige vs. persistente Indizien unterschiedlich.
""")

    # ——— 14 License ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "4 · Lizenzcode- / App-Freischaltung", size=26, bold=True, color=ACCENT)
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(5.9), Inches(5.2), "Prinzip (allgemein)", [
        "Aktivierung über App / Code",
        "Kann temporär oder persistent sein",
        "Technisch: Schreibbefehl an MCU",
        "Nicht automatisch = RAM-only",
    ])
    _bullet_card(s, Inches(6.8), Inches(1.2), Inches(5.9), Inches(5.2), "Einordnung", [
        "Wirkung modell- und toolabhängig",
        "Persistenz prüfen (Neustart-Test)",
        "BLE-Auslesbarkeit wie bei Parametern",
        "Keine Gleichsetzung aller Tools",
    ])
    finish(s, """
Wichtig gegenüber dem Publikum: Lizenztools sind heterogen. Ohne Messung keine pauschale Aussage zu Persistenz.
""")

    # ——— 15 Hardware ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "5 · Hardware-Tuning", size=26, bold=True, color=ACCENT)
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(5.9), Inches(5.2), "Was & wo", [
        "Controller-Austausch",
        "Tuningmodule / Signalmanipulation",
        "Sensorik-Eingriffe (selten)",
        "Sichtbare Bauteil-/Kabelspuren möglich",
    ])
    _bullet_card(s, Inches(6.8), Inches(1.2), Inches(5.9), Inches(5.2), "BLE-Bezug", [
        "BLE-Identität kann unverändert bleiben",
        "Oder komplett anderes Modul",
        "Diagnose ggf. unmöglich / anders",
        "Visuelle Prüfung bleibt essenziell",
    ])
    finish(s, """
Hardware-Tuning ist der Bereich, in dem BLE allein oft scheitert. Immer: Gehäuse, Siegel, Kabelbaum, Controller-Aufkleber.
""")

    # ——— 16 Matrix ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.3), Inches(11), Inches(0.45),
             "Persistenz & Nachweisbarkeit (Überblick)", size=24, bold=True)
    headers = ["Tuningart", "Nach Neustart", "Typische Spuren", "BLE oft?"]
    rows = [
        ["Parameter", "meist ja", "Limit / Region / Modi", "wenn Protokoll"],
        ["Firmware", "ja", "Version / Build / Verhalten", "teilweise"],
        ["Session / RAM", "meist nein", "Peaks / Session-Logs", "nur live"],
        ["Lizenzcode", "variabel", "wie Parameter oder Session", "variabel"],
        ["Hardware", "ja", "Bauteile, ggf. anderes BLE", "unsicher"],
    ]
    col_w = [2.4, 2.2, 4.6, 2.4]
    x0, y0 = 0.6, 1.0
    # header
    x = x0
    for i, h in enumerate(headers):
        sh = s.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.RECTANGLE, Inches(x), Inches(y0), Inches(col_w[i]), Inches(0.55))
        _fill_solid(sh, ACCENT)
        tf = sh.text_frame
        p = tf.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.add_run()
        run.text = h
        _set_run(run, size=12, bold=True, color=BG)
        x += col_w[i]
    for r, row in enumerate(rows):
        x = x0
        y = y0 + 0.55 + r * 0.85
        for i, cell in enumerate(row):
            sh = s.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.RECTANGLE, Inches(x), Inches(y), Inches(col_w[i]), Inches(0.85))
            _fill_solid(sh, CARD if r % 2 == 0 else RGBColor(0x1A, 0x1F, 0x26))
            sh.line.color.rgb = BORDER
            tf = sh.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.CENTER
            run = p.add_run()
            run.text = cell
            _set_run(run, size=12, bold=(i == 0), color=TEXT)
            x += col_w[i]
    _textbox(s, Inches(0.7), Inches(6.4), Inches(12), Inches(0.4),
             "Immer modell-, firmware- und protokollabhängig — keine Universalsätze.",
             size=13, color=MUTED)
    finish(s, """
Matrix als Spickzettel. Betonen: „BLE oft?“ heißt nicht „immer nachweisbar“.
Frage aus dem Publikum erwarten: „Hilft Neustart-Test?“ → Ja, für Persistenz-Unterscheidung, wenn Diagnose möglich.
""")

    # ——— 17 Divider BLE ———
    s = new_slide(prs)
    _chip(s, Inches(0.7), Inches(2.8), Inches(1.6), Inches(0.4), "Kapitel 5")
    _textbox(s, Inches(0.7), Inches(3.4), Inches(12), Inches(1),
             "Bluetooth Low Energy", size=34, bold=True)
    finish(s, "Kurz: BLE ist der Sensor-/Diagnosekanal der App — nicht Ortung wie GPS.")

    # ——— 18 BLE basics ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "BLE in fünf Begriffen", size=28, bold=True)
    terms = [
        ("Advertising", "Kurze Broadcasts: Name, UUIDs, Manufacturer Data — ohne Verbindung"),
        ("Service UUID", "Kennzeichnet angebotene Dienste (Standard oder proprietär)"),
        ("Manufacturer Data", "Hersteller-Payload im Advertising — oft modellrelevant"),
        ("GATT", "Tabellenmodell aus Services/Characteristics nach Verbindungsaufbau"),
        ("RSSI", "Empfangspegel am Handy — relativ, störanfällig, kein Abstandsmesser"),
    ]
    for i, (t, d) in enumerate(terms):
        y = Inches(1.1) + Inches(i * 1.0)
        _card(s, Inches(0.7), y, Inches(11.9), Inches(0.88))
        _textbox(s, Inches(1.0), y + Inches(0.22), Inches(2.8), Inches(0.45), t, size=15, bold=True, color=ACCENT)
        _textbox(s, Inches(3.9), y + Inches(0.22), Inches(8.4), Inches(0.55), d, size=14, color=TEXT)
    finish(s, """
Quellen: Bluetooth SIG Core Spec / GATT; Apple CoreBluetooth.
Advertising ≠ Diagnose. Viele Scooter brauchen Auth, bevor Characteristics lesbar sind.
""")

    # ——— 19 Five steps ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Fünf unterschiedliche Fähigkeiten", size=26, bold=True)
    caps = [
        ("1", "Signal erkennen", "Advertising empfangen"),
        ("2", "Identifizieren", "Name, UUID, Fingerprint"),
        ("3", "Verbinden", "GATT-Connect + ggf. Auth"),
        ("4", "Diagnose lesen", "Parameter / FW / BMS"),
        ("5", "Bewerten", "EvidenceEngine / Profile"),
    ]
    for i, (n, t, d) in enumerate(caps):
        x = Inches(0.55) + Inches(i * 2.5)
        _card(s, x, Inches(1.8), Inches(2.35), Inches(3.8))
        _textbox(s, x + Inches(0.15), Inches(2.1), Inches(2.0), Inches(0.5), n, size=28, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
        _textbox(s, x + Inches(0.15), Inches(2.9), Inches(2.0), Inches(1.0), t, size=15, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
        _textbox(s, x + Inches(0.15), Inches(4.2), Inches(2.0), Inches(1.0), d, size=13, color=MUTED, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(0.7), Inches(6.0), Inches(12), Inches(0.5),
             "Erkannt ≠ auslesbar. Auslesbar ≠ Manipulation bewiesen.",
             size=16, bold=True, color=ACCENT)
    finish(s, "Diese Folie merken lassen — sie strukturiert die gesamte Tool-Demo.")

    # ——— 20 Limits ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Grenzen der BLE-Analyse", size=28, bold=True)
    limits = [
        "RSSI schwankt durch Körper, Metall, Mehrwegeausbreitung",
        "Bereits verbundene Apps können den Zugriff blockieren",
        "Proprietäre / verschlüsselte Protokolle → keine Umgehung",
        "Nicht dokumentierte Register bleiben unsichtbar",
        "Custom Firmware kann Diagnosefelder verfälschen oder leeren",
        "Fehlende Auffälligkeit ≠ Serienzustand bewiesen",
    ]
    for i, t in enumerate(limits):
        y = Inches(1.2) + Inches(i * 0.8)
        _card(s, Inches(0.7), y, Inches(11.9), Inches(0.7))
        _textbox(s, Inches(1.0), y + Inches(0.18), Inches(11.3), Inches(0.4), t, size=15, color=TEXT)
    finish(s, """
Ehrlich kommunizieren: ScooterCheck respektiert Auth-Grenzen (read-only, keine Exploits).
iOS Hintergrundscan: service-gefiltert — siehe Radar-Doku.
""")

    # ——— 21 ScooterCheck intro ———
    s = new_slide(prs)
    _logo(s)
    if (ASSETS / "appicon.png").exists():
        s.shapes.add_picture(str(ASSETS / "appicon.png"), Inches(0.7), Inches(1.5), width=Inches(1.6))
    _textbox(s, Inches(2.6), Inches(1.6), Inches(9.5), Inches(0.7),
             "ScooterCheck", size=36, bold=True, color=TEXT)
    _textbox(s, Inches(2.6), Inches(2.4), Inches(9.5), Inches(0.5),
             "Technische E-Scooter-Analyse über Bluetooth", size=20, color=ACCENT)
    points = [
        "iOS-App · CoreBluetooth · lokaler Fokus",
        "Erkennung, Identifikation, Radar, Karte, Feinsuche",
        "Read-only-Diagnose (modellabhängig)",
        "EvidenceEngine: Indizien → strukturierte Bewertung",
        "Dokumentation / Berichte für die Nacharbeit",
    ]
    for i, p in enumerate(points):
        _textbox(s, Inches(2.6), Inches(3.2) + Inches(i * 0.5), Inches(9.5), Inches(0.45),
                 "▸  " + p, size=15, color=TEXT)
    _textbox(s, Inches(0.7), Inches(6.2), Inches(12), Inches(0.4),
             "UI-Details: Live-Demo · keine fingierten Screenshots in dieser Datei",
             size=12, color=MUTED)
    finish(s, """
App vorstellen ohne Feature-Überforderung. Hinweis: Screenshots bewusst nicht fingiert — Demo zeigt den aktuellen Build.
Funktionen laut Produktionscode / Doku (Radar-Karte, Heatmap, Universal Diagnosis, EvidenceEngine).
""")

    # ——— 22 Signal Finder ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Signal-Finder", size=28, bold=True)
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(5.9), Inches(5.0), "Leistung", [
        "Scooter- und allgemeine BLE-Suche",
        "RSSI-Klassen (sehr stark → schwach)",
        "Geräteidentifikation + Fingerprint",
        "Ähnlichkeit ≠ sichere Identität",
        "Pfad-Heatmap & Heading-Unterstützung",
    ])
    _bullet_card(s, Inches(6.8), Inches(1.2), Inches(5.9), Inches(5.0), "Nutzen für die Praxis", [
        "Schnelles Auffinden in Reichweite",
        "Trennung Scooter vs. Fremd-BLE",
        "Wiedererkennung über Fingerprint",
        "Kein Ersatz für sichtbare Kontrolle",
        "Indoor: Grenzen der Ortung beachten",
    ])
    finish(s, "Fingerprint: sichere Matches brauchen starke Merkmale (Services, Mfg-Data), nicht nur Name.")

    # ——— 23 Radar ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "E-Scooter-Radar", size=28, bold=True)
    if (ASSETS / "scooter.png").exists():
        s.shapes.add_picture(str(ASSETS / "scooter.png"), Inches(9.6), Inches(1.5), width=Inches(3.0))
    _bullet_card(s, Inches(0.7), Inches(1.2), Inches(8.5), Inches(5.0), "Automatische Erkennung", [
        "Aktive Session · BLE-Suche während des Einsatzes",
        "Treffer ab konfigurierbarer Signalstärke",
        "Hintergrund: iOS kann einschränken (Service-Filter)",
        "Modellhinweise + Zulassungsstatus prüfen (Katalog)",
        "Beispiel: „KuKirin G4 erkannt — Zulassung prüfen“",
        "Kein automatischer Diagnose-Connect im Hintergrund",
    ])
    finish(s, """
Zulassungshinweise nur bei belastbarer Modellzuordnung (VehicleApprovalCatalog).
Display darf ausgehen / Keep-Awake: Session bleibt logisch aktiv.
""")

    # ——— 24 Radar map ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Radar-Karte", size=28, bold=True)
    _card(s, Inches(0.7), Inches(1.3), Inches(11.9), Inches(1.4))
    _textbox(s, Inches(1.0), Inches(1.55), Inches(11.3), Inches(1.0),
             "Die Karte zeigt den Empfangsort des Smartphones —\nnicht die exakte Position des Scooters.",
             size=20, bold=True, color=ACCENT)
    cols = [
        ("Zeitfilter", "24h · 48h · 7d · 14d · Gesamt"),
        ("Historie", "Sichtungen, Wiederholungen, Heatmap"),
        ("Verwaltung", "Löschen · Ausblenden · Einblenden"),
    ]
    for i, (t, d) in enumerate(cols):
        x = Inches(0.7) + Inches(i * 4.1)
        _card(s, x, Inches(3.1), Inches(3.9), Inches(2.8))
        _textbox(s, x + Inches(0.25), Inches(3.4), Inches(3.4), Inches(0.5), t, size=16, bold=True, color=ACCENT)
        _textbox(s, x + Inches(0.25), Inches(4.2), Inches(3.4), Inches(1.3), d, size=14, color=TEXT)
    finish(s, "Opt-in Standort. Löschen betrifft nur Radar-Historie, nicht Prüfberichte/Wächter.")

    # ——— 25 Heatmap ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Heatmap & Feinsuche", size=28, bold=True)
    _card(s, Inches(0.7), Inches(1.3), Inches(5.9), Inches(4.8))
    _textbox(s, Inches(1.0), Inches(1.6), Inches(5.3), Inches(0.5), "Unzuverlässig allein", size=16, bold=True, color=WARN)
    for i, t in enumerate([
        "Statischer „Richtungspfeil“ aus RSSI",
        "Einzelmessung = Abstand?",
        "Ignorieren von Mehrweg/Abschattung",
    ]):
        _textbox(s, Inches(1.0), Inches(2.5) + Inches(i * 0.9), Inches(5.3), Inches(0.7), "•  " + t, size=14, color=TEXT)

    _card(s, Inches(6.8), Inches(1.3), Inches(5.9), Inches(4.8))
    _textbox(s, Inches(7.1), Inches(1.6), Inches(5.3), Inches(0.5), "Systematische Heatmap", size=16, bold=True, color=ACCENT)
    for i, t in enumerate([
        "RSSI entlang des Laufwegs",
        "Stärkster Bereich markieren",
        "Haptik/Ton als Feedback",
        "Indoor: relative Rekonstruktion",
    ]):
        _textbox(s, Inches(7.1), Inches(2.5) + Inches(i * 0.75), Inches(5.3), Inches(0.6), "•  " + t, size=14, color=TEXT)
    finish(s, "Innenraum: kein GPS-Ersatz. PDR/AR helfen, bleiben aber Schätzungen.")

    # ——— 26 Diagnosis ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Diagnose (read-only)", size=28, bold=True)
    flow = ["Verbinden", "Auth*\n(modellabh.)", "Parameter\nlesen", "Profil-\nvergleich", "Bericht"]
    for i, label in enumerate(flow):
        x = Inches(0.55) + Inches(i * 2.5)
        sh = s.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE, x, Inches(1.3), Inches(2.2), Inches(1.3))
        _fill_solid(sh, CARD)
        sh.line.color.rgb = ACCENT
        tf = sh.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.add_run()
        run.text = label
        _set_run(run, size=13, bold=True, color=TEXT)
        if i < len(flow) - 1:
            _textbox(s, x + Inches(2.15), Inches(1.7), Inches(0.4), Inches(0.4), "→", size=18, bold=True, color=ACCENT)

    _textbox(s, Inches(0.7), Inches(3.0), Inches(12), Inches(0.4),
             "Mögliche Felder (nur wenn das Protokoll sie liefert)", size=14, color=MUTED)
    fields = [
        "Seriennummern", "MCU- / BLE- / BMS-FW", "Region", "Speed-Limit",
        "Fahrmodi", "Betriebsdaten / Peaks", "DIS (GATT)", "VCU (falls vorhanden)",
    ]
    for i, f in enumerate(fields):
        col, row = i % 4, i // 4
        x = Inches(0.7) + Inches(col * 3.1)
        y = Inches(3.5) + Inches(row * 1.1)
        _card(s, x, y, Inches(2.95), Inches(0.9))
        _textbox(s, x + Inches(0.15), y + Inches(0.25), Inches(2.65), Inches(0.45), f, size=13, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(0.7), Inches(6.0), Inches(12), Inches(0.5),
             "* Keine Auth-Umgehung · fehlende Werte = „Nicht verfügbar“ · Support: fullNative / gattReadonly / researchHintOnly / none",
             size=12, color=MUTED)
    finish(s, "Universal Diagnosis: Herstellername ≠ Diagnose möglich. Nur verified Profile.")

    # ——— 27 EvidenceEngine ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.3), Inches(11), Inches(0.45),
             "EvidenceEngine", size=28, bold=True)
    _textbox(s, Inches(0.7), Inches(0.9), Inches(12), Inches(0.4),
             "Einzelwerte → Indizienklassen → verdichtete Bewertung (kein Gerichtsurteil)",
             size=14, color=MUTED)
    classes = [
        ("Info", "Rohwert / Kontext"),
        ("Abweichung", "Abweichung vom Profil"),
        ("Manipulationsindiz", "Auffälliges Muster"),
        ("starker Hinweis", "Mehrere starke Indizien"),
    ]
    for i, (t, d) in enumerate(classes):
        x = Inches(0.55) + Inches(i * 3.15)
        _card(s, x, Inches(1.5), Inches(3.0), Inches(2.0))
        _textbox(s, x + Inches(0.15), Inches(1.75), Inches(2.7), Inches(0.5), t, size=14, bold=True, color=ACCENT, align=PP_ALIGN.CENTER)
        _textbox(s, x + Inches(0.15), Inches(2.4), Inches(2.7), Inches(0.8), d, size=13, color=TEXT, align=PP_ALIGN.CENTER)

    _card(s, Inches(0.7), Inches(3.9), Inches(11.9), Inches(2.5))
    _textbox(s, Inches(1.0), Inches(4.15), Inches(11.3), Inches(0.4), "Beispielhafte Indizien (modellabhängig)", size=15, bold=True, color=ACCENT)
    _textbox(s, Inches(1.0), Inches(4.7), Inches(11.3), Inches(1.4),
             "• Abweichendes Speed-Limit  ·  Custom-/unbekannte Firmware  ·  inkonsistente Seriennummern\n"
             "• auffällige Region  ·  Peak über Clear-Schwelle  ·  widersprüchliche Steuergeräteangaben\n\n"
             "Mehrere unabhängige Indizien > einzelner Messwert. Score ist Hilfsmittel, kein Beweis.",
             size=14, color=TEXT)
    finish(s, """
EvidenceClass laut Code: Info / Abweichung / Manipulationsindiz / starker Manipulationshinweis.
Schwellen tuningSuspectKmh / tuningClearKmh sind profilbezogen.
""")

    # ——— 28 Comparison ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Kontrollierter Vergleich", size=28, bold=True)
    _textbox(s, Inches(0.7), Inches(1.2), Inches(12), Inches(0.6),
             "Messwerte vor und nach einem beobachteten Zustandswechsel\n— ohne selbst zu manipulieren.",
             size=16, color=MUTED)
    steps = [
        ("A", "Ist-Zustand\ndokumentieren"),
        ("B", "Ereignis\nbeobachten"),
        ("C", "Erneut\nauslesen"),
        ("D", "Differenz\nbewerten"),
    ]
    for i, (n, t) in enumerate(steps):
        x = Inches(0.9) + Inches(i * 3.1)
        sh = s.shapes.add_shape(MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE, x, Inches(2.5), Inches(2.7), Inches(2.5))
        _fill_solid(sh, CARD)
        sh.line.color.rgb = ACCENT
        tf = sh.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.alignment = PP_ALIGN.CENTER
        run = p.add_run()
        run.text = n + "\n\n" + t
        _set_run(run, size=15, bold=True, color=TEXT)
    _textbox(s, Inches(0.7), Inches(5.5), Inches(12), Inches(0.8),
             "Nur tatsächlich gelieferte Felder vergleichen. Fehlende Werte nicht interpretieren.",
             size=15, color=TEXT)
    finish(s, "Vergleichstests sind methodisch sauber und ethisch klar: keine eigene Manipulation.")

    # ——— 29 Workflow ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.3), Inches(11), Inches(0.45),
             "Praktischer Prüfablauf", size=26, bold=True)
    steps = [
        "1 Visuell erfassen",
        "2 ScooterCheck öffnen",
        "3 BLE suchen",
        "4 Identifizieren",
        "5 Verbindung prüfen",
        "6 Parameter lesen",
        "7 Abweichungen analysieren",
        "8 Bewerten",
        "9 Bericht speichern",
    ]
    for i, t in enumerate(steps):
        col, row = i % 3, i // 3
        x = Inches(0.7) + Inches(col * 4.1)
        y = Inches(1.1) + Inches(row * 1.7)
        _card(s, x, y, Inches(3.9), Inches(1.4))
        _textbox(s, x + Inches(0.25), y + Inches(0.4), Inches(3.4), Inches(0.6), t, size=15, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
    finish(s, "Ablauf als Checkliste ausgeben. Visuell bleibt Schritt 1 — immer.")

    # ——— 30 Demo ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Live-Demonstration", size=28, bold=True)
    _textbox(s, Inches(0.7), Inches(1.2), Inches(12), Inches(0.4),
             "Am tatsächlichen Funktionsstand der App — kein Skript mit Fantasiewerten",
             size=14, color=MUTED)
    demo = [
        "BLE-Suche starten · Scooter in Reichweite bringen",
        "Treffer / Radar · Identifikation besprechen",
        "Diagnose starten (wenn Support-Level es erlaubt)",
        "Messwerte & Evidence-Klassen kommentieren",
        "Bericht / Speicherung zeigen",
        "Optional: Radar-Karte oder Feinsuche kurz anreißen",
    ]
    for i, t in enumerate(demo):
        y = Inches(1.8) + Inches(i * 0.7)
        _card(s, Inches(0.7), y, Inches(11.9), Inches(0.6))
        _textbox(s, Inches(1.0), y + Inches(0.12), Inches(11.3), Inches(0.4), f"{i+1}.  {t}", size=15, color=TEXT)
    finish(s, """
Demo-Plan B: Wenn kein Scooter / Auth scheitert → Advertising + Identifikation + Grenzen erklären.
Niemals Auth umgehen oder Schreibbefehle zeigen.
""")

    # ——— 31 Misinterpretations ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.3), Inches(11), Inches(0.45),
             "Was ScooterCheck erkennt — und was nicht", size=24, bold=True)
    myths = [
        ("Hohes RSSI", "≠ unmittelbare Nähe garantiert"),
        ("US-Region", "≠ automatisch Tuning"),
        ("Hoher Peak", "≠ Ursache bewiesen"),
        ("Keine Auffälligkeit", "≠ Serienzustand sicher"),
        ("Fingerprint", "≠ immer eindeutige Identität"),
        ("FW-Version", "nur mit Modellreferenz bewerten"),
    ]
    for i, (a, b) in enumerate(myths):
        col, row = i % 2, i // 2
        x = Inches(0.7) + Inches(col * 6.2)
        y = Inches(1.1) + Inches(row * 1.7)
        _card(s, x, y, Inches(5.9), Inches(1.45))
        _textbox(s, x + Inches(0.3), y + Inches(0.3), Inches(5.3), Inches(0.4), a, size=16, bold=True, color=ACCENT)
        _textbox(s, x + Inches(0.3), y + Inches(0.8), Inches(5.3), Inches(0.4), b, size=14, color=TEXT)
    finish(s, "Diese Folie aktiv diskutieren — Fehlinterpretationen sind der häufigste Praxisfall.")

    # ——— 32 Takeaways ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Kernaussagen", size=28, bold=True)
    takes = [
        "Tuning findet auf unterschiedlichen technischen Ebenen statt.",
        "Temporäre und persistente Manipulationen sind zu trennen.",
        "Nicht jede Manipulation ist über BLE nachweisbar.",
        "Einzelne Diagnosewerte brauchen technische Einordnung.",
        "ScooterCheck strukturiert Erkennung, Auswertung und Dokumentation.",
    ]
    for i, t in enumerate(takes):
        y = Inches(1.2) + Inches(i * 1.0)
        _card(s, Inches(0.7), y, Inches(11.9), Inches(0.85))
        _textbox(s, Inches(1.0), y + Inches(0.22), Inches(0.6), Inches(0.45), str(i + 1), size=20, bold=True, color=ACCENT)
        _textbox(s, Inches(1.8), y + Inches(0.25), Inches(10.4), Inches(0.45), t, size=16, color=TEXT)
    finish(s, "Zusammenfassung langsam vorlesen. Offene Fragen sammeln.")

    # ——— 33 Close ———
    s = new_slide(prs)
    if (ASSETS / "appicon.png").exists():
        s.shapes.add_picture(str(ASSETS / "appicon.png"), Inches(6.15), Inches(1.2), width=Inches(1.0))
    _textbox(s, Inches(0.7), Inches(2.5), Inches(12), Inches(0.6),
             "ScooterCheck", size=36, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(1.5), Inches(3.4), Inches(10.3), Inches(1.2),
             "Manipulationen verstehen.\nTechnische Auffälligkeiten erkennen.\nErgebnisse nachvollziehbar dokumentieren.",
             size=20, color=ACCENT, align=PP_ALIGN.CENTER)
    _textbox(s, Inches(0.7), Inches(5.2), Inches(12), Inches(0.5),
             "Fragen & Diskussion", size=22, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
    finish(s, "Dank, Kontakthinweise der Organisation, TestFlight/Intern nach Bedarf.")

    # ——— 34 Sources ———
    s = new_slide(prs)
    _logo(s)
    _textbox(s, Inches(0.7), Inches(0.35), Inches(11), Inches(0.5),
             "Quellen & Abgrenzung", size=28, bold=True)
    _textbox(s, Inches(0.7), Inches(1.2), Inches(12), Inches(5.0),
             "• Bluetooth SIG — Core Specification / GATT Overview\n"
             "• Apple — CoreBluetooth Framework Documentation\n"
             "• ScooterCheck — interne Doku: UNIVERSAL_SCOOTER_DIAGNOSIS, RADAR_MAP,\n"
             "  BLE_PATH_HEATMAP, RADAR_BACKGROUND_APPROVAL, EvidenceEngine.swift\n"
             "• Herstellerangaben (modellbezogen) und dokumentierte Open-Source-Analysen\n\n"
             "Abgrenzung: Keine erfundenen Register, keine Auth-Umgehung, keine Rechtsbelehrung.\n"
             "Aussagen zu Nachweisbarkeit sind immer modell-/firmware-/protokollabhängig.\n"
             "App-UI in der Schulung per Live-Demo — keine fingierten Screenshots.",
             size=14, color=TEXT)
    finish(s, "Quellenfolie für Handout / Nacharbeit. Bei Nachfragen auf Doku im Repo verweisen.")

    total = len(built)
    for i, slide in enumerate(built, start=1):
        _footer(slide, i, total)

    prs.save(str(OUT))
    print(f"Wrote {OUT} with {total} slides")
    return OUT, total


if __name__ == "__main__":
    build()
