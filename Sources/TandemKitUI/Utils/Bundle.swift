import Foundation

extension Bundle {
    /// The xctest runner, under which the screens are also built, has no display name.
    var bundleDisplayName: String {
        let name = object(forInfoDictionaryKey: "CFBundleDisplayName") ?? object(forInfoDictionaryKey: "CFBundleName")
        return name as? String ?? ""
    }
}
