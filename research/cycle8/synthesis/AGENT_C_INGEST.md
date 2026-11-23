# Agent C ingest

Source: [iOS Developer](bc-f2116c4f-b9c9-56c3-a3d4-bb7e6d2af9c5)  
Branch: `cursor/ios-firmware-forensics-hub-b100` @ `03dfe40`

## Merged into C8 tip
Hub + AnalysisView + DocumentPicker + LocalPipeline + JobUIStatus mapper/tests  
ContentView → Hub sheet → `InvestigationStore.attachFirmwareReport`  
ServerClient accepts Settings API token when JWT absent  
Crypto gate: encrypted without plaintext → INCOMPLETE (never COMPLETED decompile claim)

## Residual
Full Orchestrator/ZipInspector/ReferenceStore not ported; live server E2E still pending; AuthSession JWT not invented.
