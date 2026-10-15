import Combine
import CoreBluetooth
import LoopKit
@testable import TandemKit
// Package.swift: on Linux the oracles and MockPumpManagerDelegate are compiled into TandemKitTests.
#if os(Linux)
@testable import TandemKitTests
#endif
import XCTest

/// Another app on the phone talking to the same pump, as the Tandem app does: the link is shared,
/// so the driver is notified of that app's responses too, each under that app's txId (#507). The
/// proxy delivers them at the moment they collide with a request the driver is waiting on.
final class AnotherClientIntegrationTests: FaketandemIntegrationTestCase {
    private var proxy: SecondClientProxy!

    override func setUpWithError() throws {
        try super.setUpWithError()
        proxy = try SecondClientProxy(upstream: harness.endpoint)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        proxy?.stop()
        proxy = nil
    }

    /// Delivers `theirs` ahead of the pump's answer to the driver's first `request` after the hook is
    /// set; the answer is matched on its opcode and the request's txId. Returns whether it fired.
    private func deliver(
        _ theirs: @escaping (UInt8) -> [(CBUUID, Data)],
        aheadOfTheAnswerTo request: (any Message.Type),
        answeredBy response: (any Message.Type)
    ) -> ResultBox<Bool> {
        let requestTxId = ResultBox<UInt8>()
        let delivered = ResultBox<Bool>()
        let requestProps = request.props
        let responseProps = response.props
        proxy.onDriverWrite = { characteristic, value in
            if characteristic == requestProps.characteristic, value.count > 2, value[2] == requestProps.opCode, !requestTxId.isSet {
                requestTxId.set(value[1])
            }
        }
        proxy.onPumpNotification = { characteristic, value in
            guard let txId = requestTxId.value, !delivered.isSet, characteristic == responseProps.characteristic,
                  value.count > 3, value[1] == txId, value[2] == responseProps.opCode, value[3] == txId
            else {
                return [(characteristic, value)]
            }
            delivered.set(true)
            return theirs(txId) + [(characteristic, value)]
        }
        return delivered
    }

    private static func notifications(_ response: Message, txId: UInt8) -> [(CBUUID, Data)] {
        Packetize.parse(message: response, authenticationKey: nil, txId: txId, timeSinceReset: nil).map {
            (type(of: response).props.characteristic, $0.build())
        }
    }

    func testAnotherClientsReservoirReadingIsNotTheDrivers() throws {
        let driver = makeDriver(via: proxy.endpoint)
        try harness.pair(driver)
        try harness.client.setState(["reservoir_units": 137.5])
        let delivered = deliver(
            { txId in
                Self.notifications(InsulinStatusResponse(currentInsulinAmount: 5, isEstimate: 0, insulinLowAmount: 20), txId: txId &+ 100)
            },
            aheadOfTheAnswerTo: InsulinStatusRequest.self,
            answeredBy: InsulinStatusResponse.self
        )

        XCTAssertNotNil(try harness.sync(driver))

        XCTAssertEqual(delivered.value, true, "the other client's response must arrive while the driver waits")
        XCTAssertEqual(driver.delegate.reservoirReadings.last?.units, 137)
    }

    /// The messages the issue's logs show arriving in a burst after a connect: another app's connect
    /// sequence, one of whose basal reads finds the pump suspended.
    func testAnotherClientsConnectBurstLeavesTheDriversSyncAlone() throws {
        let driver = makeDriver(via: proxy.endpoint)
        try harness.pair(driver)
        let delivered = deliver(
            { txId in
                let burst: [Message] = [
                    ApiVersionResponse(majorVersion: 3, minorVersion: 5),
                    CurrentBasalStatusResponse(profileBasalRate: 850, currentBasalRate: 0, basalModifiedBitmask: 1),
                    PumpVersionResponse(cargo: Data(count: Int(PumpVersionResponse.props.size))),
                    LocalizationResponse(cargo: Data(count: Int(LocalizationResponse.props.size))),
                    PumpFeaturesV1Response(cargo: Data(count: Int(PumpFeaturesV1Response.props.size))),
                    PumpFeaturesV2Response(cargo: Data(count: Int(PumpFeaturesV2Response.props.size))),
                    HistoryLogResponse(status: 0, streamId: 1),
                ]
                return burst.enumerated().flatMap { index, message in
                    Self.notifications(message, txId: txId &+ 50 &+ UInt8(index))
                }
            },
            aheadOfTheAnswerTo: CurrentBasalStatusRequest.self,
            answeredBy: CurrentBasalStatusResponse.self
        )

        XCTAssertNotNil(try harness.sync(driver))

        XCTAssertEqual(delivered.value, true, "the burst must arrive while the driver waits for its basal status")
        XCTAssertTrue(driver.delegate.errors.isEmpty, "no communication errors: \(driver.delegate.errors)")
        XCTAssertFalse(driver.delegate.pumpEvents.contains { $0.type == .suspend }, "the pump was never suspended")
        if case .suspended = driver.manager.status.basalDeliveryState {
            XCTFail("the pump was never suspended")
        }
    }

    /// The fill tubing screen's stream runs while the driver waits on a control answer. At the
    /// minimum MTU a signed stream message takes two notifications; the second is HMAC, which here
    /// carries the awaited opcode at byte 2 and a refusal's status at byte 5.
    func testAStreamPacketDuringFillTubingIsNotTheControlAnswer() throws {
        let driver = makeDriver(via: proxy.endpoint)
        try harness.pair(driver)
        try harness.client.setState(["workflow_mode": "none", "suspended": true])
        defer { _ = try? harness?.client.setState(["workflow_mode": "none", "suspended": false]) }
        let buttonStates = ResultBox<[Int]>()
        buttonStates.set([])
        let observation = driver.manager.fillTubingStateStream.sink { event in
            buttonStates.set((buttonStates.value ?? []) + [event.buttonState])
        }
        defer { observation.cancel() }

        let answerOpCode = EnterFillTubingModeResponse.props.opCode
        var trailer = Data(repeating: 0xA5, count: 24)
        // The second notification starts at message byte 18: byte 2 of it is trailer byte 14.
        trailer[14] = answerOpCode
        trailer[17] = 1
        let streamTxId: UInt8 = 0x40
        let body = Data([FillTubingStateStreamResponse.props.opCode, streamTxId, 25, 1]) + trailer
        let message = body + CalculateCRC16(body)
        let stream = [
            Data([1, streamTxId]) + message.prefix(18),
            Data([0, streamTxId]) + message.dropFirst(18),
        ].map { (CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS, $0) }
        XCTAssertEqual(stream[1].1[2], answerOpCode)
        let delivered = deliver({ _ in stream }, aheadOfTheAnswerTo: EnterFillTubingModeRequest.self, answeredBy: EnterFillTubingModeResponse.self)

        let status = ResultBox<Int?>()
        driver.manager.enterFillTubingMode { status.set($0?.status) }

        XCTAssertEqual(try status.wait("EnterFillTubingMode", timeout: 30), 0)
        XCTAssertEqual(delivered.value, true, "the stream must arrive while the driver waits")
        XCTAssertEqual(buttonStates.value, [1])
    }
}
