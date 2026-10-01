import Foundation

public class DailyStatusHistoryLog: HistoryLog {
    public static let typeId = 313

    public let sensorType: Int
    public let userMode: Int
    public let pumpControlState: Int

    public required init(cargo: Data) {
        sensorType = Int(cargo[11])
        userMode = Int(cargo[12])
        pumpControlState = Int(cargo[13])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sensorType: Int,
        userMode: Int,
        pumpControlState: Int
    ) {
        let payload = DailyStatusHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            sensorType: sensorType,
            userMode: userMode,
            pumpControlState: pumpControlState
        )
        self.sensorType = sensorType
        self.userMode = userMode
        self.pumpControlState = pumpControlState
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sensorType: Int,
        userMode: Int,
        pumpControlState: Int
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([0, UInt8(sensorType & 0xFF), UInt8(userMode & 0xFF), UInt8(pumpControlState & 0xFF)])
            )
        )
    }

    public enum SensorType: Int {
        case cgmTypeNone = 0
        case cgmTypeDexcomG6 = 1
        case cgmTypeLibre2 = 2
        case cgmTypeDexcomG7 = 3
        case cgmTypeLibre3 = 4
    }

    public enum UserMode: Int {
        case normal = 0
        case sleeping = 1
        case exercising = 2
    }

    public enum PumpControlState: Int {
        /// No cartridge installed.
        case pcmNoControl = 0
        case pcmOpenLoop = 1
        case pcmPining = 2
        case pcmClosedLoop = 3
    }

    public var sensorTypeEnum: SensorType? {
        SensorType(rawValue: sensorType)
    }

    public var userModeEnum: UserMode? {
        UserMode(rawValue: userMode)
    }

    public var pumpControlStateEnum: PumpControlState? {
        PumpControlState(rawValue: pumpControlState)
    }

    public var description: String {
        "DailyStatusHistoryLog(cargo=\(cargo.hexadecimalString), sensorType=\(sensorType), userMode=\(userMode), pumpControlState=\(pumpControlState))"
    }
}
