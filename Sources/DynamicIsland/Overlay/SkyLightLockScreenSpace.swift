import AppKit
import Darwin

/// Experimental, user-approved (D3) private SkyLight space above the secure
/// lock screen. Independently written from the observed call sequence
/// (Droppy 16.0.1 + MIT SkyLightWindow) and the CGSInternal declarations:
/// CGSSpaceID is 64-bit and `SLSSpaceCreate` takes (cid, flag, options).
/// Every symbol is resolved before use; any failure leaves it unavailable.
/// Measured on macOS 15.7.4: `SLSSpaceSetAbsoluteLevel` returns 0 (CGError),
/// while `SLSShowSpaces` returns 1 on success and
/// `SLSSpaceAddWindowsAndRemoveFromSpaces` returns no value at all, so those
/// two are declared `Void` and never read as status codes.
@MainActor
final class SkyLightLockScreenSpace: LockScreenSpaceProviding {
    /// Above `kCGSSpaceAbsoluteLevelScreenLock` (300); Notification Center's
    /// lock-screen layer.
    static let absoluteLevel: Int32 = 400
    /// Only versions this was actually tested on.
    nonisolated static func isTestedOS(_ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        version.majorVersion == 15 && version.minorVersion == 7
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, UnsafeRawPointer?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowHideSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Int32

    private struct Functions {
        let mainConnectionID: MainConnectionID
        let spaceCreate: SpaceCreate
        let setAbsoluteLevel: SpaceSetAbsoluteLevel
        let showSpaces: ShowHideSpaces
        let addWindows: SpaceAddWindows
        let hideSpaces: ShowHideSpaces?
        let destroy: SpaceDestroy?
    }

    private(set) var availability: LockScreenSpaceAvailability
    private let functions: Functions?
    private var connection: Int32 = 0
    private var space: UInt64 = 0
    private var adoptedWindows: Set<Int> = []

    init(isTestedOS: Bool = SkyLightLockScreenSpace.isTestedOS(),
         loadSymbol: (String) -> UnsafeMutableRawPointer? = SkyLightLockScreenSpace.systemSymbol) {
        guard isTestedOS else {
            functions = nil
            availability = .unavailable(reason: "Lock Screen widgets are only enabled on tested macOS versions (15.7).")
            return
        }
        func resolve<T>(_ name: String, as type: T.Type) -> T? {
            loadSymbol(name).map { unsafeBitCast($0, to: type) }
        }
        guard let main = resolve("SLSMainConnectionID", as: MainConnectionID.self),
              let create = resolve("SLSSpaceCreate", as: SpaceCreate.self),
              let level = resolve("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = resolve("SLSShowSpaces", as: ShowHideSpaces.self),
              let add = resolve("SLSSpaceAddWindowsAndRemoveFromSpaces", as: SpaceAddWindows.self) else {
            functions = nil
            availability = .unavailable(reason: "This macOS version no longer provides the required system functions.")
            return
        }
        functions = Functions(mainConnectionID: main, spaceCreate: create, setAbsoluteLevel: level, showSpaces: show,
                              addWindows: add, hideSpaces: resolve("SLSHideSpaces", as: ShowHideSpaces.self),
                              destroy: resolve("SLSSpaceDestroy", as: SpaceDestroy.self))
        availability = .available
    }

    /// Creates and raises the space once, never at launch: only when the user
    /// enabled the feature, while the desktop is unlocked.
    func prepare() -> Bool {
        guard availability == .available, let functions else { return false }
        if space == 0 {
            let connection = functions.mainConnectionID()
            guard connection != 0 else { return fail("No window-server connection.") }
            let space = functions.spaceCreate(connection, 1, nil)
            guard space != 0 else { return fail("The lock-screen space could not be created.") }
            guard functions.setAbsoluteLevel(connection, space, Self.absoluteLevel) == 0 else {
                _ = functions.destroy?(connection, space)
                return fail("The lock-screen space could not be raised.")
            }
            functions.showSpaces(connection, [NSNumber(value: space)] as CFArray)
            self.connection = connection
            self.space = space
        }
        return true
    }

    func adopt(windowNumber: Int) -> Bool {
        guard windowNumber > 0, prepare(), let functions else { return false }
        if adoptedWindows.contains(windowNumber) { return true }
        functions.addWindows(connection, space, [NSNumber(value: windowNumber)] as CFArray, 7)
        adoptedWindows.insert(windowNumber)
        return true
    }

    func teardown() {
        guard space != 0, let functions else { adoptedWindows.removeAll(); return }
        functions.hideSpaces?(connection, [NSNumber(value: space)] as CFArray)
        _ = functions.destroy?(connection, space)
        space = 0
        adoptedWindows.removeAll()
    }

    private func fail(_ reason: String) -> Bool {
        availability = .unavailable(reason: reason)
        return false
    }

    nonisolated static func systemSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY) else {
            return nil
        }
        return dlsym(handle, name)
    }
}
