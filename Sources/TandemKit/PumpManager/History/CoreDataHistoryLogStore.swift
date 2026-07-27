import CoreData
import Foundation

/// SQLite-backed `HistoryLogStore`.
///
/// Follows the shape of LoopKit's `PersistentDeviceLog`: a small Core Data stack private to this
/// framework, an explicit store file, a single private-queue context, and age-based pruning. Two
/// deliberate differences:
///
/// * The managed object model is built in code rather than loaded from a `.xcdatamodeld`. The
///   framework is built both by SwiftPM and by `TandemKit.xcodeproj`, and a model resource has to
///   be registered differently in each; a programmatic model has no resource to register.
/// * Rows are plain `NSManagedObject`s accessed by key rather than generated subclasses. Core Data
///   resolves `managedObjectClassName` by looking the class up at runtime, which is fragile when
///   the framework is loaded as a plugin bundle (as it is inside Trio).
///
/// All accessors are synchronous and run on the store's private queue via `performAndWait`; they
/// may block, so call them off the BLE command queue.
public final class CoreDataHistoryLogStore: HistoryLogStore {
    private static let entryEntityName = "HistoryLogEntry"
    private static let metadataEntityName = "HistoryLogPumpMetadata"
    /// SQLite's default limit on host parameters is 999; stay well under it when batching `IN`
    /// predicates and saves.
    private static let batchSize = 500

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let log = TandemLogger(category: "CoreDataHistoryLogStore")

    /// Opens (creating if needed) a history log database at `directoryURL/fileName`.
    public convenience init(directoryURL: URL, fileName: String = "HistoryLog.sqlite") throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw HistoryLogStoreError.storeUnavailable(error)
        }

        let description = NSPersistentStoreDescription(url: directoryURL.appendingPathComponent(fileName))
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        #if os(iOS)
            // Therapy history is health data. Readable after first unlock so a background BLE wake
            // can still write to it, but not while the device has never been unlocked.
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
        #endif

        try self.init(storeDescription: description)
    }

    /// A store with no file behind it, for tests.
    ///
    /// Backed by SQLite at `/dev/null` rather than `NSInMemoryStoreType`, which doesn't support the
    /// batch deletes `prune` and `deleteAll` rely on.
    public static func inMemory() throws -> CoreDataHistoryLogStore {
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        return try CoreDataHistoryLogStore(storeDescription: description)
    }

    private init(storeDescription: NSPersistentStoreDescription) throws {
        container = NSPersistentContainer(
            name: "TandemHistoryLog",
            managedObjectModel: CoreDataHistoryLogStore.managedObjectModel
        )
        container.persistentStoreDescriptions = [storeDescription]

        var loadError: Error?
        // shouldAddStoreAsynchronously is false, so this completes before the call returns.
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw HistoryLogStoreError.storeUnavailable(loadError)
        }

        context = container.newBackgroundContext()
        // Uniqueness constraints are the backstop against a duplicate slipping past the pre-insert
        // dedup check; on conflict keep what is already stored, matching the insert-ignore contract.
        context.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        context.automaticallyMergesChangesFromParent = true
    }

    /// The default location for the store file: `Application Support/TandemKit`, inside the host
    /// app's container. LoopKit hands plugins no storage directory, so the driver picks its own.
    public static func defaultDirectoryURL() throws -> URL {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return base.appendingPathComponent("TandemKit", isDirectory: true)
        } catch {
            throw HistoryLogStoreError.storeUnavailable(error)
        }
    }

    // MARK: - Model

    private static let managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let entry = NSEntityDescription()
        entry.name = entryEntityName
        entry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entry.properties = [
            attribute("pumpSerial", .integer64AttributeType),
            attribute("sequenceNum", .integer64AttributeType),
            attribute("typeId", .integer32AttributeType),
            attribute("pumpTimeSec", .integer64AttributeType),
            attribute("cargo", .binaryDataAttributeType),
            attribute("receivedAt", .dateAttributeType)
        ]
        // Sequence numbers are unique per pump; this is also the insert-ignore key.
        entry.uniquenessConstraints = [["pumpSerial", "sequenceNum"]]
        entry.indexes = [
            index(named: "byPumpTime", on: entry, properties: ["pumpSerial", "pumpTimeSec"]),
            index(named: "byPumpType", on: entry, properties: ["pumpSerial", "typeId", "sequenceNum"])
        ]

        let metadata = NSEntityDescription()
        metadata.name = metadataEntityName
        metadata.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        metadata.properties = [
            attribute("pumpSerial", .integer64AttributeType),
            attribute("prunedBelowSequenceNum", .integer64AttributeType)
        ]
        metadata.uniquenessConstraints = [["pumpSerial"]]

        model.entities = [entry, metadata]
        return model
    }()

    private static func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = false
        return attribute
    }

    private static func index(
        named name: String,
        on entity: NSEntityDescription,
        properties: [String]
    ) -> NSFetchIndexDescription {
        let elements = properties.compactMap { propertyName -> NSFetchIndexElementDescription? in
            guard let property = entity.properties.first(where: { $0.name == propertyName }) else {
                return nil
            }
            return NSFetchIndexElementDescription(property: property, collationType: .binary)
        }
        return NSFetchIndexDescription(name: name, elements: elements)
    }

    // MARK: - Plumbing

    private func perform<T>(_ block: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>?
        context.performAndWait {
            result = Result { try block(context) }
        }
        do {
            guard let result else {
                throw CocoaError(.coreData)
            }
            return try result.get()
        } catch let error as HistoryLogStoreError {
            throw error
        } catch {
            throw HistoryLogStoreError.persistenceFailed(error)
        }
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private func entryRequest(pumpSerial: UInt32) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entryEntityName)
        request.predicate = NSPredicate(format: "pumpSerial == %lld", Int64(pumpSerial))
        return request
    }

    private func storedLog(from object: NSManagedObject) -> StoredHistoryLog {
        StoredHistoryLog(
            pumpSerial: UInt32(clamping: Self.number(object.value(forKey: "pumpSerial"))?.int64Value ?? 0),
            sequenceNum: UInt32(clamping: Self.number(object.value(forKey: "sequenceNum"))?.int64Value ?? 0),
            typeId: Self.number(object.value(forKey: "typeId"))?.intValue ?? 0,
            pumpTimeSec: UInt32(clamping: Self.number(object.value(forKey: "pumpTimeSec"))?.int64Value ?? 0),
            cargo: object.value(forKey: "cargo") as? Data ?? Data(),
            receivedAt: object.value(forKey: "receivedAt") as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }

    private func firstLog(
        pumpSerial: UInt32,
        ascending: Bool,
        typeId: Int? = nil
    ) throws -> StoredHistoryLog? {
        try perform { context in
            let request = self.entryRequest(pumpSerial: pumpSerial)
            if let typeId {
                request.predicate = NSPredicate(
                    format: "pumpSerial == %lld AND typeId == %d",
                    Int64(pumpSerial),
                    Int32(typeId)
                )
            }
            request.sortDescriptors = [NSSortDescriptor(key: "sequenceNum", ascending: ascending)]
            request.fetchLimit = 1
            return try context.fetch(request).first.map(self.storedLog(from:))
        }
    }

    // MARK: - HistoryLogStore

    public func insert(_ logs: [StoredHistoryLog]) throws {
        guard !logs.isEmpty else {
            return
        }

        try perform { context in
            // Collapse duplicates within the batch first, keeping the first occurrence of each key.
            var byPump: [UInt32: [UInt32: StoredHistoryLog]] = [:]
            for log in logs where byPump[log.pumpSerial]?[log.sequenceNum] == nil {
                byPump[log.pumpSerial, default: [:]][log.sequenceNum] = log
            }

            var pendingInserts = 0
            for (pumpSerial, logsBySequence) in byPump {
                let existing = try self.existingSequenceNumbers(
                    pumpSerial: pumpSerial,
                    among: Array(logsBySequence.keys),
                    in: context
                )

                for (sequenceNum, log) in logsBySequence where !existing.contains(sequenceNum) {
                    let object = NSEntityDescription.insertNewObject(
                        forEntityName: Self.entryEntityName,
                        into: context
                    )
                    object.setValue(Int64(log.pumpSerial), forKey: "pumpSerial")
                    object.setValue(Int64(log.sequenceNum), forKey: "sequenceNum")
                    object.setValue(Int32(log.typeId), forKey: "typeId")
                    object.setValue(Int64(log.pumpTimeSec), forKey: "pumpTimeSec")
                    object.setValue(log.cargo, forKey: "cargo")
                    object.setValue(log.receivedAt, forKey: "receivedAt")

                    pendingInserts += 1
                    if pendingInserts >= Self.batchSize {
                        try context.save()
                        pendingInserts = 0
                    }
                }
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }

    /// Which of `sequenceNumbers` are already stored, asked in chunks so the `IN` predicate stays
    /// within SQLite's host-parameter limit. One query per chunk rather than one per entry.
    private func existingSequenceNumbers(
        pumpSerial: UInt32,
        among sequenceNumbers: [UInt32],
        in context: NSManagedObjectContext
    ) throws -> Set<UInt32> {
        var existing = Set<UInt32>()
        for offset in stride(from: 0, to: sequenceNumbers.count, by: Self.batchSize) {
            let slice = sequenceNumbers[offset ..< min(offset + Self.batchSize, sequenceNumbers.count)]
            let request = NSFetchRequest<NSDictionary>(entityName: Self.entryEntityName)
            request.predicate = NSPredicate(
                format: "pumpSerial == %lld AND sequenceNum IN %@",
                Int64(pumpSerial),
                slice.map { Int64($0) }
            )
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["sequenceNum"]

            for row in try context.fetch(request) {
                if let value = Self.number(row["sequenceNum"])?.int64Value {
                    existing.insert(UInt32(clamping: value))
                }
            }
        }
        return existing
    }

    public func count(pumpSerial: UInt32) throws -> Int {
        try perform { context in
            try context.count(for: self.entryRequest(pumpSerial: pumpSerial))
        }
    }

    public func sequenceNumbers(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [UInt32] {
        try perform { context in
            let request = NSFetchRequest<NSDictionary>(entityName: Self.entryEntityName)
            request.predicate = NSPredicate(
                format: "pumpSerial == %lld AND sequenceNum >= %lld AND sequenceNum <= %lld",
                Int64(pumpSerial),
                Int64(range.lowerBound),
                Int64(range.upperBound)
            )
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["sequenceNum"]
            request.sortDescriptors = [NSSortDescriptor(key: "sequenceNum", ascending: true)]

            return try context.fetch(request).compactMap { row -> UInt32? in
                guard let value = Self.number(row["sequenceNum"])?.int64Value else {
                    return nil
                }
                return UInt32(clamping: value)
            }
        }
    }

    public func logs(pumpSerial: UInt32, in range: ClosedRange<UInt32>) throws -> [StoredHistoryLog] {
        try perform { context in
            let request = self.entryRequest(pumpSerial: pumpSerial)
            request.predicate = NSPredicate(
                format: "pumpSerial == %lld AND sequenceNum >= %lld AND sequenceNum <= %lld",
                Int64(pumpSerial),
                Int64(range.lowerBound),
                Int64(range.upperBound)
            )
            request.sortDescriptors = [NSSortDescriptor(key: "sequenceNum", ascending: true)]
            return try context.fetch(request).map(self.storedLog(from:))
        }
    }

    public func logs(
        pumpSerial: UInt32,
        ofTypes typeIds: [Int],
        sincePumpTimeSec: UInt32
    ) throws -> [StoredHistoryLog] {
        guard !typeIds.isEmpty else {
            return []
        }

        return try perform { context in
            let request = self.entryRequest(pumpSerial: pumpSerial)
            request.predicate = NSPredicate(
                format: "pumpSerial == %lld AND typeId IN %@ AND pumpTimeSec >= %lld",
                Int64(pumpSerial),
                typeIds.map { Int32($0) },
                Int64(sincePumpTimeSec)
            )
            request.sortDescriptors = [NSSortDescriptor(key: "sequenceNum", ascending: true)]
            return try context.fetch(request).map(self.storedLog(from:))
        }
    }

    public func oldest(pumpSerial: UInt32) throws -> StoredHistoryLog? {
        try firstLog(pumpSerial: pumpSerial, ascending: true)
    }

    public func newest(pumpSerial: UInt32) throws -> StoredHistoryLog? {
        try firstLog(pumpSerial: pumpSerial, ascending: false)
    }

    public func newest(pumpSerial: UInt32, ofType typeId: Int) throws -> StoredHistoryLog? {
        try firstLog(pumpSerial: pumpSerial, ascending: false, typeId: typeId)
    }

    public func typeStats(pumpSerial: UInt32) throws -> [HistoryLogTypeStats] {
        try perform { context in
            let request = NSFetchRequest<NSDictionary>(entityName: Self.entryEntityName)
            request.predicate = NSPredicate(format: "pumpSerial == %lld", Int64(pumpSerial))
            request.resultType = .dictionaryResultType
            request.propertiesToGroupBy = ["typeId"]
            request.propertiesToFetch = [
                "typeId",
                Self.expression(named: "count", function: "count:", keyPath: "sequenceNum"),
                Self.expression(named: "latestSequenceNum", function: "max:", keyPath: "sequenceNum"),
                Self.expression(named: "latestPumpTimeSec", function: "max:", keyPath: "pumpTimeSec")
            ]

            return try context.fetch(request)
                .compactMap { row -> HistoryLogTypeStats? in
                    guard let typeId = Self.number(row["typeId"])?.intValue else {
                        return nil
                    }
                    return HistoryLogTypeStats(
                        typeId: typeId,
                        count: Self.number(row["count"])?.intValue ?? 0,
                        latestSequenceNum: UInt32(clamping: Self.number(row["latestSequenceNum"])?.int64Value ?? 0),
                        latestPumpTimeSec: UInt32(clamping: Self.number(row["latestPumpTimeSec"])?.int64Value ?? 0)
                    )
                }
                .sorted { $0.typeId < $1.typeId }
        }
    }

    private static func expression(
        named name: String,
        function: String,
        keyPath: String
    ) -> NSExpressionDescription {
        let description = NSExpressionDescription()
        description.name = name
        description.expression = NSExpression(
            forFunction: function,
            arguments: [NSExpression(forKeyPath: keyPath)]
        )
        description.expressionResultType = .integer64AttributeType
        return description
    }

    public func prunedBelowSequenceNum(pumpSerial: UInt32) throws -> UInt32? {
        try perform { context in
            guard let metadata = try self.metadata(pumpSerial: pumpSerial, in: context),
                  let watermark = Self.number(metadata.value(forKey: "prunedBelowSequenceNum"))?.int64Value,
                  watermark > 0
            else {
                return nil
            }
            return UInt32(clamping: watermark)
        }
    }

    private func metadata(pumpSerial: UInt32, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.metadataEntityName)
        request.predicate = NSPredicate(format: "pumpSerial == %lld", Int64(pumpSerial))
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    @discardableResult
    public func prune(pumpSerial: UInt32, beforePumpTimeSec: UInt32) throws -> Int {
        try perform { context in
            let predicate = NSPredicate(
                format: "pumpSerial == %lld AND pumpTimeSec < %lld",
                Int64(pumpSerial),
                Int64(beforePumpTimeSec)
            )

            // Learn the watermark before deleting: afterwards the rows are gone.
            let highestRequest = NSFetchRequest<NSManagedObject>(entityName: Self.entryEntityName)
            highestRequest.predicate = predicate
            highestRequest.sortDescriptors = [NSSortDescriptor(key: "sequenceNum", ascending: false)]
            highestRequest.fetchLimit = 1
            guard let highest = try context.fetch(highestRequest).first,
                  let highestSequenceNum = Self.number(highest.value(forKey: "sequenceNum"))?.int64Value
            else {
                return 0
            }

            let countRequest = NSFetchRequest<NSManagedObject>(entityName: Self.entryEntityName)
            countRequest.predicate = predicate
            let deletedCount = try context.count(for: countRequest)

            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: Self.entryEntityName)
            )
            deleteRequest.fetchRequest.predicate = predicate
            deleteRequest.resultType = .resultTypeCount
            try context.execute(deleteRequest)

            // A batch delete bypasses the context, so drop any now-stale objects it is holding.
            context.reset()

            try self.advanceWatermark(pumpSerial: pumpSerial, to: highestSequenceNum + 1, in: context)
            try context.save()

            self.log.debug(
                "Pruned \(deletedCount) history entries for pump \(pumpSerial) older than pumpTimeSec \(beforePumpTimeSec)"
            )
            return deletedCount
        }
    }

    private func advanceWatermark(
        pumpSerial: UInt32,
        to sequenceNum: Int64,
        in context: NSManagedObjectContext
    ) throws {
        let object = try metadata(pumpSerial: pumpSerial, in: context)
            ?? NSEntityDescription.insertNewObject(forEntityName: Self.metadataEntityName, into: context)
        object.setValue(Int64(pumpSerial), forKey: "pumpSerial")

        let current = Self.number(object.value(forKey: "prunedBelowSequenceNum"))?.int64Value ?? 0
        object.setValue(max(current, sequenceNum), forKey: "prunedBelowSequenceNum")
    }

    public func deleteAll(pumpSerial: UInt32?) throws {
        try perform { context in
            for entityName in [Self.entryEntityName, Self.metadataEntityName] {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                if let pumpSerial {
                    fetchRequest.predicate = NSPredicate(format: "pumpSerial == %lld", Int64(pumpSerial))
                }
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeCount
                try context.execute(deleteRequest)
            }
            context.reset()
        }
    }
}
