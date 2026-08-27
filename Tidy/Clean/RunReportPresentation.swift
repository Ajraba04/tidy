import TidyCore

struct RunReportPresentation {
    let measurementsAvailable: Bool
    let memoryText: String
    let admissionMessage: String?

    init(report: RunReport) {
        measurementsAvailable = report.coordinatorMeasurementsAvailable != false
        if measurementsAvailable, let measured = report.measuredTotalReclaimedMemoryBytes {
            memoryText = ByteFormat.human(measured)
        } else {
            memoryText = "Not measured"
        }

        guard !measurementsAvailable else {
            admissionMessage = nil
            return
        }
        switch report.disposition {
        case .noWork:
            admissionMessage = "No items selected; nothing was run."
        case .busy:
            admissionMessage = "Another cleanup is running. Wait for it to finish, then try again."
        case .recoveryBlocked:
            admissionMessage = "An earlier operation may still be running. Cleanup is blocked pending reconciliation."
        case .storageUnavailable:
            admissionMessage = "Execution records could not be validated. Cleanup remains blocked."
        case .stalePolicy:
            admissionMessage = "Settings changed. Review the items again before confirming."
        case .staleReview, .invalidToken:
            admissionMessage = "This confirmation is no longer valid. Review the items again."
        case .unavailableSelection:
            admissionMessage = "The selected action is unavailable. Nothing was run."
        case .completed:
            admissionMessage = "The operation finished, but measurements are unavailable."
        }
    }
}
