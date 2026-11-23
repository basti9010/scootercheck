import Foundation

/// Testable wiring helper for Hub → `InvestigationStore.attachFirmwareReport`.
/// Mirrors `ContentView.attachFirmwareReportFromHub` without SwiftUI state.
@MainActor
enum FirmwareInvestigationAttach {
    struct Outcome: Equatable, Sendable {
        var investigationId: String
        var createdNewInvestigation: Bool
        var ref: InvestigationFirmwareRef?
        var didAttach: Bool
        var errorDescription: String?
    }

    /// Resolve the investigation that should receive a firmware report.
    /// Reuses `activeId` when the record still exists; otherwise creates a firmware-only record.
    static func resolveTargetId(
        store: InvestigationStore,
        activeId: String?,
        reportFileName: String
    ) -> (id: String, createdNew: Bool) {
        if let existing = activeId, store.record(id: existing) != nil {
            return (existing, false)
        }
        let title = reportFileName.isEmpty ? "Firmwareanalyse" : reportFileName
        let rec = store.create(title: title, progress: .analyzeFirmware)
        return (rec.id, true)
    }

    /// Attach report (+ optional original bytes) to the resolved investigation.
    /// On failure, appends a soft note and leaves the investigation open for retry.
    @discardableResult
    static func attach(
        report: FirmwareForensicReport,
        originalData: Data?,
        store: InvestigationStore,
        activeInvestigationId: inout String?
    ) -> Outcome {
        let resolved = resolveTargetId(
            store: store,
            activeId: activeInvestigationId,
            reportFileName: report.originalFileName
        )
        activeInvestigationId = resolved.id

        do {
            let ref = try store.attachFirmwareReport(
                report,
                originalData: originalData,
                to: resolved.id
            )
            return Outcome(
                investigationId: resolved.id,
                createdNewInvestigation: resolved.createdNew,
                ref: ref,
                didAttach: true,
                errorDescription: nil
            )
        } catch {
            if var rec = store.record(id: resolved.id) {
                rec.notes.append("Firmware-Speichern fehlgeschlagen: \(error.localizedDescription)")
                store.upsert(rec)
            }
            return Outcome(
                investigationId: resolved.id,
                createdNewInvestigation: resolved.createdNew,
                ref: nil,
                didAttach: false,
                errorDescription: error.localizedDescription
            )
        }
    }
}
