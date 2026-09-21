/// Host presentation of an execution report. Model text cannot create a
/// Receipt or erase an observed tool fact.
public enum ExecutionReportCopy {
    public static func message(for report: RunExecutionReport?) -> String? {
        guard let report else { return nil }
        let committed = report.receipts.contains { $0.receipt.status == .succeeded }
        let completedTool = report.toolObservations.contains {
            if case .completed(let isError) = $0.status { return !isError }
            return false
        }
        let uncertainTool = report.toolObservations.contains {
            switch $0.status {
            case .failed, .unknown, .admitted: true
            case .proposed, .completed: false
            }
        }
        switch report.presentation {
        case .malformed, .contradictory:
            if committed { return "A tool action completed, but the final reply was unavailable." }
            if completedTool { return "A tool completed, but the final reply was unavailable." }
        case .notObserved, .parsed:
            break
        }
        if completedTool, case .failed = report.runtimeTermination {
            return "A tool completed before the request failed."
        }
        if completedTool, case .cancelled? = report.runtimeTermination {
            return "A tool completed before the request was cancelled."
        }
        if committed, case .failed = report.runtimeTermination {
            return "An action was saved before the request failed."
        }
        if committed, case .cancelled? = report.runtimeTermination {
            return "An action was saved before the request was cancelled."
        }
        if uncertainTool {
            return "The requested action did not complete; its external effect is unknown."
        }
        return nil
    }
}
