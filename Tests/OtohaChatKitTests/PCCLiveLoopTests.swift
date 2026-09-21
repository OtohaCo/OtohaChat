import OtohaChatKit
import Foundation
import Testing

struct PCCLiveLoopTests {
    @Test func coreLoopStatusIsDocumentedWhenUnsigned() {
        #expect(PCCQualification.status == "BLOCKED_CONFIGURATION")
        let liveRequested = ProcessInfo.processInfo.environment["OTOHACHAT_PCC_LIVE"] == "1"
        if !liveRequested {
            // Unsigned CI and ordinary clones must not pretend the PCC tool loop passed.
            #expect(Bool(true))
            return
        }
        #if OTOHACHAT_PCC_LIVE
        Issue.record("Live PCC execution is enabled in this environment; run the signed host separately.")
        #else
        Issue.record("OTOHACHAT_PCC_LIVE=1 but this test binary was not compiled with OTOHACHAT_PCC_LIVE.")
        #endif
    }
}
