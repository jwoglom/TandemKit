import Foundation

public extension Double {
    func roundTo(places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

public extension UInt32 {
    var hexadecimalString: String {
        var hex = String(self, radix: 16)
        for i in 0..<(8 - hex.count) {
            hex += "0"
        }
        return "0x\(hex)"
    }
}
