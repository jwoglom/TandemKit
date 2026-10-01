import Foundation
import Harmonize
import SwiftSyntax

/// Finds string literals a person reads that skipped localization. Syntax only: a literal passed to a custom component
/// counts as text, since TandemKitUI's components take `String` and expect callers to pass `String(localized:)`.
enum TextLiterals {
    static func unlocalizedText(in file: SwiftSourceCode) -> [Occurrence<StringLiteralExprSyntax>] {
        file.occurrences(of: StringLiteralExprSyntax.self, name: displayName).filter { isUnlocalizedText($0.node) }
    }

    /// Unlocalized text inside the `LocalizedError` requirements, which host apps show as the error's message.
    static func unlocalizedErrorText(in file: SwiftSourceCode) -> [Occurrence<StringLiteralExprSyntax>] {
        unlocalizedText(in: file).filter { literal in
            literal.node.ancestors.contains { ancestor in
                ancestor.as(VariableDeclSyntax.self)?.bindings.contains {
                    errorRequirements.contains($0.pattern.trimmedDescription)
                } == true
            }
        }
    }

    static func isUnlocalizedText(_ literal: StringLiteralExprSyntax) -> Bool {
        let raw = literal.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
        let text = raw
            .replacingOccurrences(of: formatSpecifier, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\[nrt0\\"']"#, with: "", options: .regularExpression)
        guard text.range(of: "[A-Za-z]", options: .regularExpression) != nil, !productNames.contains(text) else { return false }
        // Letters around an interpolation or a %d are words or units ("\(minutes)m", "%dh"), not a key.
        let templated = literal.segments.contains { $0.is(ExpressionSegmentSyntax.self) }
            || raw.range(of: formatSpecifier, options: .regularExpression) != nil
        return !looksLikeIdentifier(text, templated: templated) && !isInNonTextPosition(literal)
    }

    private static let formatSpecifier = #"%[-+ 0#]*\d*(\.\d+)?(ll|l|h)?[dDiuUxXoOfFeEgGcCsSpaA@]"#

    private static let errorRequirements: Set<String> = ["errorDescription", "failureReason", "recoverySuggestion", "helpAnchor"]

    // Proper nouns stay in English in every locale.
    private static let productNames: Set<String> = [
        "Loop", "Trio", "Tandem Mobi", "t:slim X2", "Control-IQ", "CIQ", "Basal-IQ", "Dexcom G6", "Dexcom G7", "Libre 2"
    ]

    /// SwiftUI initializers and modifiers whose first unlabeled `String` literal is a `LocalizedStringKey`.
    private static let localizedStringKeyAPIs: Set<String> = [
        "Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField", "DatePicker", "Section",
        "NavigationLink", "Stepper", "ProgressView", "Link", "Menu", "LabeledContent", "GroupBox", "DisclosureGroup",
        "navigationTitle", "navigationBarTitle", "alert", "confirmationDialog", "help",
        "accessibilityLabel", "accessibilityHint", "accessibilityValue", "LocalizedStringKey", "LocalizedStringResource"
    ]

    private static let localizingFunctions: Set<String> = ["NSLocalizedString", "LocalizedString"]

    /// Calls whose string arguments are names, paths, keys or log lines rather than text a user reads.
    private static let nonTextCalls: Set<String> = [
        "Image", "UIImage", "Color", "UIColor", "print", "debugPrint", "fatalError", "assertionFailure",
        "preconditionFailure", "precondition", "assert", "DispatchQueue", "TandemLogger", "Logger", "OSLog", "os_log",
        "Locale", "TimeZone", "URL", "Bundle", "NSPredicate", "NSRegularExpression", "Name", "accessibilityIdentifier",
        "tag", "hasPrefix", "hasSuffix", "contains", "starts", "range", "components", "replacingOccurrences",
        "appendingPathComponent", "appendingPathExtension", "object", "string", "bool", "integer", "set", "removeObject"
    ]

    private static let nonTextLabels: Set<String> = [
        "comment", "tableName", "bundle", "systemName", "systemImage", "imageName", "named", "forKey", "forResource",
        "category", "subsystem", "identifier", "id", "forInfoDictionaryKey"
    ]

    private static let logReceivers = ["log", "logger"]

    private static func isInNonTextPosition(_ literal: StringLiteralExprSyntax) -> Bool {
        guard let parent = literal.parent else { return false }

        if let element = parent.as(DictionaryElementSyntax.self) {
            return element.key.id == literal.id
        }
        if let clause = parent.as(InitializerClauseSyntax.self) {
            return clause.parent?.is(EnumCaseElementSyntax.self) == true
        }
        guard let argument = parent.as(LabeledExprSyntax.self) else { return false }

        let label = argument.label?.text
        if let label, nonTextLabels.contains(label) { return true }

        guard let owner = argument.parent?.parent else { return false }
        if owner.is(SubscriptCallExprSyntax.self) || owner.is(AttributeSyntax.self) || owner.is(MacroExpansionExprSyntax.self) {
            return true
        }
        guard let call = owner.as(FunctionCallExprSyntax.self), let callee = call.calleeName else { return false }

        if callee == "String" { return label == "localized" }
        if localizingFunctions.contains(callee) { return true }
        if label == nil, localizedStringKeyAPIs.contains(callee) { return true }
        if nonTextCalls.contains(callee) { return true }
        if let receiver = call.calledExpression.as(MemberAccessExprSyntax.self)?.base?.trimmedDescription.lowercased() {
            return logReceivers.contains { receiver.hasSuffix($0) }
        }
        return false
    }

    /// Keys, symbol names, file names and enum-like tokens: no whitespace, and either punctuation that prose lacks or,
    /// when not templated, a lowercase or SCREAMING_SNAKE spelling.
    private static func looksLikeIdentifier(_ text: String, templated: Bool) -> Bool {
        guard text.range(of: #"^[A-Za-z0-9_.\-:/#]+$"#, options: .regularExpression) != nil else { return false }
        if text.range(of: #"[_.\-:/#]"#, options: .regularExpression) != nil { return true }
        guard !templated, let first = text.first else { return false }
        return first.isLowercase || (text.contains("_") && text.uppercased() == text)
    }

    private static func displayName(_ literal: StringLiteralExprSyntax) -> String {
        literal.segments.trimmedDescription
    }
}
