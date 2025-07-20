import Foundation

struct InsulinDeliveryProfileRequestBuilder {
    private var queue: [Message] = [ProfileStatusRequest()]

    mutating func nextRequest() -> Message? {
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    mutating func processResponse(_ response: Message) {
        if let profiles = response as? ProfileStatusResponse {
            for id in profiles.idpSlotIds {
                queue.append(IDPSettingsRequest(idpId: id))
            }
        } else if let settings = response as? IDPSettingsResponse {
            for i in 1...settings.numberOfProfileSegments {
                queue.append(IDPSegmentRequest(idpId: settings.idpId, segmentIndex: i))
            }
        }
    }
}
