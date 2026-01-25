import Foundation

final class Locked<Value> {
    private var valueStorage: Value
    private let lock = NSLock()

    init(_ value: Value) {
        valueStorage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return valueStorage
        }
        set {
            lock.lock()
            valueStorage = newValue
            lock.unlock()
        }
    }
}
