import LoopKit

public struct SimpleReservoirValue: ReservoirValue {
    public let startDate: Date
    public let unitVolume: Double

    public init(startDate: Date, unitVolume: Double) {
        self.startDate = startDate
        self.unitVolume = unitVolume
    }
}
