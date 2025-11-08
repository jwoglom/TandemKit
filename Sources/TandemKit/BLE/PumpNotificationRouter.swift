import Foundation
import CoreBluetooth
import TandemCore
import TandemBLE

final class PumpNotificationRouter: PeripheralManagerNotificationHandler {
    private final class Collector {
        var packetArrayList: PacketArrayList
        let metadata: MessageMetadata?

        init(packetArrayList: PacketArrayList, metadata: MessageMetadata?) {
            self.packetArrayList = packetArrayList
            self.metadata = metadata
        }
    }

    private let queue = DispatchQueue(label: "com.jwoglom.TandemKit.PumpNotificationRouter.queue", qos: .utility)
    private let logger = PumpLogger(label: "TandemKit.PumpNotificationRouter")

    private weak var session: PumpCommSession?
    private weak var peripheralManager: PeripheralManager?

    private var collectors: [CharacteristicUUID: [UInt8: Collector]] = [:]

    func start(with peripheralManager: PeripheralManager, session: PumpCommSession) {
        queue.async {
            self.peripheralManager?.notificationHandler = nil
            self.peripheralManager = peripheralManager
            self.session = session
            self.collectors.removeAll(keepingCapacity: false)
            peripheralManager.notificationHandler = self
            self.logger.info("[PumpNotificationRouter] attached to peripheral manager")
        }
    }

    func stop(with peripheralManager: PeripheralManager? = nil) {
        queue.async {
            let manager = peripheralManager ?? self.peripheralManager
            manager?.notificationHandler = nil
            self.peripheralManager = nil
            self.session = nil
            self.collectors.removeAll(keepingCapacity: false)
            self.logger.info("[PumpNotificationRouter] detached from peripheral manager")
        }
    }

    // MARK: - PeripheralManagerNotificationHandler

    func peripheralManager(_ manager: PeripheralManager,
                           didReceiveNotification value: Data,
                           for characteristic: CBCharacteristic) {
        guard let uuid = CharacteristicUUID(rawValue: characteristic.uuid.uuidString.uppercased()) else {
            return
        }

        queue.async { [weak self] in
            self?.ingest(value, characteristic: uuid)
        }
    }

    // MARK: - Parsing

    private func ingest(_ data: Data, characteristic: CharacteristicUUID) {
        guard data.count >= 5 else {
            logger.warning("[PumpNotificationRouter] ignoring short packet len=\(data.count) characteristic=\(characteristic.prettyName)")
            return
        }

        let opCode = data[2]
        let txId = data[3]

        var reportedLength = Int(Int8(bitPattern: data[4]))
        if reportedLength < 0 {
            reportedLength += 256
        }

        let candidates = MessageRegistry.bestMatches(opCode: opCode,
                                                     characteristic: characteristic,
                                                     payloadLength: reportedLength)
        let metadata = candidates.first

        let expectedSize: UInt8
        if let meta = metadata, !meta.stream && !meta.variableSize {
            expectedSize = UInt8(truncatingIfNeeded: meta.size)
        } else {
            expectedSize = UInt8(truncatingIfNeeded: reportedLength)
        }
        let isSigned = metadata?.signed ?? false

        var perCharacteristic = collectors[characteristic] ?? [:]
        let collector: Collector
        if let existing = perCharacteristic[txId] {
            collector = existing
        } else {
            var packetArray = PacketArrayList(expectedOpCode: opCode,
                                              expectedCargoSize: expectedSize,
                                              expectedTxId: txId,
                                              isSigned: isSigned,
                                              requestMetadata: nil,
                                              responseMetadata: metadata)
            collector = Collector(packetArrayList: packetArray, metadata: metadata)
            perCharacteristic[txId] = collector
            collectors[characteristic] = perCharacteristic
        }

        do {
            try collector.packetArrayList.validatePacket(data)
        } catch {
            logger.error("[PumpNotificationRouter] validation failed opCode=\(opCode) txId=\(txId) error=\(String(describing: error))")
            perCharacteristic.removeValue(forKey: txId)
            collectors[characteristic] = perCharacteristic
            return
        }

        if collector.packetArrayList.needsMorePacket() {
            collectors[characteristic] = perCharacteristic
            return
        }

        let authKey = PumpStateSupplier.authenticationKey()
        let isValid = collector.packetArrayList.validate(authKey)
        if !isValid {
            logger.warning("[PumpNotificationRouter] CRC/HMAC validation failed opCode=\(opCode) txId=\(txId)")
        }

        let messageData = collector.packetArrayList.buildMessageData()
        let payload = Data(messageData.dropFirst(3))

        perCharacteristic.removeValue(forKey: txId)
        collectors[characteristic] = perCharacteristic

        let message: Message?
        if let meta = metadata {
            message = meta.type.init(cargo: payload)
        } else {
            message = BTResponseParser.decodeMessage(opCode: collector.packetArrayList.opCode,
                                                     characteristic: characteristic.cbUUID,
                                                     payload: payload)
        }

        guard let finalMessage = message else {
            logger.error("[PumpNotificationRouter] unable to decode message opCode=\(opCode) txId=\(txId)")
            return
        }

        guard let session else {
            logger.warning("[PumpNotificationRouter] dropping message opCode=\(opCode) txId=\(txId) – missing session")
            return
        }

        let finalMetadata = metadata ?? MessageRegistry.metadata(for: finalMessage)
        session.runSession(withName: "Notification \(characteristic.prettyName) txId=\(txId)") {
            session.handleIncoming(message: finalMessage,
                                   metadata: finalMetadata,
                                   characteristic: characteristic,
                                   txId: txId)
        }
    }
}
