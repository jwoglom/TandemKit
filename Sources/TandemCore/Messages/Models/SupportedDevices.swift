public enum SupportedDevices: Sendable {
    case all
    case tslimX2Only
    case mobiOnly

    public var value: [PumpModel] {
        switch self {
        case .all:
            return [.TSLIM_X2, .MOBI]
        case .tslimX2Only:
            return [.TSLIM_X2]
        case .mobiOnly:
            return [.MOBI]
        }
    }
}
