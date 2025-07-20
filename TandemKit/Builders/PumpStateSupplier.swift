import Foundation

struct PumpStateSupplier {
    static var pumpPairingCode: (() -> String)?
    static var jpakeDerivedSecretHex: (() -> String)?
    static var jpakeServerNonceHex: (() -> String)?
    static var pumpTimeSinceReset: (() -> UInt32)?
    static var pumpApiVersion: (() -> ApiVersion)?
    static var controlIQSupported: () -> Bool = { false }
    static var actionsAffectingInsulinDeliveryEnabled: () -> Bool = { false }

    static var authenticationKey: () -> Data = {
        determinePumpAuthKey()
    }

    private static func determinePumpAuthKey() -> Data {
        let derivedSecret = jpakeDerivedSecretHex?()
        let serverNonce = jpakeServerNonceHex?()
        let code = pumpPairingCode?()

        if (derivedSecret == nil || derivedSecret!.isEmpty) && (code == nil || code!.isEmpty) {
            fatalError("no pump authenticationKey")
        }

        if let ds = derivedSecret, !ds.isEmpty,
           let sn = serverNonce, !sn.isEmpty,
           let secretBytes = Data(hexadecimalString: ds),
           let nonceBytes = Data(hexadecimalString: sn) {
            let authKey = Hkdf.build(nonce: nonceBytes, keyMaterial: secretBytes)
            return authKey
        }

        if let code = code {
            return Data(code.utf8)
        }
        return Data()
    }
}
