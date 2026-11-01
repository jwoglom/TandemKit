import Foundation

/// Drives the Tandem Source relay from the pump manager: builds the device metadata from what the
/// driver already read off the pump, and pokes the throttled uploader after a history sync.
extension TandemPumpManager {
    /// Fire an upload if one is due. Safe to call often (e.g. on every history insert) — the
    /// controller throttles and de-duplicates. `force` bypasses the interval for the settings
    /// "Upload now" button.
    public func uploadToTandemSourceIfDue(force: Bool = false) {
        guard state.tandemSourceUploadEnabled, let inputs = tandemSourceInputs() else { return }
        tandemSource.trigger(now: now, force: force, inputs: inputs) { [weak self] result in
            self?.handleTandemSourceResult(result)
        }
        if force {
            refreshTandemSourceSettingsIfDue(force: true)
        }
    }

    func tandemSourceInputs() -> TandemSourceController.Inputs? {
        guard let serial = historyLogStoreSerial else { return nil }
        return TandemSourceController.Inputs(
            serial: serial.rawValue,
            deviceInfo: tandemSourceDeviceInfo(),
            deviceAssignmentId: state.tandemSourceDeviceAssignmentId,
            store: historyLogStore,
            // The backfill coordinator fills the store from the pump on its own schedule; a range it
            // hasn't reached when the upload runs is skipped (the uploader logs how many).
            fillGaps: { _, _ in },
            pumpClock: { [weak self] in self?.state.currentPumpTime ?? Date() }
        )
    }

    public var tandemSourceIsAuthenticated: Bool { tandemSource.isAuthenticated }

    /// Exchanges an authorization code (from the UI's PKCE login) for tokens and turns the relay on.
    public func completeTandemSourceSignIn(code: String, codeVerifier: String, redirectURI: String) async throws {
        try await tandemSource.auth.exchangeAuthorizationCode(code, codeVerifier: codeVerifier, redirectURI: redirectURI)
        logger.info("Signed in to Tandem Source; upload enabled")
        state.tandemSourceUploadEnabled = true
        state.lastTandemSourceError = nil
        notifyDelegateStateUpdated()
        uploadToTandemSourceIfDue(force: true)
    }

    public func signOutTandemSource() {
        tandemSource.auth.signOut()
        logger.info("Signed out of Tandem Source; upload disabled")
        state.tandemSourceUploadEnabled = false
        // Another account signed in next has none of this pump's settings.
        state.lastTandemSourceSettingsHash = nil
        notifyDelegateStateUpdated()
    }

    public func setTandemSourceUploadEnabled(_ enabled: Bool) {
        logger.info("Tandem Source upload \(enabled ? "enabled" : "disabled")")
        state.tandemSourceUploadEnabled = enabled
        notifyDelegateStateUpdated()
        if enabled { uploadToTandemSourceIfDue(force: true) }
    }

    private func handleTandemSourceResult(_ result: Result<TandemSourceUploader.Result, Error>) {
        switch result {
        case let .success(uploaded):
            logger.info("Tandem Source: uploaded \(uploaded.uploadedCount) events, server at \(uploaded.serverMaxEventIndex)")
            state.lastTandemSourceUpload = now
            state.lastTandemSourceEventIndex = uploaded.serverMaxEventIndex
            // Persist an id resolved automatically from the account so later uploads skip the lookup
            // and the settings screen can show it.
            if state.tandemSourceDeviceAssignmentId != uploaded.deviceAssignmentId {
                state.tandemSourceDeviceAssignmentId = uploaded.deviceAssignmentId
            }
            state.lastTandemSourceError = nil
        case let .failure(error):
            logger.error("Tandem Source upload failed: \(error)")
            state.lastTandemSourceError = String(describing: error)
        }
        notifyDelegateStateUpdated()
    }

    /// The upload's device block, assembled from the pump reads the driver already caches. The "A"
    /// version read supplies `armSwVer`/`partNum`/`pcbaRev`/`pumpRev`; the rest come from
    /// `PumpState`. Nil until a serial is known (no serial, no upload).
    func tandemSourceDeviceInfo() -> TandemSourceDeviceInfo? {
        let pump = state.pumpState
        guard let serial = pump.pumpSerial else { return nil }

        let versionA = pump.pumpVersionACargo.map { PumpVersionResponse(cargo: $0) }
        let features = state.pumpMainFeaturesBitmask.map { PumpFeaturesV1Response.PumpFeatureType.fromBitmask(UInt64($0)) }
        return TandemSourceDeviceInfo(
            serialNum: serial,
            modelNum: versionA?.modelNum ?? pump.modelNumber ?? 1_004_000,
            partNum: versionA?.partNum ?? 0,
            armSwVer: versionA?.armSwVer ?? 0,
            mspSwVer: versionA?.mspSwVer ?? 0,
            pcbaSN: versionA?.pcbaSN ?? pump.pcbSerialNumber ?? 0,
            configABits: versionA?.configABits ?? pump.controlBitsA ?? 0,
            configBBits: versionA?.configBBits ?? pump.controlBitsB ?? 0,
            pumpRev: versionA?.pumpRev ?? "0",
            pcbaRev: versionA?.pcbaRev ?? "0",
            pumpAPIVersion: pump.apiVersion.map { "\($0.major).\($0.minor)" } ?? "3.11",
            dexcomG6: features?.contains(.DEXCOM_G6_SUPPORTED) ?? false,
            basalIQ: features?.contains(.BASAL_IQ_SUPPORTED) ?? false,
            // Until the features read lands, a pump that has answered a Control-IQ read supports it.
            controlIQ: features?.contains(.CONTROL_IQ_SUPPORTED) ?? (state.controlIQEnabled != nil)
        )
    }
}
