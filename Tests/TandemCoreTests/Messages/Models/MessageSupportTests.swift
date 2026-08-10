@testable import TandemKit
import XCTest

final class MessageSupportTests: XCTestCase {
    /// Sleep schedules are Mobi-only from API 3.5, which is why the settings screen shows them
    /// read-only on a t:slim X2 instead of offering a write the pump will not answer.
    func testSleepScheduleWriteIsMobiOnly() {
        XCTAssertTrue(SetSleepScheduleRequest.props.isSupported(
            pumpModel: .MOBI,
            apiVersion: KnownApiVersion.mobiApiV3_5.value
        ))
        XCTAssertFalse(SetSleepScheduleRequest.props.isSupported(
            pumpModel: .TSLIM_X2,
            apiVersion: KnownApiVersion.mobiApiV3_5.value
        ))
    }

    func testMessageBelowItsMinimumApiIsUnsupported() {
        XCTAssertFalse(SetSleepScheduleRequest.props.isSupported(
            pumpModel: .MOBI,
            apiVersion: KnownApiVersion.apiV3_4.value
        ))
    }

    func testMinimumApiItselfIsSupported() {
        XCTAssertTrue(SetSleepScheduleRequest.props.isSupported(
            pumpModel: .MOBI,
            apiVersion: KnownApiVersion.mobiApiV3_5.value
        ))
    }

    func testNewerApiIsSupported() {
        XCTAssertTrue(SetSleepScheduleRequest.props.isSupported(
            pumpModel: .MOBI,
            apiVersion: KnownApiVersion.apiFuture.value
        ))
    }

    /// Before the pump has been interrogated we do not know what it accepts, and offering a write on
    /// a guess is worse than waiting for the next sync to say.
    func testUnknownPumpIsTreatedAsUnsupported() {
        XCTAssertFalse(SetSleepScheduleRequest.props.isSupported(
            pumpModel: nil,
            apiVersion: KnownApiVersion.mobiApiV3_5.value
        ))
        XCTAssertFalse(SetSleepScheduleRequest.props.isSupported(pumpModel: .MOBI, apiVersion: nil))
    }

    /// A message with no restrictions is supported on every known pump.
    func testUnrestrictedMessageIsSupportedEverywhere() {
        for model in [PumpModel.TSLIM_X2, .MOBI] {
            XCTAssertTrue(
                ControlIQInfoV1Request.props.isSupported(
                    pumpModel: model,
                    apiVersion: KnownApiVersion.apiV2_1.value
                ),
                "Expected \(model) to support ControlIQInfoV1Request"
            )
        }
    }
}
