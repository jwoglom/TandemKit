import Foundation

public extension Double {
    func roundTo(places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

public extension UInt32 {
    var hexadecimalString: String {
        let hex = String(self, radix: 16)
        return "0x" + String(repeating: "0", count: 8 - hex.count) + hex
    }
}
