import Foundation

/// Base response shared by ControlIQInfoV1 and ControlIQInfoV2.
public class ControlIQInfoAbstractResponse: Message {
    public class var props: MessageProps {
        MessageProps(
            opCode: 0,
            size: 0,
            type: .Response,
            characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
        )
    }

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public func getClosedLoopEnabled() -> Bool { fatalError("abstract") }
    public func getWeight() -> Int { fatalError("abstract") }
    public func getWeightUnitId() -> Int { fatalError("abstract") }
    public func getTotalDailyInsulin() -> Int { fatalError("abstract") }
    public func getCurrentUserModeTypeId() -> Int { fatalError("abstract") }
    public func getByte6() -> Int { fatalError("abstract") }
    public func getByte7() -> Int { fatalError("abstract") }
    public func getByte8() -> Int { fatalError("abstract") }
    public func getControlStateType() -> Int { fatalError("abstract") }

    public var currentUserModeType: UserModeType? { UserModeType(rawValue: getCurrentUserModeTypeId()) }
    public var weightUnit: WeightUnit? { WeightUnit(rawValue: getWeightUnitId()) }

    /// Whether the pump has a body weight stored.
    ///
    /// A pump that has never had one entered reports zero, which is not a weight —
    /// it means "not configured". Echoing it back in a
    /// `ChangeControlIQSettingsRequest` is what makes enabling Control-IQ fail.
    public var isWeightConfigured: Bool { getWeight() > 0 }

    /// Whether the pump has a total daily insulin amount stored. Zero means "not
    /// configured", not "no insulin".
    public var isTotalDailyInsulinConfigured: Bool { getTotalDailyInsulin() > 0 }

    /// Body weight as stored on the pump, or `nil` when it has never been configured.
    public var configuredWeight: Int? { isWeightConfigured ? getWeight() : nil }

    /// Total daily insulin as stored on the pump, or `nil` when it has never been
    /// configured.
    public var configuredTotalDailyInsulin: Int? {
        isTotalDailyInsulinConfigured ? getTotalDailyInsulin() : nil
    }

    /// ControlIQ user modes.
    public enum UserModeType: Int, RawRepresentable {
        case standard = 0
        case sleep = 1
        case exercise = 2
        case notSupportedEatingSoon = 3
    }

    /// Weight units. Retained as a nested name for existing callers; the canonical
    /// type is `ControlIQWeightUnit`, shared with `ChangeControlIQSettingsRequest`
    /// so a weight can never be read in one unit and written in another.
    public typealias WeightUnit = ControlIQWeightUnit

    open var description: String {
        "ControlIQInfoAbstractResponse(cargo=\(cargo.hexadecimalString), currentUserModeType=\(String(describing: currentUserModeType)), weightUnit=\(String(describing: weightUnit)))"
    }
}
