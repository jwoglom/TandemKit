import Foundation

/// History log type used when a specific implementation is unavailable.
public class UnknownHistoryLog: HistoryLog {
    public required init(cargo: Data) {
        super.init(cargo: cargo)
    }
}
