import Foundation

/// Unit the pump uses for the body weight stored in its Control-IQ settings.
///
/// The pump reports this alongside the weight in `ControlIQInfoV1Response` /
/// `ControlIQInfoV2Response`, and expects it echoed back in
/// `ChangeControlIQSettingsRequest`. The weight value itself is unit-less on the
/// wire, so reading a weight without its unit — or writing one with a different
/// unit than it was read in — silently changes the user's stored body weight.
public enum ControlIQWeightUnit: Int, CaseIterable, Sendable {
    case kilograms = 0
    case pounds = 1
}

public extension ControlIQWeightUnit {
    /// Exact conversion factor, matching the definition of the international pound.
    static let poundsPerKilogram = 2.20462262185

    /// Converts a whole-unit weight into `unit`, rounding to the nearest whole
    /// unit because the pump stores weight as an integer.
    func convert(_ weight: Int, to unit: ControlIQWeightUnit) -> Int {
        guard self != unit else { return weight }

        switch (self, unit) {
        case (.kilograms, .pounds):
            return Int((Double(weight) * Self.poundsPerKilogram).rounded())
        case (.pounds, .kilograms):
            return Int((Double(weight) / Self.poundsPerKilogram).rounded())
        default:
            return weight
        }
    }
}
