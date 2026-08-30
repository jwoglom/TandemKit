// Linux-only Combine stand-in. See LinuxShims/README.md.
@_exported import Foundation

#if os(Linux)

/// Cancels on deinit, as Combine's does.
public final class AnyCancellable: Hashable {
    private var cancelBlock: (() -> Void)?
    private let lock = NSLock()

    public init(_ cancel: @escaping () -> Void) {
        cancelBlock = cancel
    }

    public func cancel() {
        lock.lock()
        let block = cancelBlock
        cancelBlock = nil
        lock.unlock()
        block?()
    }

    deinit { cancel() }

    public func store(in set: inout Set<AnyCancellable>) {
        set.insert(self)
    }

    public func store(in collection: inout [AnyCancellable]) {
        collection.append(self)
    }

    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

public final class PassthroughSubject<Output, Failure: Error> {
    private var subscribers: [(id: UUID, handler: (Output) -> Void)] = []
    private let lock = NSLock()

    public init() {}

    public func send(_ value: Output) {
        lock.lock()
        let handlers = subscribers.map(\.handler)
        lock.unlock()
        // Outside the lock: a handler may cancel its own subscription.
        for handler in handlers {
            handler(value)
        }
    }

    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        let id = UUID()
        lock.lock()
        subscribers.append((id: id, handler: receiveValue))
        lock.unlock()

        return AnyCancellable { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.subscribers.removeAll { $0.id == id }
            self.lock.unlock()
        }
    }
}

#endif
