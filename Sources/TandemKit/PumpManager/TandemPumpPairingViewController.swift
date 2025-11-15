#if canImport(UIKit)
    import TandemCore
    import UIKit

    final class TandemPumpPairingViewController: UIViewController {
        private enum Layout {
            static let spacing: CGFloat = 16
            static let textFieldHeight: CGFloat = 44
        }

        private let pumpManager: TandemPumpManager
        private let completion: (Result<Void, Error>) -> Void

        private var isPairing = false {
            didSet { updateInteractionState() }
        }

        private lazy var instructionsLabel: UILabel = {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .center
            label.text = LocalizedString(
                "Enter the pairing code from your pump to begin pairing.",
                comment: "Instructions for Tandem pairing UI"
            )
            return label
        }()

        private lazy var pairingCodeField: UITextField = {
            let field = UITextField()
            field.translatesAutoresizingMaskIntoConstraints = false
            field.borderStyle = .roundedRect
            field.placeholder = LocalizedString("Pump pairing code", comment: "Placeholder text for Tandem pairing code field")
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.returnKeyType = .done
            field.clearButtonMode = .whileEditing
            field.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
            field.delegate = self
            return field
        }()

        private lazy var pairButton: UIButton = {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(LocalizedString("Pair Pump", comment: "Button title for Tandem pump pairing"), for: .normal)
            button.addTarget(self, action: #selector(pairButtonTapped), for: .touchUpInside)
            button.isEnabled = false
            return button
        }()

        private lazy var statusLabel: UILabel = {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            label.isHidden = true
            return label
        }()

        private lazy var activityIndicator: UIActivityIndicatorView = {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.hidesWhenStopped = true
            return indicator
        }()

        init(pumpManager: TandemPumpManager, completion: @escaping (Result<Void, Error>) -> Void) {
            self.pumpManager = pumpManager
            self.completion = completion
            super.init(nibName: nil, bundle: nil)
            title = LocalizedString("Pair Tandem Pump", comment: "Title for Tandem pump pairing flow")
        }

        @available(*, unavailable)  required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            configureLayout()
            updateInteractionState()
        }

        private func configureLayout() {
            let stackView =
                UIStackView(arrangedSubviews: [instructionsLabel, pairingCodeField, pairButton, activityIndicator, statusLabel])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .vertical
            stackView.spacing = Layout.spacing

            view.addSubview(stackView)

            NSLayoutConstraint.activate([
                pairingCodeField.heightAnchor.constraint(equalToConstant: Layout.textFieldHeight),

                stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        private func updateInteractionState() {
            let hasCode = !(pairingCodeField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            pairButton.isEnabled = hasCode && !isPairing
            pairingCodeField.isEnabled = !isPairing
            if isPairing {
                activityIndicator.startAnimating()
            } else {
                activityIndicator.stopAnimating()
            }
        }

        @objc  private func textDidChange() {
            statusLabel.isHidden = true
            updateInteractionState()
        }

        @objc  private func pairButtonTapped() {
            guard !isPairing else { return }
            guard let code = pairingCodeField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
                showStatus(.failure(PumpPairingCodeValidationError.empty))
                return
            }

            isPairing = true
            pumpManager.pairPump(with: code) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isPairing = false
                    self?.showStatus(result)
                    self?.completion(result)
                }
            }
        }

        private func showStatus(_ result: Result<Void, Error>) {
            switch result {
            case .success:
                statusLabel.textColor = .systemGreen
                statusLabel.text = LocalizedString(
                    "Pairing request sent. Follow the prompts on your pump.",
                    comment: "Success message for Tandem pump pairing"
                )
            case let .failure(error):
                statusLabel.textColor = .systemRed
                statusLabel.text = [error.localizedDescription, error.recoverySuggestion].compactMap { $0 }
                    .joined(separator: "\n")
            }
            statusLabel.isHidden = false
        }
    }

    extension TandemPumpPairingViewController: UITextFieldDelegate {
        func textFieldShouldReturn(_: UITextField) -> Bool {
            pairButtonTapped()
            return false
        }
    }
#endif
