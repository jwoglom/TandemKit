import Foundation

@MainActor
public struct PumpStateSupplier {
    static var pumpPairingCode: (() -> String)?
    static var jpakeDerivedSecretHex: (() -> String)?
    static var jpakeServerNonceHex: (() -> String)?
    public static var pumpTimeSinceReset: (() -> UInt32)?
    static var pumpApiVersion: (() -> ApiVersion)?
    static var controlIQSupported: () -> Bool = { false }
    public static var actionsAffectingInsulinDeliveryEnabled: () -> Bool = { false }

    // Flags mirroring PumpX2 PumpState fields
    static var tconnectAppConnectionSharing = false
    static var sendSharedConnectionResponseMessages = false
    static var relyOnConnectionSharingForAuthentication = false
    static var tconnectAppAlreadyAuthenticated = false
    static var tconnectAppConnectionSharingIgnoreInitialFailingWrite = false
    static var onlySnoopBluetooth = false

    static var processedResponseMessages = 0
    static var processedResponseMessagesFromUs = 0

    static var pairingCodeType: PairingCodeType = .long16Char

    public static var authenticationKey: () -> Data = {
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

    // MARK: - Configuration helpers

    public static func enableActionsAffectingInsulinDelivery() {
        actionsAffectingInsulinDeliveryEnabled = { true }
    }

    static func enableTconnectAppConnectionSharing() {
        tconnectAppConnectionSharing = true
    }

    static func enableSendSharedConnectionResponseMessages() {
        sendSharedConnectionResponseMessages = true
    }

    static func enableRelyOnConnectionSharingForAuthentication() {
        relyOnConnectionSharingForAuthentication = true
    }

    static func enableOnlySnoopBluetooth() {
        onlySnoopBluetooth = true
    }
}
