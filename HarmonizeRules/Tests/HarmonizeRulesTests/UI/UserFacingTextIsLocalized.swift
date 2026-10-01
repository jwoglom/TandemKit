import Harmonize
import XCTest

final class UserFacingTextIsLocalized: XCTestCase {
    func testTextInTandemKitUIIsLocalized() {
        let literals = TandemHarmonize.uiPackage.sources().flatMap(TextLiterals.unlocalizedText(in:))

        literals.assertEmpty(rule: Self.rule, baseline: Self.uiBaseline)
    }

    func testDriverErrorDescriptionsAreLocalized() {
        let literals = (TandemHarmonize.driverPackage.sources() + TandemHarmonize.corePackage.sources())
            .flatMap(TextLiterals.unlocalizedErrorText(in:))

        literals.assertEmpty(rule: Self.rule)
    }

    // Developer screens, left in English.
    private static let uiBaseline: [String] = [
        "TandemKitDebugView.swift",
        "TandemKitDebugViewModel.swift",
        "TandemKitHistoryLogViewerView.swift",
        "TandemKitHistoryLogViewerViewModel.swift",
        // TandemOnboardingView, an unused Xcode template; deleting it means editing the project file.
        "Hello, World!"
    ]

    private static let rule = Rule(
        description: "Text a user reads goes through String(localized:comment:) or Text(_:comment:), never a bare literal.",
        rationale: """
            Loop and Trio ship in many languages, and a person reading a pump error, a cartridge step or a temp basal
            prompt may not read English. A bare literal cannot be translated, and neither can a String handed to a
            custom view, a view model property or an error's errorDescription: hosts show those as they are.
            SwiftUI's Text("..."), Button("..."), Toggle("...") and .navigationTitle("...") do translate a literal,
            but from the host app's bundle, which has none of TandemKit's strings.
            """,
        fixHint: """
            Give Text a comment, Text("...", comment: "..."), which TandemCore routes to TandemKit's bundle. Anywhere
            else, pass String(localized: "...", comment: "...") with a comment saying where the text appears. Format
            numbers, units and durations with a formatter or a localized format string instead of concatenating them.
            """,
        badExample: "pairingError = \"Please enter a pairing code\"",
        goodExample: "pairingError = String(localized: \"Please enter a pairing code\", comment: \"Error when the pairing code field is empty\")"
    )
}
