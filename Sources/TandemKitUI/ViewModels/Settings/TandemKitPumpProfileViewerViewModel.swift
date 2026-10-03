import Combine
import Foundation

final class TandemKitPumpProfileViewerViewModel: ObservableObject {
    struct ExchangeRow: Identifiable {
        let id: String
        let title: String
        let exchange: PumpProfileReadout.Exchange
    }

    struct ProfileSection: Identifiable {
        let idpId: Int
        let title: String
        let rows: [ExchangeRow]
        var id: Int { idpId }
    }

    @Published private(set) var isReading = false
    @Published private(set) var readout: PumpProfileReadout?
    private var readAt: Date?

    private let pumpManager: TandemPumpManager?

    init(pumpManager: TandemPumpManager?) {
        self.pumpManager = pumpManager
    }

    var statusRow: ExchangeRow? {
        readout?.status.map {
            ExchangeRow(
                id: "status",
                title: String(localized: "Profile Status", comment: "Pump profile viewer section for the profile status response"),
                exchange: $0
            )
        }
    }

    var profileSections: [ProfileSection] {
        guard let readout else { return [] }
        return readout.profiles.map { profile in
            let settings = ExchangeRow(
                id: "\(profile.idpId)-settings",
                title: String(localized: "Settings", comment: "Pump profile viewer row for a profile's settings response"),
                exchange: profile.settings
            )
            let segments = profile.segments.enumerated().map { index, segment in
                ExchangeRow(
                    id: "\(profile.idpId)-segment-\(index)",
                    title: Self.markedActive(
                        String(localized: "Segment \(index)", comment: "Pump profile viewer row for one profile segment response"),
                        if: readout.isActive(segment: index, of: profile)
                    ),
                    exchange: segment
                )
            }
            return ProfileSection(
                idpId: profile.idpId,
                title: Self.markedActive(Self.title(of: profile), if: readout.isActive(profile)),
                rows: [settings] + segments
            )
        }
    }

    private static func title(of profile: PumpProfileReadout.Profile) -> String {
        guard let name = (profile.settings.response as? IDPSettingsResponse)?.name else {
            return String(localized: "IDP \(profile.idpId)", comment: "Pump profile viewer header for a profile whose name was not read")
        }
        return String(localized: "IDP \(profile.idpId): \(name)", comment: "Pump profile viewer header: profile id and name")
    }

    private static func markedActive(_ title: String, if active: Bool) -> String {
        guard active else { return title }
        return String(localized: "\(title) (active)", comment: "Pump profile viewer: marks the active profile or segment")
    }

    func readIfNeeded() {
        if readout == nil {
            read()
        }
    }

    func read() {
        guard !isReading else { return }
        guard let pumpManager else {
            readout = PumpProfileReadout(
                failure: String(localized: "Pump not available", comment: "Pump profile viewer error when there is no pump")
            )
            return
        }

        isReading = true
        pumpManager.readPumpProfiles { [weak self] readout in
            DispatchQueue.main.async {
                guard let self else { return }
                self.readout = readout
                self.readAt = Date()
                self.isReading = false
            }
        }
    }

    func exportFileURL() -> URL? {
        guard let readout, let data = readout.jsonData(exportedAt: readAt ?? Date()) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pump-profiles-\(formatter.string(from: readAt ?? Date())).json")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
