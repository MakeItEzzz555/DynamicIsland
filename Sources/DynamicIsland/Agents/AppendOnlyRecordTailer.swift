import Darwin
import Dispatch
import Foundation

enum AppendOnlyRecordLimits {
    static let maximumRecordBytes = 1_048_576
    static let maximumCatchUpBytes = 1_048_576
    static let maximumCatchUpRecords = 2_000
    static let readChunkBytes = 65_536
}

struct DelimitedRecordFramer: Sendable {
    struct Output: Equatable, Sendable {
        let records: [Data]
        let oversizeRecordsDropped: Int
    }

    let maximumRecordBytes: Int
    private(set) var retainedByteCount = 0
    private var buffer = Data()
    private var droppingOversizeRecord = false

    init(maximumRecordBytes: Int = AppendOnlyRecordLimits.maximumRecordBytes) {
        precondition(maximumRecordBytes > 0)
        self.maximumRecordBytes = maximumRecordBytes
    }

    mutating func feed(_ data: Data) -> Output {
        var records: [Data] = []
        let dropped = consume(data) { records.append($0) }
        return Output(records: records, oversizeRecordsDropped: dropped)
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
        retainedByteCount = 0
        droppingOversizeRecord = false
    }

    /// Feeds bytes without decoding them. The callback is invoked only for a
    /// complete LF-delimited record, keeping split UTF-8 sequences intact.
    @discardableResult
    mutating func consume(
        _ data: Data,
        onRecord: (Data) -> Void
    ) -> Int {
        var dropped = 0
        for byte in data {
            if droppingOversizeRecord {
                if byte == 0x0A {
                    droppingOversizeRecord = false
                    dropped += 1
                }
                continue
            }

            if byte == 0x0A {
                if buffer.last == 0x0D {
                    buffer.removeLast()
                }
                onRecord(buffer)
                buffer.removeAll(keepingCapacity: true)
                retainedByteCount = 0
            } else if buffer.count < maximumRecordBytes {
                buffer.append(byte)
                retainedByteCount = buffer.count
            } else {
                buffer.removeAll(keepingCapacity: false)
                retainedByteCount = 0
                droppingOversizeRecord = true
            }
        }
        return dropped
    }
}

struct AppendOnlyFileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64

    fileprivate init(stat value: stat) {
        device = UInt64(value.st_dev)
        inode = UInt64(value.st_ino)
    }
}

enum AppendOnlyRecordStartPolicy: Equatable, Sendable {
    case fromEnd
    case boundedCatchUp
}

enum AppendOnlyRecordTailerStatus: Equatable, Sendable {
    case stopped
    case waitingForFile
    case tailing
    case degraded
    case failed
}

enum AppendOnlyRecordTailerFailure: Equatable, Sendable {
    case parentUnavailable
    case symlinkRejected
    case notRegularFile
    case permissionDenied
    case identityRace
    case ioFailure
}

enum AppendOnlyRecordTailerNotice: Equatable, Sendable {
    case waitingForFile
    case opened(AppendOnlyFileIdentity)
    case rotated(from: AppendOnlyFileIdentity, to: AppendOnlyFileIdentity)
    case truncated(AppendOnlyFileIdentity)
    case oversizeRecordDropped
    case reopenFailed(AppendOnlyRecordTailerFailure)
}

struct AppendOnlyRecordTailerHealth: Equatable, Sendable {
    var status: AppendOnlyRecordTailerStatus = .stopped
    var recordsEmitted: UInt64 = 0
    var oversizeRecordsDropped: UInt64 = 0
    var bytesRead: UInt64 = 0
    var rotations: UInt64 = 0
    var truncations: UInt64 = 0
    var reopenFailures: UInt64 = 0
    var lastFailure: AppendOnlyRecordTailerFailure?
}

/// Ownership token carried by file-system callbacks. It is intentionally
/// independent of file content so callbacks from an earlier start or inode
/// incarnation can be rejected deterministically.
struct AppendOnlyRecordTailerSignalToken: Equatable, Sendable {
    let lifecycleGeneration: UInt64
    let fileGeneration: UInt64
}

private enum AppendOnlyRecordTailerIOError: Error {
    case missing
    case failure(AppendOnlyRecordTailerFailure)
}

/// Provider-neutral physical reader for one append-only, LF-delimited file.
/// Provider parsing and session identity deliberately live above this type.
actor AppendOnlyRecordTailer {
    typealias RecordHandler = @Sendable (Data) -> Void
    typealias NoticeHandler = @Sendable (AppendOnlyRecordTailerNotice) -> Void

    private struct OpenFile {
        let readDescriptor: Int32
        let watchDescriptor: Int32
        let identity: AppendOnlyFileIdentity
        let size: Int64
    }

    private let fileURL: URL
    private let initialPolicy: AppendOnlyRecordStartPolicy
    private let replacementPolicy: AppendOnlyRecordStartPolicy
    private let recordHandler: RecordHandler
    private let noticeHandler: NoticeHandler
    private let watcherQueue = DispatchQueue(label: "com.local.dynamicisland.agent-record-tailer")

    private var health = AppendOnlyRecordTailerHealth()
    private var framer = DelimitedRecordFramer()
    private var started = false
    private var lifecycleGeneration: UInt64 = 0
    private var fileGeneration: UInt64 = 0
    private var identity: AppendOnlyFileIdentity?
    private var previousIdentity: AppendOnlyFileIdentity?
    private var offset: Int64 = 0
    private var lastObservedSize: Int64 = 0
    private var readDescriptor: Int32?
    private var fileSource: DispatchSourceFileSystemObject?
    private var parentSource: DispatchSourceFileSystemObject?

    init(
        fileURL: URL,
        initialPolicy: AppendOnlyRecordStartPolicy,
        replacementPolicy: AppendOnlyRecordStartPolicy = .boundedCatchUp,
        onRecord: @escaping RecordHandler,
        onNotice: @escaping NoticeHandler = { _ in }
    ) {
        self.fileURL = fileURL
        self.initialPolicy = initialPolicy
        self.replacementPolicy = replacementPolicy
        recordHandler = onRecord
        noticeHandler = onNotice
    }

    func start() async {
        guard !started else { return }
        started = true
        lifecycleGeneration &+= 1
        health = AppendOnlyRecordTailerHealth(status: .waitingForFile)
        installParentWatcher(lifecycle: lifecycleGeneration)
        reconcileInternal(isInitial: true)
    }

    func stop() async {
        guard started || health.status != .stopped else { return }
        started = false
        lifecycleGeneration &+= 1
        fileGeneration &+= 1
        cancelFileResources()
        cancelParentWatcher()
        identity = nil
        previousIdentity = nil
        offset = 0
        lastObservedSize = 0
        framer.reset()
        health.status = .stopped
        health.lastFailure = nil
        await drainWatcherQueue()
    }

    /// Reconciles identity, size and unread bytes. Future sleep/wake integration
    /// can invoke this without coupling the primitive to application lifecycle.
    func reconcile() {
        guard started else { return }
        reconcileInternal(isInitial: false)
    }

    func healthSnapshot() -> AppendOnlyRecordTailerHealth {
        health
    }

    func currentFileIdentity() -> AppendOnlyFileIdentity? {
        identity
    }

    func currentFileSignalToken() -> AppendOnlyRecordTailerSignalToken {
        AppendOnlyRecordTailerSignalToken(
            lifecycleGeneration: lifecycleGeneration,
            fileGeneration: fileGeneration
        )
    }

    func reconcile(fileSignal token: AppendOnlyRecordTailerSignalToken) {
        handleFileSignal(token)
    }

    private func reconcileInternal(isInitial: Bool) {
        if parentSource == nil {
            installParentWatcher(lifecycle: lifecycleGeneration)
        }

        let opened: OpenFile
        do {
            opened = try openFilePair()
        } catch AppendOnlyRecordTailerIOError.missing {
            transitionToMissing()
            return
        } catch AppendOnlyRecordTailerIOError.failure(let failure) {
            recordReopenFailure(failure)
            return
        } catch {
            recordReopenFailure(.ioFailure)
            return
        }

        if opened.identity == identity, let currentDescriptor = readDescriptor {
            Darwin.close(opened.readDescriptor)
            Darwin.close(opened.watchDescriptor)
            reconcileOpenDescriptor(currentDescriptor, observedSize: opened.size)
            return
        }

        let priorIdentity = identity ?? previousIdentity
        cancelFileResources()
        fileGeneration &+= 1
        identity = opened.identity
        previousIdentity = nil
        readDescriptor = opened.readDescriptor
        offset = 0
        lastObservedSize = opened.size
        framer.reset()
        installFileWatcher(
            descriptor: opened.watchDescriptor,
            lifecycle: lifecycleGeneration,
            file: fileGeneration
        )

        if let priorIdentity {
            health.rotations = health.rotations.saturatingIncremented()
            noticeHandler(.rotated(from: priorIdentity, to: opened.identity))
        } else {
            noticeHandler(.opened(opened.identity))
        }

        applyStartPolicy(isInitial ? initialPolicy : replacementPolicy, snapshotSize: opened.size)
        health.status = .tailing
        health.lastFailure = nil
    }

    private func reconcileOpenDescriptor(_ descriptor: Int32, observedSize: Int64) {
        if observedSize < offset {
            fileGeneration &+= 1
            health.truncations = health.truncations.saturatingIncremented()
            if let identity { noticeHandler(.truncated(identity)) }
            offset = 0
            lastObservedSize = observedSize
            framer.reset()
            reinstallFileWatcher()
            readBoundedCatchUp(snapshotSize: observedSize)
        } else {
            readLiveBytes(until: observedSize)
        }
        lastObservedSize = observedSize
        health.status = .tailing
        health.lastFailure = nil
    }

    private func applyStartPolicy(_ policy: AppendOnlyRecordStartPolicy, snapshotSize: Int64) {
        switch policy {
        case .fromEnd:
            offset = max(0, snapshotSize)
            lastObservedSize = max(0, snapshotSize)
        case .boundedCatchUp:
            readBoundedCatchUp(snapshotSize: snapshotSize)
        }
    }

    private func readBoundedCatchUp(snapshotSize: Int64) {
        guard let descriptor = readDescriptor else { return }
        let boundedSize = max(0, snapshotSize)
        let start = max(0, boundedSize - Int64(AppendOnlyRecordLimits.maximumCatchUpBytes))
        offset = start
        framer.reset()

        var discardInitialFragment = false
        if start > 0 {
            do {
                let previous = try readBytes(descriptor: descriptor, offset: start - 1, count: 1)
                discardInitialFragment = previous.first != 0x0A
            } catch {
                recordReopenFailure(.ioFailure)
                return
            }
        }

        var ring = BoundedRecordRing(capacity: AppendOnlyRecordLimits.maximumCatchUpRecords)
        while offset < boundedSize {
            let count = min(AppendOnlyRecordLimits.readChunkBytes, Int(boundedSize - offset))
            let data: Data
            do {
                data = try readBytes(descriptor: descriptor, offset: offset, count: count)
            } catch {
                recordReopenFailure(.ioFailure)
                return
            }
            guard !data.isEmpty else { break }
            offset += Int64(data.count)
            health.bytesRead = health.bytesRead.saturatingAdding(UInt64(data.count))

            var framedData = data
            if discardInitialFragment {
                if let delimiter = framedData.firstIndex(of: 0x0A) {
                    framedData = Data(framedData[framedData.index(after: delimiter)...])
                    discardInitialFragment = false
                } else {
                    continue
                }
            }

            let dropped = framer.consume(framedData) { ring.append($0) }
            recordOversizeDrops(dropped)
        }
        // The cursor always advances to the catch-up snapshot even when its
        // record count is capped, so later events cannot leak old history.
        offset = boundedSize
        for record in ring.orderedRecords {
            emit(record)
        }
    }

    private func readLiveBytes(until snapshotSize: Int64) {
        guard let descriptor = readDescriptor else { return }
        let end = max(offset, snapshotSize)
        while offset < end {
            let count = min(AppendOnlyRecordLimits.readChunkBytes, Int(end - offset))
            let data: Data
            do {
                data = try readBytes(descriptor: descriptor, offset: offset, count: count)
            } catch {
                recordReopenFailure(.ioFailure)
                return
            }
            guard !data.isEmpty else { break }
            offset += Int64(data.count)
            health.bytesRead = health.bytesRead.saturatingAdding(UInt64(data.count))
            let dropped = framer.consume(data) { emit($0) }
            recordOversizeDrops(dropped)
        }
    }

    private func emit(_ record: Data) {
        health.recordsEmitted = health.recordsEmitted.saturatingIncremented()
        recordHandler(record)
    }

    private func recordOversizeDrops(_ count: Int) {
        guard count > 0 else { return }
        health.oversizeRecordsDropped = health.oversizeRecordsDropped.saturatingAdding(UInt64(count))
        health.status = .degraded
        for _ in 0..<count { noticeHandler(.oversizeRecordDropped) }
    }

    private func transitionToMissing() {
        fileGeneration &+= 1
        cancelFileResources()
        previousIdentity = identity ?? previousIdentity
        identity = nil
        offset = 0
        lastObservedSize = 0
        framer.reset()
        health.status = .waitingForFile
        health.lastFailure = nil
        noticeHandler(.waitingForFile)
    }

    private func recordReopenFailure(_ failure: AppendOnlyRecordTailerFailure) {
        health.reopenFailures = health.reopenFailures.saturatingIncremented()
        health.lastFailure = failure
        health.status = failure == .notRegularFile || failure == .symlinkRejected ? .failed : .degraded
        noticeHandler(.reopenFailed(failure))
    }

    private func openFilePair() throws -> OpenFile {
        let readFD = try openDescriptor(fileURL, flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        var readStat = stat()
        guard fstat(readFD, &readStat) == 0 else {
            Darwin.close(readFD)
            throw AppendOnlyRecordTailerIOError.failure(.ioFailure)
        }
        guard (readStat.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(readFD)
            throw AppendOnlyRecordTailerIOError.failure(.notRegularFile)
        }
        let readIdentity = AppendOnlyFileIdentity(stat: readStat)

        let watchFD: Int32
        do {
            watchFD = try openDescriptor(fileURL, flags: O_EVTONLY | O_CLOEXEC | O_NOFOLLOW)
        } catch {
            Darwin.close(readFD)
            throw error
        }
        var watchStat = stat()
        guard fstat(watchFD, &watchStat) == 0 else {
            Darwin.close(readFD)
            Darwin.close(watchFD)
            throw AppendOnlyRecordTailerIOError.failure(.ioFailure)
        }
        guard AppendOnlyFileIdentity(stat: watchStat) == readIdentity else {
            Darwin.close(readFD)
            Darwin.close(watchFD)
            throw AppendOnlyRecordTailerIOError.failure(.identityRace)
        }
        return OpenFile(
            readDescriptor: readFD,
            watchDescriptor: watchFD,
            identity: readIdentity,
            size: max(0, Int64(readStat.st_size))
        )
    }

    private func openDescriptor(_ url: URL, flags: Int32) throws -> Int32 {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, flags)
        }
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT: throw AppendOnlyRecordTailerIOError.missing
            case ELOOP: throw AppendOnlyRecordTailerIOError.failure(.symlinkRejected)
            case EACCES, EPERM: throw AppendOnlyRecordTailerIOError.failure(.permissionDenied)
            default: throw AppendOnlyRecordTailerIOError.failure(.ioFailure)
            }
        }
        return descriptor
    }

    private func readBytes(descriptor: Int32, offset: Int64, count: Int) throws -> Data {
        guard count > 0, offset >= 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        while true {
            let result = pread(descriptor, &bytes, count, off_t(offset))
            if result >= 0 { return Data(bytes.prefix(Int(result))) }
            if errno != EINTR { throw AppendOnlyRecordTailerIOError.failure(.ioFailure) }
        }
    }

    private func installFileWatcher(descriptor: Int32, lifecycle: UInt64, file: UInt64) {
        let owner = self
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: watcherQueue
        )
        let token = AppendOnlyRecordTailerSignalToken(
            lifecycleGeneration: lifecycle,
            fileGeneration: file
        )
        source.setEventHandler {
            Task { await owner.handleFileSignal(token) }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        fileSource = source
        source.activate()
    }

    private func reinstallFileWatcher() {
        fileSource?.cancel()
        fileSource = nil
        guard let identity else { return }
        let watchFD: Int32
        do {
            watchFD = try openDescriptor(fileURL, flags: O_EVTONLY | O_CLOEXEC | O_NOFOLLOW)
        } catch {
            recordReopenFailure(.ioFailure)
            return
        }
        var value = stat()
        guard fstat(watchFD, &value) == 0,
              AppendOnlyFileIdentity(stat: value) == identity else {
            Darwin.close(watchFD)
            recordReopenFailure(.identityRace)
            return
        }
        installFileWatcher(descriptor: watchFD, lifecycle: lifecycleGeneration, file: fileGeneration)
    }

    private func installParentWatcher(lifecycle: UInt64) {
        guard parentSource == nil else { return }
        let parent = fileURL.deletingLastPathComponent()
        let descriptor: Int32
        do {
            descriptor = try openDescriptor(parent, flags: O_EVTONLY | O_CLOEXEC | O_NOFOLLOW)
        } catch {
            health.status = .degraded
            health.lastFailure = .parentUnavailable
            noticeHandler(.reopenFailed(.parentUnavailable))
            return
        }
        var value = stat()
        guard fstat(descriptor, &value) == 0, (value.st_mode & S_IFMT) == S_IFDIR else {
            Darwin.close(descriptor)
            health.status = .degraded
            health.lastFailure = .parentUnavailable
            return
        }
        let owner = self
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: watcherQueue
        )
        source.setEventHandler {
            Task { await owner.handleParentSignal(lifecycle: lifecycle) }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        parentSource = source
        source.activate()
    }

    private func handleFileSignal(_ token: AppendOnlyRecordTailerSignalToken) {
        guard started,
              token.lifecycleGeneration == lifecycleGeneration,
              token.fileGeneration == fileGeneration else { return }
        reconcileInternal(isInitial: false)
    }

    private func handleParentSignal(lifecycle: UInt64) {
        guard started, lifecycle == lifecycleGeneration else { return }
        // A directory source follows its inode. Reinstall before resolving the
        // child path so replacement of the watched directory cannot leave a
        // permanently stale source behind.
        cancelParentWatcher()
        installParentWatcher(lifecycle: lifecycle)
        reconcileInternal(isInitial: false)
    }

    private func cancelFileResources() {
        fileSource?.cancel()
        fileSource = nil
        if let readDescriptor {
            Darwin.close(readDescriptor)
            self.readDescriptor = nil
        }
    }

    private func cancelParentWatcher() {
        parentSource?.cancel()
        parentSource = nil
    }

    private func drainWatcherQueue() async {
        await withCheckedContinuation { continuation in
            watcherQueue.async { continuation.resume() }
        }
    }
}

private struct BoundedRecordRing {
    private let capacity: Int
    private var storage: [Data?]
    private var count = 0
    private var next = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ record: Data) {
        guard capacity > 0 else { return }
        storage[next] = record
        next = (next + 1) % capacity
        count = min(capacity, count + 1)
    }

    var orderedRecords: [Data] {
        guard count > 0 else { return [] }
        let start = count == capacity ? next : 0
        return (0..<count).compactMap { storage[(start + $0) % capacity] }
    }
}

private extension UInt64 {
    func saturatingIncremented() -> UInt64 {
        self == .max ? .max : self + 1
    }

    func saturatingAdding(_ value: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(value)
        return overflow ? .max : result
    }
}
