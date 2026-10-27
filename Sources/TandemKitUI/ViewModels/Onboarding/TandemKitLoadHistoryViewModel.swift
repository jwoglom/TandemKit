import Combine
import Foundation

enum LoadHistoryPhase {
    case choosing
    case loading
}

final class TandemKitLoadHistoryViewModel: ObservableObject {
    @Published var phase = LoadHistoryPhase.choosing
    /// 0 to 1, never moving back.
    @Published var progress: Double = 0
    @Published var isShowingNotLoadedAlert = false
    @Published var isShowingLoadFailedAlert = false
    @Published var loadFailedMessage: String?

    private let pumpManager: TandemPumpManager
    private let done: () -> Void

    init(pumpManager: TandemPumpManager, done: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.done = done
    }

    var appName: String { HostApp.current.appName }

    var explanation: String {
        // "this app" opens the sentence for a host that is neither Trio nor Loop.
        let sentenceStart = appName.prefix(1).uppercased() + appName.dropFirst()
        return String(format: String(
            localized: "%1$@ can read your pump history of boluses and basal delivery from before you connected to %2$@.",
            comment: "Setup explanation of loading the pump's history (1: app name at the start of a sentence, 2: app name)"
        ), sentenceStart, appName)
    }

    var guidance: String {
        String(format: String(
            localized: "If you were previously using this Tandem Mobi device with the Tandem app, it is essential to load history so that %1$@ knows your current IOB and does not over-deliver insulin in the hours following setup. If you were previously using a different pump with %1$@, and it is already aware of any active insulin doses, you can skip this step.",
            comment: "Setup guidance on whether to load the pump's history (1: app name)"
        ), appName)
    }

    var loadButtonTitle: String {
        String(format: String(
            localized: "Load Pump History into %@",
            comment: "Setup button that loads the pump's history into the app (1: app name)"
        ), appName)
    }

    var notLoadedMessage: String {
        String(format: String(
            localized: "This Tandem Mobi pump's past bolus and basal records were not loaded, so %@ assumes you have 0 units of Insulin on Board. Please monitor your glucose accordingly.",
            comment: "Setup alert after the user chose not to load the pump's history (1: app name)"
        ), appName)
    }

    var loadingMessage: String {
        String(format: String(
            localized: "Reading the past %1$@ hours of your pump's history into %2$@. Keep the pump near your phone.",
            comment: "Setup message while the pump's history loads (1: number of hours, 2: app name)"
        ), String(Int(TandemPumpManager.setupHistoryLoadWindow / .hours(1))), appName)
    }

    func doNotLoad() {
        isShowingNotLoadedAlert = true
    }

    func notLoadedAcknowledged() {
        done()
    }

    func load() {
        phase = .loading
        pumpManager.loadHistoryForSetup(
            progress: { value in
                DispatchQueue.main.async {
                    self.progress = max(self.progress, value)
                }
            },
            completion: { error in
                DispatchQueue.main.async {
                    guard let error else {
                        self.progress = 1
                        self.done()
                        return
                    }
                    self.loadFailedMessage = error.localizedDescription
                    self.isShowingLoadFailedAlert = true
                }
            }
        )
    }
}
