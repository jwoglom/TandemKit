public enum KnownDeviceModel: Sendable {
    case tslimX2
    case mobi
}

public enum SupportedDevices: Sendable {
    case all
    case tslimX2Only
    case mobiOnly

    public var value: [KnownDeviceModel] {
        switch self {
        case .all:
            return [.tslimX2, .mobi]
        case .tslimX2Only:
            return [.tslimX2]
        case .mobiOnly:
            return [.mobi]
        }
    }
}
