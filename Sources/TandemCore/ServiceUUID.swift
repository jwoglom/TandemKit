import CoreBluetooth

public enum ServiceUUID {
    // All pump operations
    static let PUMP_SERVICE = CBUUID(string: "0000fdfb-0000-1000-8000-00805f9b34fb")

    // Tandem Device Update service
    static let TDU_SERVICE = CBUUID(string: "0000fdfa-0000-1000-8000-00805f9b34fb")

    // Bluetooth Device Information service (DIS)
    static let DIS_SERVICE = CBUUID(string: "0000180A-0000-1000-8000-00805f9b34fb")

    // Generic Access service
    static let GENERIC_ACCESS_SERVICE = CBUUID(string: "00001800-0000-1000-8000-00805f9b34fb")

    // Generic Attribute service
    static let GENERIC_ATTRIBUTE_SERVICE = CBUUID(string: "00001801-0000-1000-8000-00805f9b34fb")

    static let all: [CBUUID] = [
        PUMP_SERVICE,
        TDU_SERVICE,
        DIS_SERVICE,
        GENERIC_ACCESS_SERVICE,
        GENERIC_ATTRIBUTE_SERVICE
    ]
}
