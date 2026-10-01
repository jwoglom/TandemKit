import Harmonize
import HarmonizeSemantics
import XCTest

final class StateTypesAreEquatable: XCTestCase {
    func testStateStructsAreEquatable() {
        let structs = Self.scope.flatMap { $0.structs(includeNested: true) }.withSuffix("State").filter(Self.isVisible)

        structs.assertTrue(rule: Self.rule, strict: true) {
            Self.declaresEquality($0.inheritanceTypesNames)
        }
    }

    func testStateEnumsWithAssociatedValuesAreEquatable() {
        // An enum whose cases carry no values is Equatable without saying so.
        let enums = Self.scope.flatMap { $0.enums(includeNested: true) }.withSuffix("State").filter(Self.isVisible)
            .filter { $0.cases.contains { !$0.parameters.isEmpty } }

        enums.assertTrue(rule: Self.rule) { Self.declaresEquality($0.inheritanceTypesNames) }
    }

    private static var scope: [HarmonizeScope] { [TandemHarmonize.driverPackage, TandemHarmonize.uiPackage] }

    private static func isVisible(_ declaration: some ModifiersProviding) -> Bool {
        !declaration.modifiers.contains(.private) && !declaration.modifiers.contains(.fileprivate)
    }

    private static func declaresEquality(_ conformances: [String]) -> Bool {
        conformances.contains("Equatable") || conformances.contains("Hashable")
    }

    private static let rule = Rule(
        description: "State types in the driver and the UI are Equatable.",
        rationale: """
            State is what tests assert on. Without Equatable, a test compares one field at a time and misses the one
            it forgot, and code that wants to skip a no-op update has nothing to compare.
            """,
        fixHint: "Add Equatable (or Hashable) to the type; synthesis covers it once every stored property is Equatable.",
        badExample: "public struct TandemPumpManagerState: RawRepresentable { ... }",
        goodExample: "public struct TandemPumpManagerState: RawRepresentable, Equatable { ... }"
    )
}
