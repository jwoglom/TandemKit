import Foundation

public enum BolusSource: Int {
    case quickBolus = 0
    case gui = 1
    case controlIQAutoBolus = 7
    case bluetoothRemoteBolus = 8

    public static func fromId(_ id: Int) -> BolusSource? {
        BolusSource(rawValue: id)
    }
}

public enum BolusType: Int, CaseIterable {
    case food1 = 1
    case correction = 2
    case extended = 4
    case food2 = 8

    public static func fromBitmask(_ bitmask: Int) -> Set<BolusType> {
        var ret = Set<BolusType>()
        for t in BolusType.allCases {
            if (bitmask & t.rawValue) != 0 {
                ret.insert(t)
            }
        }
        return ret
    }

    public static func toBitmask(_ types: [BolusType]) -> Int {
        var bitmask = 0
        for t in types {
            bitmask |= t.rawValue
        }
        return bitmask
    }
}
