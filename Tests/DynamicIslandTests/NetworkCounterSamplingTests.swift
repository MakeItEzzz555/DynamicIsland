import Darwin
import XCTest
@testable import DynamicIsland

final class NetworkCounterSamplingTests: XCTestCase {
    func testIncreasingCountersPreserveBytesPerSecond() {
        let rates = NetworkCounters(sent: 160, received: 340)
            .rates(since: NetworkCounters(sent: 100, received: 100), interval: 2)
        XCTAssertEqual(rates?.upload, 30)
        XCTAssertEqual(rates?.download, 120)
    }

    func testEqualCountersProduceZeroRates() {
        let counters = NetworkCounters(sent: 100, received: 200)
        let rates = counters.rates(since: counters, interval: 1)
        XCTAssertEqual(rates?.upload, 0)
        XCTAssertEqual(rates?.download, 0)
    }

    func testResetProducesZeroAndNextSampleUsesFreshBaseline() {
        let reset = NetworkCounters(sent: 10, received: 20)
        let rates = reset.rates(since: NetworkCounters(sent: 100, received: 200), interval: 1)
        XCTAssertEqual(rates?.upload, 0)
        XCTAssertEqual(rates?.download, 0)
        let next = NetworkCounters(sent: 40, received: 70).rates(since: reset, interval: 1)
        XCTAssertEqual(next?.upload, 30)
        XCTAssertEqual(next?.download, 50)
    }

    func testDirectionsResetIndependentlyAndKeepMinimumInterval() {
        let rates = NetworkCounters(sent: 10, received: 210)
            .rates(since: NetworkCounters(sent: 100, received: 200), interval: 0)
        XCTAssertEqual(rates?.upload, 0)
        XCTAssertEqual(rates?.download, 100)
    }

    func testWrappedCountersDoNotUnderflow() {
        let rates = NetworkCounters(sent: 0, received: 1)
            .rates(since: NetworkCounters(sent: .max, received: .max), interval: 1)
        XCTAssertEqual(rates?.upload, 0)
        XCTAssertEqual(rates?.download, 0)
    }

    func testFirstSampleEstablishesBaseline() {
        XCTAssertNil(NetworkCounters(sent: 100, received: 200).rates(since: nil, interval: 1))
    }

    func testAppearingAndRemovedInterfacesAreSampledSafely() {
        let first = Interface(sent: 100, received: 200)
        let added = Interface(sent: 20, received: 30)
        let before = NetworkCounters.read(from: first.record)
        first.record.pointee.ifa_next = added.record
        let appeared = NetworkCounters.read(from: first.record)
        let increase = appeared.rates(since: before, interval: 1)
        XCTAssertEqual(increase?.upload, 20)
        XCTAssertEqual(increase?.download, 30)
        first.record.pointee.ifa_next = nil
        let removed = NetworkCounters.read(from: first.record).rates(since: appeared, interval: 1)
        XCTAssertEqual(removed?.upload, 0)
        XCTAssertEqual(removed?.download, 0)
        let empty = NetworkCounters.read(from: nil).rates(since: before, interval: 1)
        XCTAssertEqual(empty?.upload, 0)
        XCTAssertEqual(empty?.download, 0)
    }

    func testAddresslessRecordIsSkippedAndTraversalContinues() {
        let addressless = Interface(sent: 500, received: 600)
        addressless.record.pointee.ifa_addr = nil
        let valid = Interface(sent: 10, received: 20)
        addressless.record.pointee.ifa_next = valid.record
        let counters = NetworkCounters.read(from: addressless.record)
        XCTAssertEqual(counters.sent, 10)
        XCTAssertEqual(counters.received, 20)
    }

    func testLoopbackNonLinkAndMissingDataRecordsAreSkipped() {
        let loopback = Interface(sent: 100, received: 200)
        loopback.record.pointee.ifa_flags = UInt32(IFF_LOOPBACK)
        let nonLink = Interface(sent: 300, received: 400)
        nonLink.address.pointee.sa_family = UInt8(AF_INET)
        let missingData = Interface(sent: 500, received: 600)
        missingData.record.pointee.ifa_data = nil
        loopback.record.pointee.ifa_next = nonLink.record
        nonLink.record.pointee.ifa_next = missingData.record
        let counters = NetworkCounters.read(from: loopback.record)
        XCTAssertEqual(counters.sent, 0)
        XCTAssertEqual(counters.received, 0)
    }

    private final class Interface {
        let record = UnsafeMutablePointer<ifaddrs>.allocate(capacity: 1)
        let address = UnsafeMutablePointer<sockaddr>.allocate(capacity: 1)
        let data = UnsafeMutablePointer<if_data>.allocate(capacity: 1)

        init(sent: UInt32, received: UInt32) {
            record.initialize(to: ifaddrs())
            address.initialize(to: sockaddr())
            data.initialize(to: if_data())
            address.pointee.sa_family = UInt8(AF_LINK)
            data.pointee.ifi_obytes = sent
            data.pointee.ifi_ibytes = received
            record.pointee.ifa_addr = address
            record.pointee.ifa_data = UnsafeMutableRawPointer(data)
        }

        deinit {
            record.deinitialize(count: 1)
            record.deallocate()
            address.deinitialize(count: 1)
            address.deallocate()
            data.deinitialize(count: 1)
            data.deallocate()
        }
    }
}
