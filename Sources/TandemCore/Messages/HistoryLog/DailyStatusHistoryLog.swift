import Foundation

public class DailyStatusHistoryLog: HistoryLog {
    public static let typeId = 313

    public let sensorType: Int
    public let userMode: Int
    public let pumpControlState: Int
    /// Raw weight unit, see `WeightUnit`.
    public let weightUnit: Int
    /// Configured weight, in the unit given by `weightUnit`.
    public let weight: Int
    /// Current total daily insulin (population) estimate, in units.
    public let currentTdiPop: Int

    public required init(cargo: Data) {
        // Layout per the Tandem Source event schema: PumpControlState @10, usermode @11, SensorType @12,
        // WeightUnit @13, Weight u16 @14, currentTDIpop @16.
        pumpControlState = Int(cargo[cargo.startIndex + 10])
        userMode = Int(cargo[cargo.startIndex + 11])
        sensorType = Int(cargo[cargo.startIndex + 12])
        weightUnit = Int(cargo[cargo.startIndex + 13])
        weight = Bytes.readShort(cargo, 14)
        currentTdiPop = Int(cargo[cargo.startIndex + 16])
        super.init(cargo: cargo)
    }

    public init(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sensorType: Int,
        userMode: Int,
        pumpControlState: Int,
        weightUnit: Int = 0,
        weight: Int = 0,
        currentTdiPop: Int = 0
    ) {
        let payload = DailyStatusHistoryLog.buildCargo(
            pumpTimeSec: pumpTimeSec,
            sequenceNum: sequenceNum,
            sensorType: sensorType,
            userMode: userMode,
            pumpControlState: pumpControlState,
            weightUnit: weightUnit,
            weight: weight,
            currentTdiPop: currentTdiPop
        )
        self.sensorType = sensorType
        self.userMode = userMode
        self.pumpControlState = pumpControlState
        self.weightUnit = weightUnit
        self.weight = weight
        self.currentTdiPop = currentTdiPop
        super.init(cargo: payload)
    }

    public static func buildCargo(
        pumpTimeSec: UInt32,
        sequenceNum: UInt32,
        sensorType: Int,
        userMode: Int,
        pumpControlState: Int,
        weightUnit: Int = 0,
        weight: Int = 0,
        currentTdiPop: Int = 0
    ) -> Data {
        HistoryLog.fillCargo(
            Bytes.combine(
                HistoryLog.typeIdBytes(typeId),
                Bytes.toUint32(pumpTimeSec),
                Bytes.toUint32(sequenceNum),
                Data([UInt8(pumpControlState & 0xFF), UInt8(userMode & 0xFF), UInt8(sensorType & 0xFF), UInt8(weightUnit & 0xFF)]),
                Bytes.firstTwoBytesLittleEndian(weight),
                Data([UInt8(currentTdiPop & 0xFF)])
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

    public enum WeightUnit: Int {
        case notSet = 0
        case pounds = 1
        case kilograms = 2
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

    public var weightUnitEnum: WeightUnit? {
        WeightUnit(rawValue: weightUnit)
    }

    public var description: String {
        "DailyStatusHistoryLog(cargo=\(cargo.hexadecimalString), sensorType=\(sensorType), userMode=\(userMode), pumpControlState=\(pumpControlState), weightUnit=\(weightUnit), weight=\(weight), currentTdiPop=\(currentTdiPop))"
    }
}
