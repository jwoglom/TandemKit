#if canImport(SwiftUI)
    import SwiftUI

    extension Text {
        init(_ key: LocalizedStringKey, comment: StaticString = "") {
            self.init(key, bundle: Bundle(for: TandemKitHUDProvider.self), comment: comment)
        }
    }

    extension String {
        init(localized key: String.LocalizationValue, comment: StaticString = "") {
            self.init(localized: key, bundle: Bundle(for: TandemKitHUDProvider.self), comment: comment)
        }
    }
#else
    import Foundation

    extension String {
        // Desktop/Linux SwiftPM fallback: SwiftUI and the TandemKitUI resource
        // bundle are unavailable, so return the development-language key as-is.
        // The `localized:` label is preserved so shared call sites compile
        // unchanged.
        init(localized key: String, comment _: StaticString = "") {
            self = key
        }
    }
#endif
