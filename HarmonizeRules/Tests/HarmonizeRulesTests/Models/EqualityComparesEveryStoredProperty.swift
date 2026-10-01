import Foundation
import Harmonize
import HarmonizeSemantics
import SwiftSyntax
import XCTest

final class EqualityComparesEveryStoredProperty: XCTestCase {
    func testHandWrittenEqualityComparesEveryStoredProperty() {
        // Parsing every file would take twenty seconds, so files are picked by text: an == says `func ==`, and the
        // declaration of a type that has one says the type's name.
        let files = TandemHarmonize.productionCode.sources()
        let equalityFiles = files.filter { $0.source.range(of: #"func\s*=="#, options: .regularExpression) != nil }
        var typesWithEquality: Set<String> = []
        var compared: Set<String> = []
        for body in equalityFiles.flatMap(Self.bodies) {
            for function in Self.members(body.node.members, of: FunctionDeclSyntax.self) where Self.isEquality(function) {
                typesWithEquality.insert(body.name)
                compared.formUnion(Self.names(in: function).map { "\(body.name).\($0)" })
            }
        }
        let typeNames = Set(typesWithEquality.compactMap { $0.split(separator: ".").last.map(String.init) })
        let properties = files.filter { file in typeNames.contains { file.source.contains($0) } }
            .flatMap(Self.bodies)
            .filter { typesWithEquality.contains($0.name) }
            .flatMap(Self.storedProperties)

        properties.filter { !Self.notState.contains($0.name) }.assertTrue(rule: Self.rule, strict: true) {
            compared.contains($0.name)
        }

        let stale = Self.notState.subtracting(properties.map(\.name))
        XCTAssertTrue(stale.isEmpty, "notState names no stored property of a type with a hand-written ==: \(stale.sorted())")
    }

    /// Stored properties that are not part of the value, so their type's `==` leaves them out.
    private static let notState: Set<String> = [
        // A TandemLogger, the same in every instance.
        "UnfinalizedDose.logger"
    ]

    /// Every type and extension body in the file, named by its qualified type name.
    private static func bodies(in file: SwiftSourceCode) -> [Occurrence<MemberBlockSyntax>] {
        file.occurrences(of: MemberBlockSyntax.self) { qualifiedName(Syntax($0)) }
    }

    private static func isEquality(_ function: FunctionDeclSyntax) -> Bool {
        function.name.text == "==" && isStatic(function.modifiers)
    }

    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
    }

    /// Identifier and keyword tokens, so a name in a comment or a string literal does not count as compared.
    private static func names(in function: FunctionDeclSyntax) -> [String] {
        guard let body = function.body else { return [] }
        return body.tokens(viewMode: .sourceAccurate).compactMap { token in
            switch token.tokenKind {
            case .identifier, .keyword: return token.text.filter { $0 != "`" }
            default: return nil
            }
        }
    }

    /// One occurrence per stored instance property of a struct or class body, named `Type.property`.
    private static func storedProperties(of body: Occurrence<MemberBlockSyntax>) -> [Occurrence<PatternBindingSyntax>] {
        guard body.node.parent?.is(StructDeclSyntax.self) == true || body.node.parent?.is(ClassDeclSyntax.self) == true
        else { return [] }

        return members(body.node.members, of: VariableDeclSyntax.self)
            .filter { !isStatic($0.modifiers) }
            .flatMap(\.bindings)
            .filter(isStored)
            .flatMap { binding in
                binding.pattern.tokens(viewMode: .sourceAccurate).filter(isIdentifier).map {
                    Occurrence(node: binding, name: "\(body.name).\($0.text)", sourceCodeLocation: body.sourceCodeLocation)
                }
            }
    }

    private static func isIdentifier(_ token: TokenSyntax) -> Bool {
        if case .identifier = token.tokenKind { return true }
        return false
    }

    /// No accessors, or only `willSet`/`didSet`. `lazy` has no accessors either.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        switch binding.accessorBlock?.accessors {
        case nil:
            return true
        case .getter:
            return false
        case let .accessors(accessors):
            return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
    }

    /// The body's own declarations, including those under `#if`; a nested type's members are in its own body.
    private static func members<Decl: DeclSyntaxProtocol>(_ list: MemberBlockItemListSyntax, of type: Decl.Type) -> [Decl] {
        list.flatMap { member -> [Decl] in
            if let decl = member.decl.as(Decl.self) { return [decl] }
            guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else { return [] }
            return conditional.clauses.flatMap { clause -> [Decl] in
                guard case let .decls(nested)? = clause.elements else { return [] }
                return members(nested, of: type)
            }
        }
    }

    /// `Outer.Inner` for a nested type, where `enclosingTypeName` would give two nested types that share a name the
    /// same one.
    private static func qualifiedName(_ node: Syntax) -> String {
        ([node] + Array(node.ancestors)).reversed().compactMap { ancestor -> String? in
            if let type = ancestor.as(StructDeclSyntax.self) { return type.name.text }
            if let type = ancestor.as(ClassDeclSyntax.self) { return type.name.text }
            if let type = ancestor.as(EnumDeclSyntax.self) { return type.name.text }
            if let type = ancestor.as(ActorDeclSyntax.self) { return type.name.text }
            if let type = ancestor.as(ExtensionDeclSyntax.self) { return type.extendedType.trimmedDescription }
            return nil
        }.joined(separator: ".")
    }

    private static let rule = Rule(
        description: "A hand-written == compares every stored property of its type.",
        rationale: """
            Swift synthesizes == only while every stored property is Equatable; once it is written by hand, a property
            added later is left out without a word. Two values that differ only there then compare equal, so a test
            asserting on state passes when it should fail, and code that skips a no-op update skips a real one.
            """,
        fixHint: """
            Compare the property in the type's ==, and add a mutation for it to the type's equality tests if it has
            them. If the property is not part of the value (a logger, a cache), add Type.property to this rule's
            notState with the reason.
            """,
        badExample: "struct S: Equatable {\n    var a: Int\n    var b: Int\n    static func == (lhs: S, rhs: S) -> Bool { lhs.a == rhs.a }\n}",
        goodExample: "struct S: Equatable {\n    var a: Int\n    var b: Int\n    static func == (lhs: S, rhs: S) -> Bool { lhs.a == rhs.a && lhs.b == rhs.b }\n}"
    )
}
