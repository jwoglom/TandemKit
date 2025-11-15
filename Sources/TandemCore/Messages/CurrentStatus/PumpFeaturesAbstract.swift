import Foundation

/// Base response for pump feature messages.
public class PumpFeaturesAbstractResponse: Message {
    public static let props = MessageProps(
        opCode: 0,
        size: 0,
        type: .Response,
        characteristic: .CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public func getPrimaryFeatures() -> Set<PumpFeaturesV1Response.PumpFeatureType> { fatalError("abstract") }
}
