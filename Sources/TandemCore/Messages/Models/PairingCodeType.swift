import Foundation

enum PairingCodeType: String {
    case long16Char = "LONG_16CHAR"
    case short6Char = "SHORT_6CHAR"

    func filterCharacters(_ pairingCode: String) -> String {
        var processed = ""
        for c in pairingCode {
            switch self {
            case .long16Char:
                if c.isLetter || c.isNumber { processed.append(c) }
            case .short6Char:
                if c.isNumber { processed.append(c) }
            }
        }
        return processed
    }

    static func fromLabel(_ label: String) -> PairingCodeType? {
        return PairingCodeType(rawValue: label)
    }
}
