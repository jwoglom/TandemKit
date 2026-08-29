import Foundation

/// Request the current reservoir/load status.
public class LoadStatusRequest: PumpRequest {
    public typealias Response = LoadStatusResponse

    public static let props = MessageProps(
        opCode: 20,
        size: 0,
        type: .Request,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data

    public required init(cargo: Data) {
        self.cargo = cargo
    }

    public init() {
        cargo = Data()
    }

    public var description: String {
        "LoadStatusRequest(cargo=\(cargo.hexadecimalString))"
    }
}

/// Response with reservoir/load status information.
///
/// Binary layout (3 bytes):
///   byte 0: isLoadingActive (bool, nonzero = true)
///   byte 1: loadStateId (LoadState ordinal)
///   byte 2: primeStatusId (PrimeTubingStatus or PrimeNudgeStatus, depending on loadState)
public class LoadStatusResponse: Message {
    public static let props = MessageProps(
        opCode: 21,
        size: 3,
        type: .Response,
        characteristic: CharacteristicUUID.CURRENT_STATUS_CHARACTERISTICS
    )

    public var cargo: Data
    public var isLoadingActiveId: Int
    public var isLoadingActive: Bool
    public var loadStateId: Int
    public var primeStatusId: Int

    public required init(cargo: Data) {
        self.cargo = cargo
        isLoadingActiveId = Int(cargo[0])
        isLoadingActive = cargo[0] != 0
        loadStateId = Int(cargo[1])
        primeStatusId = Int(cargo[2])
    }

    public init(isLoadingActive: Bool, loadStateId: Int, primeStatusId: Int) {
        cargo = Data([
            isLoadingActive ? 1 : 0,
            UInt8(truncatingIfNeeded: loadStateId),
            UInt8(truncatingIfNeeded: primeStatusId)
        ])
        isLoadingActiveId = isLoadingActive ? 1 : 0
        self.isLoadingActive = isLoadingActive
        self.loadStateId = loadStateId
        self.primeStatusId = primeStatusId
    }

    public var loadState: LoadState {
        LoadState(rawValue: loadStateId) ?? .unknown
    }

    public var primeTubingStatus: PrimeTubingStatus? {
        guard loadState == .primeTubing else { return nil }
        return PrimeTubingStatus(rawValue: primeStatusId) ?? .unknown
    }

    public var primeNudgeStatus: PrimeNudgeStatus? {
        guard loadState == .primeNudge else { return nil }
        return PrimeNudgeStatus(rawValue: primeStatusId) ?? .unknown
    }

    /// True when loadState is one of changeCartridge, loadCartridge, or primeTubing.
    public var isInLoadingState: Bool {
        loadState == .changeCartridge || loadState == .loadCartridge || loadState == .primeTubing
    }

    public enum LoadState: Int {
        case changeCartridge = 0
        case loadCartridge = 1
        case primeTubing = 2
        case primeCannula = 3
        case primeNudge = 4
        case invalid = 5
        case unknown = 6
    }

    public enum PrimeTubingStatus: Int {
        case stop = 0
        case start = 1
        case enteredCanExit = 2
        case enteredCannotExit = 3
        case suspended = 4
        case unknown = 5
    }

    public enum PrimeNudgeStatus: Int {
        case start = 0
        case complete = 1
        case unknown = 2
    }

    /// Legacy compatibility: maps to isLoadingActiveId.
    public var status: Int { isLoadingActiveId }

    /// Legacy compatibility: combines loadStateId and primeStatusId as a short.
    public var unknown: Int { (loadStateId & 0xFF) | ((primeStatusId & 0xFF) << 8) }

    public var description: String {
        "LoadStatusResponse(cargo=\(cargo.hexadecimalString), isLoadingActive=\(isLoadingActive), loadState=\(loadState), loadStateId=\(loadStateId), primeStatusId=\(primeStatusId))"
    }
}
