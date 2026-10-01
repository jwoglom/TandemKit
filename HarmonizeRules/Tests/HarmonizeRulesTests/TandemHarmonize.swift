import Harmonize
import HarmonizeSemantics
import SwiftParser
import SwiftSyntax

enum TandemHarmonize {
    static let productionCode = Harmonize.productionCode()
    static let testCode = Harmonize.testCode()

    static let corePackage = productionCode.on("Sources/TandemCore")
    static let messagesPackage = productionCode.on("Sources/TandemCore/Messages")
    static let driverPackage = productionCode.on("Sources/TandemKit")
    static let uiPackage = productionCode.on("Sources/TandemKitUI")
    static let viewModelsFolder = productionCode.on("Sources/TandemKitUI/ViewModels")
    // The integration tests poll a separate faketandem process, so real time is part of what they test.
    static let unitTestCode = testCode.excluding("TandemKitIntegrationTests")

    static var viewModels: [Class] { viewModelsFolder.classes().withSuffix("ViewModel") }
    static var testClassNames: Set<String> { Set(testCode.classes().map(\.name)) }
}

/// A syntax node inside a file, reported by Harmonize's assertions at its own line rather than the file's.
struct Occurrence<Node: SyntaxProtocol>: SyntaxNodeProviding, SourceCodeProviding, NamedDeclaration, CustomStringConvertible {
    let node: Node
    let name: String
    let sourceCodeLocation: SourceCodeLocation

    var description: String { name }
}

extension SwiftSourceCode {
    /// Identifier tokens in the file's code, so a name that appears only in a comment does not count as a use.
    var identifiers: [String] {
        Parser.parse(source: source).tokens(viewMode: .sourceAccurate).compactMap { token in
            if case let .identifier(name) = token.tokenKind { return name }
            return nil
        }
    }

    /// Every `Node` in the file, skipping preview code, which never reaches a user.
    func occurrences<Node: SyntaxProtocol>(
        of type: Node.Type,
        name: (Node) -> String = { $0.trimmedDescription }
    ) -> [Occurrence<Node>] {
        let tree = Parser.parse(source: source)
        let location = SourceCodeLocation(sourceFilePath: filePath, sourceFileTree: tree)
        let collector = NodeCollector<Node>()
        collector.walk(tree)
        return collector.nodes.map { Occurrence(node: $0, name: name($0), sourceCodeLocation: location) }
    }
}

private final class NodeCollector<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    var nodes: [Node] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if node.isPreviewCode { return .skipChildren }
        if let match = node.as(Node.self) { nodes.append(match) }
        return .visitChildren
    }
}

extension SyntaxProtocol {
    var isPreviewCode: Bool {
        if let macro = self.as(MacroExpansionExprSyntax.self) { return macro.macroName.text == "Preview" }
        if let macro = self.as(MacroExpansionDeclSyntax.self) { return macro.macroName.text == "Preview" }
        if let type = self.as(StructDeclSyntax.self) {
            return type.name.text.hasPrefix("Preview")
                || type.inheritanceClause?.inheritedTypes.contains { $0.type.trimmedDescription == "PreviewProvider" } == true
        }
        if let type = self.as(ClassDeclSyntax.self) { return type.name.text.hasPrefix("Preview") }
        if let function = self.as(FunctionDeclSyntax.self) { return function.name.text.lowercased().hasPrefix("preview") }
        if let variable = self.as(VariableDeclSyntax.self) {
            return variable.bindings.contains {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text.lowercased().hasPrefix("preview") == true
            }
        }
        return false
    }

    /// The last component of the called function's name, e.g. `error` for `self.log.error(...)`.
    var calleeName: String? {
        guard let call = self.as(FunctionCallExprSyntax.self) else { return nil }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) { return reference.baseName.text }
        return call.calledExpression.trimmedDescription
    }
}
