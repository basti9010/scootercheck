# ScooterCheck – Technikschulung (PowerPoint)

**Datei:** [`ScooterCheck_Technikschulung_Polizei.pptx`](ScooterCheck_Technikschulung_Polizei.pptx)

Professionelle 16:9-Präsentation (34 Folien) für polizeiliche Technikfortbildung:

> E-Scooter-Tuning verstehen, Manipulationen erkennen und mit ScooterCheck analysieren

## Inhalt

1. Aufbau & Geschwindigkeitsbegrenzung  
2. Tuningarten (Parameter, Firmware, Session, Lizenz, Hardware) getrennt  
3. Persistenz-Matrix  
4. BLE-Grundlagen & Grenzen  
5. ScooterCheck-Module (Finder, Radar, Karte, Heatmap, Diagnose, EvidenceEngine)  
6. Prüfablauf, Live-Demo, Fehlinterpretationen, Quellen  

Jede Folie hat ausführliche **Sprecher-Notizen**.

## Design

ScooterCheck-CI: Hintergrund `#12161C`, Akzent `#6BDBC2`, Text `#F5F7F8`, Sekundär `#8B949E`, Karten `#20262D`. Logo/App-Icon aus dem iOS-Target.

## Screenshots

Es wurden **keine fingierten App-Screenshots** eingefügt. Die UI wird in der **Live-Demo** am aktuellen Build gezeigt. Eingebettet: echtes Logo, App-Icon, Produktgrafik.

## Neu erzeugen

```bash
python3 docs/schulung/build_technikschulung.py
```

Benötigt: `python-pptx`, Assets unter `docs/schulung/assets/`.

## Fachliche Abgrenzung

- Keine Rechtsbelehrung, keine Tuning-Anleitungen  
- Keine erfundenen Register/Diagnosefelder  
- Nachweisbarkeit immer modell-/firmware-/protokollabhängig  
- EvidenceEngine-Klassen entsprechen dem Code (`Info` … `starker Manipulationshinweis`)
