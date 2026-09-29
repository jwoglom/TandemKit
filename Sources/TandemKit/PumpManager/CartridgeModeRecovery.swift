import Foundation

/// Backs the pump out of a cartridge procedure left open, then enters change-cartridge mode again.
///
/// The pump refuses `EnterChangeCartridgeMode` while another procedure is open, and a wizard the
/// user walked away from mid-fill leaves fill-tubing open, where exiting change-cartridge mode is
/// refused too. So the exits run in the reverse of the wizard's order and neither is allowed to
/// stop the sequence: a nonzero exit status only says the pump was not in that mode.
///
/// Like `ResumeWithAlarmAcknowledgement`, every operation is synchronous and must run on the pump
/// command queue with the pump already connected.
struct CartridgeModeRecovery {
    /// The pump's status, or nil when it did not answer.
    let exitFillTubing: () -> Int?
    let exitChangeCartridge: () -> Int?
    let enterChangeCartridge: () -> EnterChangeCartridgeModeResponse?
    var log: (String) -> Void = { _ in }

    /// The pump's answer to the final enter, nil if it gave none.
    func run() -> EnterChangeCartridgeModeResponse? {
        log("Exit fill tubing mode: status \(describe(exitFillTubing()))")
        log("Exit change cartridge mode: status \(describe(exitChangeCartridge()))")

        let response = enterChangeCartridge()
        log("Re-enter change cartridge mode: status \(describe(response?.status))")
        return response
    }

    private func describe(_ status: Int?) -> String {
        status.map(String.init) ?? "no answer"
    }
}
