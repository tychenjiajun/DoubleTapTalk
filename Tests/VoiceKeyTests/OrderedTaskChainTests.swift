import XCTest
@testable import DoubleTapTalk

/// Tests for the ordered execution chain used to serialize relay-segment
/// delivery and per-segment cloud ASR + refinement + injection.
final class OrderedTaskChainTests: XCTestCase {

    func testOperationsRunInEnqueueOrder() async {
        let chain = OrderedTaskChain()
        let recorder = OrderRecorder()

        chain.enqueue {
            try? await Task.sleep(nanoseconds: 30_000_000)
            await recorder.append(1)
        }
        chain.enqueue {
            await recorder.append(2)
        }
        chain.enqueue {
            try? await Task.sleep(nanoseconds: 10_000_000)
            await recorder.append(3)
        }

        await chain.drain()
        let visited = await recorder.values
        XCTAssertEqual(visited, [1, 2, 3], "a slow first operation must not let later ones overtake it")
    }

    func testDrainWaitsForWorkEnqueuedWhileWaiting() async {
        let chain = OrderedTaskChain()
        let recorder = OrderRecorder()

        chain.enqueue {
            try? await Task.sleep(nanoseconds: 20_000_000)
            await recorder.append(1)
            // Enqueued from inside a running operation: drain() must still see it.
            chain.enqueue { await recorder.append(2) }
        }

        await chain.drain()
        let visited = await recorder.values
        XCTAssertEqual(visited, [1, 2])
    }

    func testManyAppendsFromEnqueuesStayOrdered() async {
        let chain = OrderedTaskChain()
        let recorder = OrderRecorder()

        for value in 0..<50 {
            chain.enqueue { await recorder.append(value) }
        }

        await chain.drain()
        let visited = await recorder.values
        XCTAssertEqual(visited, Array(0..<50))
    }

    func testConcurrentEnqueuesAllRun() async {
        let chain = OrderedTaskChain()
        let recorder = OrderRecorder()

        await withTaskGroup(of: Void.self) { group in
            for value in 0..<40 {
                group.addTask {
                    chain.enqueue {
                        try? await Task.sleep(nanoseconds: UInt64(value % 3) * 1_000_000)
                        await recorder.append(value)
                    }
                }
            }
        }

        await chain.drain()
        let visited = await recorder.values
        XCTAssertEqual(visited.count, 40, "no enqueued operation may be lost")
        XCTAssertEqual(Set(visited).count, 40, "every operation must run exactly once")
    }

    func testDrainReturnsImmediatelyWhenEmpty() async {
        let chain = OrderedTaskChain()
        await chain.drain()   // must not hang or crash
        XCTAssertNil(chain.lastOperation)
    }
}

/// Thread-safe ordered sink for chain tests.
private actor OrderRecorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}