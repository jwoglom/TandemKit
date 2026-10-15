import CoreBluetooth
import Foundation

/// Sorts the messages that arrive with no write waiting for them. One under the txId of a write
/// that timed out is that write's late answer. Anything else answers another app on the phone: the
/// pump has one link to the phone, and iOS notifies every app subscribed to a characteristic. That
/// app's traffic comes in bursts, such as its connect sequence, so only the first message of a
/// burst is worth more than a debug line.
struct UnsolicitedNotificationLog {
    enum Kind: Equatable {
        case lateAnswer(request: String, secondsAfterGivingUp: TimeInterval)
        /// The first message after `quietGap` without one.
        case startsBurst
        /// A later message of the burst; the first is 1.
        case inBurst(Int)
    }

    static let quietGap: TimeInterval = 10
    /// How long after its timeout a write's answer is still told apart as late.
    static let lateAnswerWindow: TimeInterval = 120

    private struct Unanswered {
        let request: String
        let txId: UInt8
        let responseOpCode: UInt8
        let characteristic: CBUUID
        let gaveUpAt: Date
    }

    private var unanswered: [Unanswered] = []
    private var lastAt: Date?
    private var burstCount = 0

    mutating func recordUnanswered(request: String, txId: UInt8, responseOpCode: UInt8, characteristic: CBUUID, at date: Date) {
        forgetExpired(at: date)
        unanswered.removeAll { $0.txId == txId }
        unanswered.append(Unanswered(
            request: request,
            txId: txId,
            responseOpCode: responseOpCode,
            characteristic: characteristic,
            gaveUpAt: date
        ))
    }

    mutating func classify(_ message: AssembledMessage, on characteristic: CBUUID, at date: Date) -> Kind {
        forgetExpired(at: date)
        let isRefusal = message.opCode == ErrorResponse.props.opCode
        if let index = unanswered.firstIndex(where: {
            $0.txId == message.txId
                && ($0.responseOpCode == message.opCode && $0.characteristic == characteristic
                    || isRefusal && characteristic == CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS)
        }) {
            let write = unanswered.remove(at: index)
            return .lateAnswer(request: write.request, secondsAfterGivingUp: date.timeIntervalSince(write.gaveUpAt))
        }

        defer { lastAt = date }
        if let lastAt, date.timeIntervalSince(lastAt) < Self.quietGap {
            burstCount += 1
            return .inBurst(burstCount)
        }
        burstCount = 1
        return .startsBurst
    }

    private mutating func forgetExpired(at date: Date) {
        unanswered.removeAll { date.timeIntervalSince($0.gaveUpAt) > Self.lateAnswerWindow }
    }
}
