import Foundation

public enum PumpPairingCodeValidationError: Error {
    case empty
    case invalidLength
}

extension PumpPairingCodeValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty:
            return LocalizedString(
                "Enter the pairing code shown on your pump.",
                comment: "Error message when pairing code text field is empty"
            )
        case .invalidLength:
            return LocalizedString(
                "Pairing codes are either 6 digits or 16 letters and numbers.",
                comment: "Error message when pairing code entry has the wrong length"
            )
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .empty:
            return LocalizedString(
                "Type the code displayed on the pump screen.",
                comment: "Recovery suggestion when pairing code text field is empty"
            )
        case .invalidLength:
            return LocalizedString(
                "Check the code on the pump and try again.",
                comment: "Recovery suggestion when pairing code entry has the wrong length"
            )
        }
    }
}

public enum PumpStateSupplier {
    private static let lock = NSRecursiveLock()

    private static func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

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

    public static func currentPumpApiVersion() -> ApiVersion? {
        withLock { pumpApiVersion?() }
    }

    private static func determinePumpAuthKey() -> Data {
        let (derivedSecret, serverNonce, code) = withLock {
            (jpakeDerivedSecretHex?(), jpakeServerNonceHex?(), pumpPairingCode?())
        }

        if derivedSecret == nil || derivedSecret!.isEmpty, code == nil || code!.isEmpty {
            fatalError("no pump authenticationKey")
        }

        if let ds = derivedSecret, !ds.isEmpty,
           let sn = serverNonce, !sn.isEmpty,
           let secretBytes = Data(hexadecimalString: ds),
           let nonceBytes = Data(hexadecimalString: sn)
        {
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
        setActionsAffectingInsulinDeliveryEnabled(true)
    }

    public static func disableActionsAffectingInsulinDelivery() {
        setActionsAffectingInsulinDeliveryEnabled(false)
    }

    public static func setActionsAffectingInsulinDeliveryEnabled(_ enabled: Bool) {
        withLock {
            actionsAffectingInsulinDeliveryEnabled = { enabled }
        }
    }

    public static func enableTconnectAppConnectionSharing() {
        withLock { tconnectAppConnectionSharing = true }
    }

    public static func disableTconnectAppConnectionSharing() {
        withLock { tconnectAppConnectionSharing = false }
    }

    public static func enableSendSharedConnectionResponseMessages() {
        withLock { sendSharedConnectionResponseMessages = true }
    }

    public static func disableSendSharedConnectionResponseMessages() {
        withLock { sendSharedConnectionResponseMessages = false }
    }

    public static func enableRelyOnConnectionSharingForAuthentication() {
        withLock { relyOnConnectionSharingForAuthentication = true }
    }

    public static func disableRelyOnConnectionSharingForAuthentication() {
        withLock { relyOnConnectionSharingForAuthentication = false }
    }

    public static func enableOnlySnoopBluetooth() {
        withLock { onlySnoopBluetooth = true }
    }

    public static func disableOnlySnoopBluetooth() {
        withLock { onlySnoopBluetooth = false }
    }

    public static func setConnectionSharingEnabled(_ enabled: Bool) {
        if enabled {
            enableTconnectAppConnectionSharing()
            enableSendSharedConnectionResponseMessages()
            enableRelyOnConnectionSharingForAuthentication()
        } else {
            disableTconnectAppConnectionSharing()
            disableSendSharedConnectionResponseMessages()
            disableRelyOnConnectionSharingForAuthentication()
        }
    }

    public static func disableConnectionSharing() {
        setConnectionSharingEnabled(false)
    }

    public static func connectionSharingEnabled() -> Bool {
        withLock {
            tconnectAppConnectionSharing &&
                sendSharedConnectionResponseMessages &&
                relyOnConnectionSharingForAuthentication
        }
    }

    /// Normalizes and stores a pump pairing code so that future requests can fetch it.
    ///
    /// - Parameter rawCode: The user entered pairing code which may include separators or lowercase letters.
    /// - Returns: The sanitized pairing code that will be used for authentication.
    /// - Throws: ``PumpPairingCodeValidationError`` when the supplied code is empty or has an unexpected length.
    @discardableResult public static func sanitizeAndStorePairingCode(_ rawCode: String) throws -> String {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PumpPairingCodeValidationError.empty }

        let shortCode = PairingCodeType.short6Char.filterCharacters(trimmed)
        if shortCode.count == 6 {
            withLock {
                pumpPairingCode = { shortCode }
                pairingCodeType = .short6Char
            }
            return shortCode
        }

        let longCode = PairingCodeType.long16Char.filterCharacters(trimmed).uppercased()
        if longCode.count == 16 {
            withLock {
                pumpPairingCode = { longCode }
                pairingCodeType = .long16Char
            }
            return longCode
        }

        throw PumpPairingCodeValidationError.invalidLength
    }

    public static func storePairingArtifacts(derivedSecret: Data?, serverNonce: Data?) {
        withLock {
            if let derivedSecret = derivedSecret, !derivedSecret.isEmpty {
                let derivedHex = derivedSecret.hexadecimalString
                jpakeDerivedSecretHex = { derivedHex }
            } else {
                jpakeDerivedSecretHex = nil
            }

            if let serverNonce = serverNonce, !serverNonce.isEmpty {
                let serverNonceHex = serverNonce.hexadecimalString
                jpakeServerNonceHex = { serverNonceHex }
            } else {
                jpakeServerNonceHex = nil
            }
        }
    }

    public static func getDerivedSecret() -> Data? {
        withLock {
            guard let derivedHex = jpakeDerivedSecretHex?(), !derivedHex.isEmpty else {
                return nil
            }
            return Data(hexadecimalString: derivedHex)
        }
    }
}
