import Harmonize
import SwiftParser
import SwiftSyntax
import XCTest

final class MilliunitConversionsRound: XCTestCase {
    func testIntegerConversionsOfAThousandfoldRound() {
        let truncations = TandemHarmonize.productionCode.sources().flatMap { file in
            let integerNames = Self.integerTypedNames(in: file)
            return file.occurrences(of: FunctionCallExprSyntax.self).filter { call in
                Self.integerTypes.contains(call.node.calledExpression.trimmedDescription)
                    && call.node.arguments.contains { Self.truncatesAThousandfold($0.expression, integerNames: integerNames) }
            }
        }

        truncations.assertEmpty(rule: Self.rule)
    }

    private static let integerTypes: Set<String> = ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]

    /// A product with 1000 that is neither rounded first nor made of integers alone.
    private static func truncatesAThousandfold(_ argument: ExprSyntax, integerNames: Set<String>) -> Bool {
        let text = argument.trimmedDescription
        guard text.contains("* 1000") || text.contains("*1000"), !text.contains(".rounded(") else { return false }
        let identifiers = argument.tokens(viewMode: .sourceAccurate).compactMap { token -> String? in
            if case let .identifier(name) = token.tokenKind { return name }
            return nil
        }
        return !identifiers.allSatisfy { integerNames.contains($0) }
    }

    /// Parameters and variables the file declares with an integer type, whose products are exact.
    private static func integerTypedNames(in file: SwiftSourceCode) -> Set<String> {
        let collector = IntegerDeclarationCollector()
        collector.walk(Parser.parse(source: file.source))
        return collector.names
    }

    private static let rule = Rule(
        description: "A Double scaled by 1000 is rounded before it becomes an integer.",
        rationale: """
            Insulin amounts travel as whole milliunits, and Double arithmetic lands a hair off: 1.001 * 1000 is
            1000.9999999999999, which Int(_:) truncates to 1000, a milliunit under what the host asked for. The same
            truncation under-counts a prime, a limit or a delay by one unit of the pump's resolution.
            """,
        fixHint: "Use TandemPumpCapabilities.milliunits(_:) for an insulin amount, or round before converting: Int((x * 1000).rounded()).",
        badExample: "FillCannulaRequest(primeSizeMilliUnits: Int(amount * 1000))",
        goodExample: "FillCannulaRequest(primeSizeMilliUnits: TandemPumpCapabilities.milliunits(amount))"
    )
}

private final class IntegerDeclarationCollector: SyntaxVisitor {
    var names: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        if isInteger(node.type) {
            names.insert((node.secondName ?? node.firstName).text)
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
           let type = node.typeAnnotation?.type, isInteger(type)
        {
            names.insert(name)
        }
        return .visitChildren
    }

    private func isInteger(_ type: TypeSyntax) -> Bool {
        ["Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]
            .contains(type.trimmedDescription)
    }
}
