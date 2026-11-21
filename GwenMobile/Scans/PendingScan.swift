struct PendingScan {
    var outcome: ScanOutcome
    var request: ScanRequest
    var file: PendingFile

    init(outcome: ScanOutcome, request: ScanRequest) {
        self.outcome = outcome
        self.request = request
        self.file = PendingFile(outcome.attachment)
    }
}
