import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import DynamicIsland

private enum FileDropProviderTestError: Error {
    case requestedFailure
}

private final class ControlledDataRepresentation: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Data?, Error?) -> Void)?
    let requested = XCTestExpectation(description: "Provider representation requested")

    func makeProvider(typeIdentifier: String, suggestedName: String? = nil) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { [self] completion in
            lock.withLock { self.completion = completion }
            requested.fulfill()
            return Progress(totalUnitCount: 1)
        }
        return provider
    }

    func succeed(with data: Data) {
        let callback = lock.withLock { completion }
        callback?(data, nil)
    }

    func fail() {
        let callback = lock.withLock { completion }
        callback?(nil, FileDropProviderTestError.requestedFailure)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }
}

final class FileDropProviderLoaderTests: XCTestCase {
    private var testRoot: URL!
    private var providerTemporaryRoot: URL!
    private var shelfRoot: URL!
    private var storage: FileShelfTemporaryStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDropProviderLoaderTests-\(UUID().uuidString)", isDirectory: true)
        providerTemporaryRoot = testRoot.appendingPathComponent("Provider", isDirectory: true)
        shelfRoot = testRoot.appendingPathComponent("Shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: providerTemporaryRoot, withIntermediateDirectories: true)
        storage = FileShelfTemporaryStorage(
            rootURL: shelfRoot,
            providerTemporaryRootURL: providerTemporaryRoot
        )
    }

    override func tearDownWithError() throws {
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        storage = nil
        shelfRoot = nil
        providerTemporaryRoot = nil
        testRoot = nil
        try super.tearDownWithError()
    }

    func testImmediateStableFileURLIsReturnedWithoutCopying() throws {
        let stableDirectory = testRoot.appendingPathComponent("Stable", isDirectory: true)
        try FileManager.default.createDirectory(at: stableDirectory, withIntermediateDirectories: true)
        let stableURL = stableDirectory.appendingPathComponent("document.txt")
        try Data("stable".utf8).write(to: stableURL)
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(typeIdentifier: UTType.fileURL.identifier)
        let loaded = expectation(description: "Stable URL loaded")
        let result = LockedValue<[URL]>([])

        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { urls in
            result.set(urls)
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)
        representation.succeed(with: stableURL.dataRepresentation)
        wait(for: [loaded], timeout: 1)

        XCTAssertEqual(result.value, [stableURL.standardizedFileURL])
        XCTAssertFalse(storage.isOwned(try XCTUnwrap(result.value.first)))
    }

    func testTemporaryFileURLIsCopiedBeforeProviderSourceDisappears() throws {
        let providerURL = providerTemporaryRoot.appendingPathComponent("temporary.png")
        let contents = Data("temporary image".utf8)
        try contents.write(to: providerURL)
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(typeIdentifier: UTType.fileURL.identifier)
        let loaded = expectation(description: "Temporary URL loaded")
        let result = LockedValue<[URL]>([])

        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { urls in
            result.set(urls)
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)
        representation.succeed(with: providerURL.dataRepresentation)
        wait(for: [loaded], timeout: 1)
        try FileManager.default.removeItem(at: providerURL)

        let durableURL = try XCTUnwrap(result.value.first)
        XCTAssertTrue(storage.isOwned(durableURL))
        XCTAssertEqual(try Data(contentsOf: durableURL), contents)
    }

    func testDelayedPNGProviderMaterializesScreenshotLikeRepresentation() throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(
            typeIdentifier: UTType.png.identifier,
            suggestedName: "Screenshot"
        )
        let loaded = expectation(description: "Delayed PNG loaded")
        let result = LockedValue<[URL]>([])

        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { urls in
            result.set(urls)
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)
        XCTAssertTrue(result.value.isEmpty)

        representation.succeed(with: pngData)
        wait(for: [loaded], timeout: 1)

        let durableURL = try XCTUnwrap(result.value.first)
        XCTAssertTrue(storage.isOwned(durableURL))
        XCTAssertEqual(durableURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: durableURL), pngData)
    }

    func testDelayedProviderFailureDoesNotProduceShelfURL() {
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(typeIdentifier: UTType.png.identifier)
        let loaded = expectation(description: "Failure completed")
        let result = LockedValue<[URL]>([])

        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { urls in
            result.set(urls)
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)
        representation.fail()
        wait(for: [loaded], timeout: 1)

        XCTAssertTrue(result.value.isEmpty)
    }

    func testOverlappingDelayedProvidersCompleteIndependently() throws {
        let first = ControlledDataRepresentation()
        let second = ControlledDataRepresentation()
        let firstProvider = first.makeProvider(typeIdentifier: UTType.png.identifier, suggestedName: "A.png")
        let secondProvider = second.makeProvider(typeIdentifier: UTType.png.identifier, suggestedName: "B.png")
        let firstLoaded = expectation(description: "First loaded")
        let secondLoaded = expectation(description: "Second loaded")
        let firstResult = LockedValue<[URL]>([])
        let secondResult = LockedValue<[URL]>([])
        let loader = FileDropProviderLoader(temporaryStorage: storage)

        loader.loadURLs(from: [firstProvider]) { urls in
            firstResult.set(urls)
            firstLoaded.fulfill()
        }
        loader.loadURLs(from: [secondProvider]) { urls in
            secondResult.set(urls)
            secondLoaded.fulfill()
        }
        wait(for: [first.requested, second.requested], timeout: 1)

        second.succeed(with: Data("B".utf8))
        wait(for: [secondLoaded], timeout: 1)
        XCTAssertTrue(firstResult.value.isEmpty)
        first.succeed(with: Data("A".utf8))
        wait(for: [firstLoaded], timeout: 1)

        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(firstResult.value.first)), Data("A".utf8))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(secondResult.value.first)), Data("B".utf8))
    }


    func testJPEGFileRepresentationMaterializesForPhotosStyleProvider() throws {
        let providerFile = providerTemporaryRoot.appendingPathComponent("provider-photo.jpg")
        try Data("jpeg-bytes".utf8).write(to: providerFile)
        let provider = NSItemProvider()
        provider.suggestedName = "Vacation Photo"
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(providerFile, false, nil)
            return Progress(totalUnitCount: 1)
        }
        let loader = FileDropProviderLoader(temporaryStorage: storage)
        XCTAssertTrue(loader.canLoad([provider]))
        let loaded = expectation(description: "JPEG representation loaded")
        let result = LockedValue<[URL]>([])

        loader.loadURLs(from: [provider]) { urls in
            result.set(urls)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)

        let durable = try XCTUnwrap(result.value.first)
        XCTAssertTrue(storage.isOwned(durable))
        XCTAssertEqual(durable.pathExtension.lowercased(), "jpeg")
        XCTAssertEqual(try Data(contentsOf: durable), Data("jpeg-bytes".utf8))
    }


    func testPromisedFileRepresentationMaterializesForShelfDrop() throws {
        let promiseIdentifier = try XCTUnwrap(NSFilePromiseReceiver.readableDraggedTypes.first)
        let providerFile = providerTemporaryRoot.appendingPathComponent("promised-export.mov")
        try Data("movie-bytes".utf8).write(to: providerFile)
        let provider = NSItemProvider()
        provider.suggestedName = "Promised Export.mov"
        provider.registerFileRepresentation(
            forTypeIdentifier: promiseIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(providerFile, false, nil)
            return Progress(totalUnitCount: 1)
        }
        let loader = FileDropProviderLoader(temporaryStorage: storage)
        XCTAssertTrue(loader.canLoad([provider]))
        let loaded = expectation(description: "promised representation loaded")
        let result = LockedValue<[URL]>([])

        loader.loadURLs(from: [provider]) { urls in
            result.set(urls)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)

        let durable = try XCTUnwrap(result.value.first)
        XCTAssertTrue(storage.isOwned(durable))
        XCTAssertEqual(durable.lastPathComponent.hasSuffix("Promised Export.mov"), true)
        XCTAssertEqual(try Data(contentsOf: durable), Data("movie-bytes".utf8))
    }

    func testUnsupportedTextProviderFailsClosed() {
        let provider = NSItemProvider(item: Data("text".utf8) as NSData, typeIdentifier: UTType.plainText.identifier)
        XCTAssertFalse(FileDropProviderLoader(temporaryStorage: storage).canLoad([provider]))
    }


    func testAcceptedTypesIncludeNativeFilePromiseWakeTypes() {
        let accepted = Set(FileDropProviderLoader.acceptedTypes.map(\.identifier))
        for type in NSFilePromiseReceiver.readableDraggedTypes {
            XCTAssertTrue(accepted.contains(UTType(importedAs: type).identifier))
        }
    }

    @MainActor
    func testAcceptedDropEndsTargetingWhileProviderRemainsPending() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let navigation = IslandNavigationStore()
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(typeIdentifier: UTType.png.identifier)
        let loaded = expectation(description: "Provider completed")

        navigation.showTrayForFileDrag(using: settings)
        XCTAssertTrue(navigation.isFileDropTargeted)
        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { _ in
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)

        navigation.endFileDropTargeting()

        XCTAssertFalse(navigation.isFileDropTargeted)
        representation.succeed(with: Data("screenshot".utf8))
        wait(for: [loaded], timeout: 1)
        XCTAssertFalse(navigation.isFileDropTargeted)
    }

    @MainActor
    func testDelayedCompletionCannotClearNewerDragTargeting() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let navigation = IslandNavigationStore()
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(typeIdentifier: UTType.png.identifier)
        let loaded = expectation(description: "Older provider completed")

        navigation.showTrayForFileDrag(using: settings)
        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { _ in
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)
        navigation.endFileDropTargeting()

        navigation.showTrayForFileDrag(using: settings)
        XCTAssertTrue(navigation.isFileDropTargeted)
        representation.succeed(with: Data("older".utf8))
        wait(for: [loaded], timeout: 1)

        XCTAssertTrue(navigation.isFileDropTargeted)
        navigation.endFileDropTargeting()
    }

    @MainActor
    func testAcceptedProviderFailureLeavesTargetingEnded() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let navigation = IslandNavigationStore()
        let representation = ControlledDataRepresentation()
        let provider = representation.makeProvider(typeIdentifier: UTType.png.identifier)
        let loaded = expectation(description: "Provider failure completed")

        navigation.showTrayForFileDrag(using: settings)
        FileDropProviderLoader(temporaryStorage: storage).loadURLs(from: [provider]) { _ in
            loaded.fulfill()
        }
        wait(for: [representation.requested], timeout: 1)
        navigation.endFileDropTargeting()
        representation.fail()
        wait(for: [loaded], timeout: 1)

        XCTAssertFalse(navigation.isFileDropTargeted)
    }

    @MainActor
    func testDragExitEndsTargetingWithoutProviderCompletion() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let navigation = IslandNavigationStore()

        navigation.showTrayForFileDrag(using: settings)
        XCTAssertTrue(navigation.isFileDropTargeted)

        navigation.endFileDropTargeting()

        XCTAssertFalse(navigation.isFileDropTargeted)
    }

    @MainActor
    func testDisabledPoliciesRejectDropsAtAcceptanceAndCompletionChecks() {
        let suiteName = "FileDropPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(FileDropPolicy.allowsCollapsedDrop(settings: settings))
        XCTAssertTrue(FileDropPolicy.allowsExpandedDrop(settings: settings))

        settings.allowFileDropsOnCollapsedIsland = false
        XCTAssertFalse(FileDropPolicy.allowsCollapsedDrop(settings: settings))
        settings.allowFileDropsOnExpandedTray = false
        XCTAssertFalse(FileDropPolicy.allowsExpandedDrop(settings: settings))
        settings.fileShelfEnabled = false
        XCTAssertFalse(FileDropPolicy.allowsCollapsedDrop(settings: settings))
        XCTAssertFalse(FileDropPolicy.allowsExpandedDrop(settings: settings))
    }

    @MainActor
    private func makeSettings() -> (AppSettings, UserDefaults, String) {
        let suiteName = "FileDropTargetingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (AppSettings(defaults: defaults), defaults, suiteName)
    }
}
