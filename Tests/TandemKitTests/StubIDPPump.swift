import Foundation
@testable import TandemKit

/// In-memory stand-in for the pump's insulin delivery profile: answers the IDP read walk and
/// applies segment writes the way the pump does, rejecting one that would collide on a start time
/// or flags a start time on segment 0, which a Mobi refused.
final class StubIDPPump {
    struct Segment: Equatable, CustomStringConvertible {
        var startTime: Int
        var basalRate: Int

        var description: String { "\(startTime)/\(basalRate)" }
    }

    /// A modify carries only the fields its status mask flags; nil is a field it leaves alone.
    enum Command: Equatable, CustomStringConvertible {
        case modify(segment: Int, startTime: Int? = nil, basalRate: Int? = nil)
        case create(startTime: Int, basalRate: Int)
        case delete(segment: Int)

        /// Nil for a mask Tandem's app never sends: a modify flagging anything but start time and
        /// basal rate, or a create or delete flagging fewer than all five fields.
        init?(_ request: SetIDPSegmentRequest) {
            let fields = request.idpStatus
            let allFields = Set(IDPSegmentResponse.IDPSegmentStatus.allCases)
            switch request.operation {
            case .modifySegmentId:
                guard fields.isSubset(of: [.START_TIME, .BASAL_RATE]) else { return nil }
                self = .modify(
                    segment: request.segmentIndex,
                    startTime: fields.contains(.START_TIME) ? request.profileStartTime : nil,
                    basalRate: fields.contains(.BASAL_RATE) ? request.profileBasalRate : nil
                )
            case .createSegment:
                guard fields == allFields else { return nil }
                self = .create(startTime: request.profileStartTime, basalRate: request.profileBasalRate)
            case .deleteSegmentId:
                guard fields == allFields else { return nil }
                self = .delete(segment: request.segmentIndex)
            case .none:
                return nil
            }
        }

        var description: String {
            switch self {
            case let .modify(segment, startTime, basalRate):
                "modify(\(segment) -> start \(startTime.map(String.init) ?? "-"), rate \(basalRate.map(String.init) ?? "-"))"
            case let .create(startTime, basalRate): "create(\(startTime)/\(basalRate))"
            case let .delete(segment): "delete(\(segment))"
            }
        }
    }

    private(set) var segments: [Segment]
    let idpId: Int

    /// When false, writes are answered with status 0 but never applied.
    var appliesWrites = true

    init(_ segments: [Segment], idpId: Int = 10) {
        self.segments = segments
        self.idpId = idpId
    }

    @discardableResult func apply(_ command: Command) -> Int {
        guard appliesWrites else {
            return 0
        }

        switch command {
        case let .modify(index, startTime, basalRate):
            guard index < segments.count, index != 0 || startTime == nil else { return 1 }
            let updated = Segment(
                startTime: startTime ?? segments[index].startTime,
                basalRate: basalRate ?? segments[index].basalRate
            )
            guard !collides(startTime: updated.startTime, excluding: index) else { return 1 }
            segments[index] = updated
            return 0
        case let .create(startTime, basalRate):
            guard !collides(startTime: startTime, excluding: nil) else { return 1 }
            segments.append(Segment(startTime: startTime, basalRate: basalRate))
            return 0
        case let .delete(index):
            guard index != 0, index < segments.count else { return 1 }
            segments.remove(at: index)
            return 0
        }
    }

    private func collides(startTime: Int, excluding index: Int?) -> Bool {
        segments.enumerated().contains { offset, segment in
            offset != index && segment.startTime == startTime
        }
    }

    func install(on bluetooth: StubPumpBluetooth) {
        bluetooth.stub(ProfileStatusRequest.self, with: ProfileStatusResponse(
            numberOfProfiles: 1,
            idpSlot0Id: idpId,
            idpSlot1Id: 0,
            idpSlot2Id: 0,
            idpSlot3Id: 0,
            idpSlot4Id: 0,
            idpSlot5Id: 0,
            activeSegmentIndex: 0
        ))

        bluetooth.stub(IDPSettingsRequest.self) { _ in
            IDPSettingsResponse(
                idpId: self.idpId,
                name: "Test",
                numberOfProfileSegments: self.segments.count,
                insulinDuration: 180,
                maxBolus: 0,
                carbEntry: true
            )
        }

        bluetooth.stub(IDPSegmentRequest.self) { request in
            guard let request = request as? IDPSegmentRequest, request.segmentIndex < self.segments.count else {
                return nil
            }
            let segment = self.segments[request.segmentIndex]
            return IDPSegmentResponse(
                idpId: self.idpId,
                segmentIndex: request.segmentIndex,
                profileStartTime: segment.startTime,
                profileBasalRate: segment.basalRate,
                profileCarbRatio: 10000,
                profileTargetBG: 110,
                profileISF: 50,
                idpStatusId: 31
            )
        }

        bluetooth.stub(SetIDPSegmentRequest.self) { request in
            guard let request = request as? SetIDPSegmentRequest else { return nil }
            guard let command = Command(request) else { return SetIDPSegmentResponse(status: 1, unknown: 0) }
            return SetIDPSegmentResponse(status: self.apply(command), unknown: 0)
        }
    }
}
