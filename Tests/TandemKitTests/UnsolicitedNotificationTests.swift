#if TANDEMKIT_VIRTUAL_PUMP
import Combine
import CoreBluetooth
import Foundation
@testable import TandemKit
import XCTest

private final class ConnectRecorder: CBCentralManagerDelegate {
    var onConnect: ((CBPeripheral) -> Void)?

    func centralManagerDidUpdateState(_: CBCentralManager) {}

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnect?(peripheral)
    }
}

private final class DiscoveryRecorder: CBPeripheralDelegate {
    var onServices: (() -> Void)?
    var onCharacteristics: (() -> Void)?

    func peripheral(_: CBPeripheral, didDiscoverServices _: Error?) {
        onServices?()
    }

    func peripheral(_: CBPeripheral, didDiscoverCharacteristicsFor _: CBService, error _: Error?) {
        onCharacteristics?()
    }
}

/// Notifications that are not the answer to the write in flight, through the real
/// `TandemPeripheralManager` over the virtual link: responses to another app's requests on the link
/// the phone shares, a late answer to a write that timed out, and the pump's own stream and
/// qualifying-event packets, each shaped to collide with the pending write (#507).
final class UnsolicitedNotificationTests: XCTestCase {
    private var server: FakeVirtualPumpServer!
    private var central: CBCentralManager!
    private var centralDelegate: ConnectRecorder!
    private var pumpManager: TandemPumpManager!
    private var peripheralManager: TandemPeripheralManager!
    private var savedResponseTimeout: DispatchTimeInterval?
    private let queue = DispatchQueue(label: "UnsolicitedNotificationTests")

    private static let requestCharacteristics = [
        CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
        CharacteristicUUID.CONTROL_CHARACTERISTICS,
        CharacteristicUUID.AUTHORIZATION_CHARACTERISTICS,
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedResponseTimeout = VirtualPump.responseTimeout
        VirtualPump.responseTimeout = .seconds(2)
        server = FakeVirtualPumpServer()
        try server.start()
        centralDelegate = ConnectRecorder()
        central = CBCentralManager(delegate: centralDelegate, queue: queue, endpoint: server.endpoint, scanInterval: 0.2)

        let peripheral = try XCTUnwrap(central.retrievePeripherals(withIdentifiers: [server.peripheralId]).first)
        let connected = expectation(description: "didConnect")
        centralDelegate.onConnect = { _ in connected.fulfill() }
        central.connect(peripheral)
        wait(for: [connected], timeout: 5)
        try discover(peripheral)

        pumpManager = TandemPumpManager(state: TandemPumpManagerState(rawValue: [:]), bluetooth: StubPumpBluetooth())
        peripheralManager = TandemPeripheralManager(TandemBluetoothManager(), peripheral, pumpManager) { _ in }
        let subscribed = expectation(description: "subscribed")
        DispatchQueue.global().async { [peripheralManager] in
            for (service, characteristic) in CharacteristicUUID.notificationCharacteristics {
                peripheralManager?.startNotify(service: service, characteristic: characteristic)
            }
            subscribed.fulfill()
        }
        wait(for: [subscribed], timeout: 20)
    }

    override func tearDown() {
        if let peripheral = central?.retrieveConnectedPeripherals(withServices: []).first {
            central.cancelPeripheralConnection(peripheral)
        }
        server?.stop()
        VirtualPump.responseTimeout = savedResponseTimeout
        peripheralManager = nil
        pumpManager = nil
        central = nil
        centralDelegate = nil
        server = nil
        super.tearDown()
    }

    private func discover(_ peripheral: CBPeripheral) throws {
        let events = DiscoveryRecorder()
        peripheral.delegate = events
        let servicesFound = expectation(description: "didDiscoverServices")
        events.onServices = { servicesFound.fulfill() }
        peripheral.discoverServices(ServiceUUID.all)
        wait(for: [servicesFound], timeout: 2)

        let characteristicsFound = expectation(description: "didDiscoverCharacteristicsFor")
        characteristicsFound.expectedFulfillmentCount = 2
        events.onCharacteristics = { characteristicsFound.fulfill() }
        for service in try XCTUnwrap(peripheral.services) {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        wait(for: [characteristicsFound], timeout: 2)
        peripheral.delegate = nil
    }

    // MARK: - Wire

    /// `[opCode][txId][length][payload]` and its CRC16: one message as the pump frames it.
    private static func message(opCode: UInt8, txId: UInt8, payload: Data) -> Data {
        let body = Data([opCode, txId, UInt8(payload.count)]) + payload
        return body + CalculateCRC16(body)
    }

    private static func message(_ response: Message, txId: UInt8) -> Data {
        message(opCode: type(of: response).props.opCode, txId: txId, payload: response.cargo)
    }

    /// `message` cut into notifications of `[remaining][txId]` and at most `chunk` message bytes;
    /// 18 is what the 23-byte minimum ATT MTU leaves.
    private static func notifications(_ message: Data, txId: UInt8, chunk: Int = 18) -> [Data] {
        let pieces = stride(from: 0, to: message.count, by: chunk).map {
            message.subdata(in: $0 ..< min($0 + chunk, message.count))
        }
        return pieces.enumerated().map { index, piece in
            Data([UInt8(pieces.count - 1 - index), txId]) + piece
        }
    }

    private static func notifications(_ response: Message, txId: UInt8, chunk: Int = 18) -> [Data] {
        notifications(message(response, txId: txId), txId: txId, chunk: chunk)
    }

    /// A signed message's payload: `cargo` and the 24-byte trailer (time since reset, HMAC). Nothing
    /// checks the HMAC, so the trailer is filler that puts `value` at byte `tailByte` of the second
    /// notification at the minimum MTU, where it lands at random on the wire.
    private static func signedPayload(cargo: Data, putting value: UInt8, atTailByte tailByte: Int = 2) -> Data {
        var trailer = Data(repeating: 0xA5, count: 24)
        trailer[16 + tailByte - 3 - cargo.count] = value
        return cargo + trailer
    }

    /// faketandem's single-fragment, unsigned ErrorResponse (pkg/protocol BuildErrorResponse).
    private static func errorResponse(txId: UInt8, refusing request: UInt8) -> Data {
        notifications(message(opCode: ErrorResponse.props.opCode, txId: txId, payload: Data([request, 3])), txId: txId)[0]
    }

    // MARK: - Driving

    /// Answers every request with `respond`, given the request's txId; writes on other
    /// characteristics (qualifying-event acknowledgements) are left alone.
    private func answer(_ respond: @escaping (FakeVirtualPumpServer.Connection, UInt8) -> Void) {
        server.onWrite = { connection, characteristic, value in
            guard Self.requestCharacteristics.contains(characteristic), value[0] == 0 else { return }
            respond(connection, value[1])
        }
    }

    private func write<R: PumpRequest>(_ request: R) -> R.Response? {
        let answered = expectation(description: "\(R.self) returned")
        var response: R.Response?
        DispatchQueue.global().async { [peripheralManager] in
            response = peripheralManager?.write(request)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 15)
        return response
    }

    private func send(_ notifications: [Data], on characteristic: CBUUID, via connection: FakeVirtualPumpServer.Connection) {
        for notification in notifications {
            connection.notify(characteristic, notification)
        }
    }

    // MARK: - Responses to someone else's request

    func testAResponseUnderAnotherTxIdIsNotTheAnswer() {
        let current = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        answer { connection, txId in
            let theirs = CurrentBasalStatusResponse(profileBasalRate: 850, currentBasalRate: 0, basalModifiedBitmask: 1)
            self.send(Self.notifications(theirs, txId: txId &+ 7), on: current, via: connection)
            let ours = CurrentBasalStatusResponse(profileBasalRate: 850, currentBasalRate: 850, basalModifiedBitmask: 0)
            self.send(Self.notifications(ours, txId: txId), on: current, via: connection)
        }

        let response = write(CurrentBasalStatusRequest())

        XCTAssertEqual(response?.currentBasalRate, 0.85)
        XCTAssertEqual(response?.basalType, .basal)
    }

    func testALateAnswerToAWriteThatTimedOutIsNotTheNextWritesAnswer() {
        VirtualPump.responseTimeout = .milliseconds(500)
        let current = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        server.onWrite = nil
        XCTAssertNil(write(ApiVersionRequest()), "the first write goes unanswered")

        answer { connection, txId in
            self.send(Self.notifications(ApiVersionResponse(majorVersion: 1, minorVersion: 1), txId: txId &- 1), on: current, via: connection)
            self.send(Self.notifications(ApiVersionResponse(majorVersion: 2, minorVersion: 2), txId: txId), on: current, via: connection)
        }
        let response = write(ApiVersionRequest())

        XCTAssertEqual(response?.majorVersion, 2)
        XCTAssertEqual(response?.minorVersion, 2)
    }

    /// ControlIQIOBResponse is 22 message bytes, two notifications at the minimum MTU; another
    /// client's lands between ours.
    func testAnotherTxIdsPacketsInterleavedWithTheAnswerAreLeftOut() {
        let current = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        let ours = ControlIQIOBResponse(mudaliarIOB: 1234, timeRemainingSeconds: 600, mudaliarTotalIOB: 2345, swan6hrIOB: 3456, iobType: 1)
        let theirs = ControlIQIOBResponse(mudaliarIOB: 9999, timeRemainingSeconds: 9, mudaliarTotalIOB: 9999, swan6hrIOB: 9999, iobType: 0)
        answer { connection, txId in
            let mine = Self.notifications(ours, txId: txId)
            let other = Self.notifications(theirs, txId: txId &+ 1)
            XCTAssertEqual(mine.count, 2, "the fixture must fragment the way the pump does at the minimum MTU")
            self.send([mine[0], other[0], other[1], mine[1]], on: current, via: connection)
        }

        let response = write(ControlIQIOBRequest())

        XCTAssertEqual(response?.mudaliarIOB, 1234)
        XCTAssertEqual(response?.swan6hrIOB, 3456)
        XCTAssertEqual(response?.iobType, 1)
    }

    func testAnErrorResponseUnderAnotherTxIdLeavesTheWritePending() {
        let current = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        answer { connection, txId in
            connection.notify(current, Self.errorResponse(txId: txId &+ 5, refusing: ApiVersionRequest.props.opCode))
            self.send(Self.notifications(ApiVersionResponse(majorVersion: 3, minorVersion: 7), txId: txId), on: current, via: connection)
        }

        let response = write(ApiVersionRequest())

        XCTAssertEqual(response?.majorVersion, 3)
    }

    func testAnAnswerWhoseCRCDoesNotMatchIsNotTaken() {
        let current = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        answer { connection, txId in
            var corrupt = Self.notifications(ApiVersionResponse(majorVersion: 9, minorVersion: 9), txId: txId)[0]
            corrupt[corrupt.count - 1] ^= 0xFF
            connection.notify(current, corrupt)
            self.send(Self.notifications(ApiVersionResponse(majorVersion: 3, minorVersion: 7), txId: txId), on: current, via: connection)
        }

        let response = write(ApiVersionRequest())

        XCTAssertEqual(response?.majorVersion, 3)
        XCTAssertEqual(response?.minorVersion, 7)
    }

    /// A signed ErrorResponse is 31 message bytes; at the minimum MTU its second notification is HMAC.
    func testASignedErrorResponseInTwoNotificationsFailsTheWriteAtOnce() {
        let current = CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        answer { connection, txId in
            let payload = Self.signedPayload(cargo: Data([ApiVersionRequest.props.opCode, 3]), putting: ApiVersionResponse.props.opCode)
            let refusal = Self.notifications(Self.message(opCode: ErrorResponse.props.opCode, txId: txId, payload: payload), txId: txId)
            XCTAssertEqual(refusal.count, 2)
            self.send(refusal, on: current, via: connection)
        }

        let started = Date()
        let response = write(ApiVersionRequest())

        XCTAssertNil(response)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "the response timeout is 2 s")
    }

    // MARK: - The pump's own notifications

    /// The fill tubing screen polls while the stream runs. At the minimum MTU a signed stream message
    /// takes two notifications, and the second one's byte 2, where a response carries its opcode, is
    /// HMAC.
    func testAStreamPacketWhoseThirdByteIsThePendingOpcodeIsNotTheAnswer() {
        var buttonStates: [Int] = []
        let observation = pumpManager.fillTubingStateStream.sink { buttonStates.append($0.buttonState) }
        defer { observation.cancel() }
        answer { connection, txId in
            let payload = Self.signedPayload(cargo: Data([1]), putting: ApiVersionResponse.props.opCode)
            let stream = Self.notifications(
                Self.message(opCode: FillTubingStateStreamResponse.props.opCode, txId: 0x40, payload: payload),
                txId: 0x40
            )
            XCTAssertEqual(stream[1][2], ApiVersionResponse.props.opCode)
            self.send(stream, on: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS, via: connection)
            self.send(
                Self.notifications(ApiVersionResponse(majorVersion: 3, minorVersion: 7), txId: txId),
                on: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
                via: connection
            )
        }

        let response = write(ApiVersionRequest())
        queue.sync {}

        XCTAssertEqual(response?.majorVersion, 3)
        XCTAssertEqual(response?.minorVersion, 7)
        XCTAssertEqual(buttonStates, [1])
    }

    /// Byte 2 of a qualifying-event bitmask is battery and Basal-IQ status here, and ApiVersionResponse's
    /// opcode too.
    func testQualifyingEventsWhoseThirdByteIsThePendingOpcodeAreStillHandled() {
        let acknowledged = expectation(description: "qualifying events acknowledged")
        let events = Data([0x00, 0x00, ApiVersionResponse.props.opCode, 0x00])
        XCTAssertEqual(QualifyingEvent.fromRawBytes(events), [.battery, .basalIQStatus])
        server.onWrite = { connection, characteristic, value in
            if characteristic == CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS {
                acknowledged.fulfill()
                return
            }
            connection.notify(CharacteristicUUID.QUALIFYING_EVENTS_CHARACTERISTICS, events)
            self.send(
                Self.notifications(ApiVersionResponse(majorVersion: 3, minorVersion: 7), txId: value[1]),
                on: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS,
                via: connection
            )
        }

        let response = write(ApiVersionRequest())

        XCTAssertEqual(response?.majorVersion, 3)
        wait(for: [acknowledged], timeout: 2)
    }

    /// Each stream test ends on a message whose event shows that everything before it was handled.
    private func send(_ notifications: [Data], thenTheLast last: Data, awaiting lastEvent: XCTestExpectation) throws {
        let connection = try XCTUnwrap(server.latestAttachedConnection)
        send(notifications + [last], on: CharacteristicUUID.CONTROL_STREAM_CHARACTERISTICS, via: connection)
        wait(for: [lastEvent], timeout: 5)
    }

    func testASignedStreamMessageInTwoNotificationsIsOneEvent() throws {
        var buttonStates: [Int] = []
        let released = expectation(description: "the button released")
        let observation = pumpManager.fillTubingStateStream.sink {
            buttonStates.append($0.buttonState)
            if $0.buttonState == 0 { released.fulfill() }
        }
        defer { observation.cancel() }
        let opCode = FillTubingStateStreamResponse.props.opCode
        let pressed = Self.notifications(
            Self.message(opCode: opCode, txId: 0x41, payload: Self.signedPayload(cargo: Data([1]), putting: opCode)),
            txId: 0x41
        )
        XCTAssertEqual(pressed[1][2], opCode, "the second notification carries the stream's own opcode at byte 2")
        let releasing = Self.notifications(
            Self.message(opCode: opCode, txId: 0x42, payload: Self.signedPayload(cargo: Data([0]), putting: 0)),
            txId: 0x42,
            chunk: 255
        )[0]

        try send(pressed, thenTheLast: releasing, awaiting: released)

        XCTAssertEqual(queue.sync { buttonStates }, [1, 0])
    }

    /// pumpX2's DetectingCartridgeStateStreamResponse captures, 20% and 40%, the first refragmented
    /// as the minimum MTU carries it.
    func testDetectingCartridgeProgressInTwoNotificationsIsReported() throws {
        var progress: [Int] = []
        let reachedForty = expectation(description: "40%")
        let observation = pumpManager.detectingCartridgeStateStream.sink {
            progress.append($0.percentComplete)
            if $0.percentComplete == 40 { reachedForty.fulfill() }
        }
        defer { observation.cancel() }
        let twenty = try XCTUnwrap(Data(hexadecimalString: "0089e3891a140078c84020f4eabab90ec17db0da1b4d99095f92c063a1b1b9456a"))
        let forty = try XCTUnwrap(Data(hexadecimalString: "0089e3891a280078c840207ae3354ae4a861ca6cbaf2a6acc178441f68714f8a3f"))

        try send(Self.notifications(Data(twenty.dropFirst(2)), txId: twenty[1]), thenTheLast: forty, awaiting: reachedForty)

        XCTAssertEqual(queue.sync { progress }, [20, 40])
    }

    /// LoadCartridgeStateStreamResponse shares DetectingCartridgeStateStreamResponse's opcode and is
    /// one cargo byte shorter; whole, as a large MTU carries it, it is 32 bytes.
    func testLoadCartridgeStateIsNotReportedAsDetectingProgress() throws {
        var progress: [Int] = []
        let reachedForty = expectation(description: "40%")
        let observation = pumpManager.detectingCartridgeStateStream.sink {
            progress.append($0.percentComplete)
            if $0.percentComplete == 40 { reachedForty.fulfill() }
        }
        defer { observation.cancel() }
        let load = Self.notifications(
            Self.message(
                opCode: LoadCartridgeStateStreamResponse.props.opCode,
                txId: 0x43,
                payload: Self.signedPayload(cargo: Data([2]), putting: 0x00)
            ),
            txId: 0x43,
            chunk: 255
        )
        XCTAssertEqual(load.map(\.count), [32])
        let forty = try XCTUnwrap(Data(hexadecimalString: "0089e3891a280078c840207ae3354ae4a861ca6cbaf2a6acc178441f68714f8a3f"))

        try send(load, thenTheLast: forty, awaiting: reachedForty)

        XCTAssertEqual(queue.sync { progress }, [40])
    }
}
#endif
