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

    enum Command: Equatable, CustomStringConvertible {
        case modify(segment: Int, startTime: Int, basalRate: Int)
        case create(startTime: Int, basalRate: Int)
        case delete(segment: Int)

        init?(_ request: SetIDPSegmentRequest) {
            switch request.operation {
            case .modifySegmentId:
                self = .modify(
                    segment: request.segmentIndex,
                    startTime: request.profileStartTime,
                    basalRate: request.profileBasalRate
                )
            case .createSegment:
                self = .create(startTime: request.profileStartTime, basalRate: request.profileBasalRate)
            case .deleteSegmentId:
                self = .delete(segment: request.segmentIndex)
            case .none:
                return nil
            }
        }

        var description: String {
            switch self {
            case let .modify(segment, startTime, basalRate): "modify(\(segment) -> \(startTime)/\(basalRate))"
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

    /// A modify changes only the fields `changedFields` flags; nil flags the ones that differ.
    @discardableResult func apply(
        _ command: Command,
        changedFields: Set<IDPSegmentResponse.IDPSegmentStatus>? = nil
    ) -> Int {
        guard appliesWrites else {
            return 0
        }

        switch command {
        case let .modify(index, startTime, basalRate):
            guard index < segments.count else { return 1 }
            let current = segments[index]
            let changedFields = changedFields ?? Self.differingFields(current, startTime: startTime, basalRate: basalRate)
            guard index != 0 || !changedFields.contains(.START_TIME) else { return 1 }
            let updated = Segment(
                startTime: changedFields.contains(.START_TIME) ? startTime : current.startTime,
                basalRate: changedFields.contains(.BASAL_RATE) ? basalRate : current.basalRate
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

    private static func differingFields(
        _ segment: Segment,
        startTime: Int,
        basalRate: Int
    ) -> Set<IDPSegmentResponse.IDPSegmentStatus> {
        var fields: Set<IDPSegmentResponse.IDPSegmentStatus> = []
        if segment.startTime != startTime { fields.insert(.START_TIME) }
        if segment.basalRate != basalRate { fields.insert(.BASAL_RATE) }
        return fields
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
            guard let request = request as? SetIDPSegmentRequest, let command = Command(request) else { return nil }
            return SetIDPSegmentResponse(status: self.apply(command, changedFields: request.idpStatus), unknown: 0)
        }
    }
}
