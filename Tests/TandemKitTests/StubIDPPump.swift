import Foundation
@testable import TandemKit

/// In-memory stand-in for the pump's insulin delivery profile.
///
/// Answers the IDP read walk from its current segments and applies segment writes the way the pump
/// does, including rejecting one that would put two segments on the same start time. Tests that
/// stubbed a fixed segment list instead used to pass a sync that the pump had not actually
/// applied, which is exactly what the post-write read-back exists to catch.
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

    /// When false the pump answers every write with status 0 but leaves the profile untouched --
    /// an ACK is not proof the profile changed.
    var appliesWrites = true

    init(_ segments: [Segment], idpId: Int = 10) {
        self.segments = segments
        self.idpId = idpId
    }

    /// The status byte the pump would answer with.
    @discardableResult func apply(_ command: Command) -> Int {
        guard appliesWrites else {
            return 0
        }

        switch command {
        case let .modify(index, startTime, basalRate):
            guard index < segments.count, !collides(startTime: startTime, excluding: index) else { return 1 }
            segments[index] = Segment(startTime: startTime, basalRate: basalRate)
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

    /// Registers this profile as the pump's single, active one.
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
            return SetIDPSegmentResponse(status: self.apply(command), unknown: 0)
        }
    }
}
