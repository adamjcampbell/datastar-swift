import Testing
@testable import Datastar

@Suite("ServerSentEventGenerator.onCancel")
struct OnCancelTests {
    @Test("Fires when the consumer task is cancelled")
    func firesOnConsumerCancellation() async {
        await confirmation("onCancel handler fires", expectedCount: 1) { confirm in
            let sse = ServerSentEventGenerator()
            sse.onCancel { confirm() }

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in sse.body {
                        // Drain forever — will be cancelled by the group.
                    }
                }
                // Let the consumer actually start awaiting before we cancel.
                try? await Task.sleep(for: .milliseconds(10))
                group.cancelAll()
            }
        }
    }

    @Test("Does NOT fire when the producer calls finish()")
    func doesNotFireOnOrderlyFinish() async {
        await confirmation("onCancel must not fire on orderly finish", expectedCount: 0) { confirm in
            let sse = ServerSentEventGenerator()
            sse.onCancel { confirm() }

            let consumer = Task {
                for await _ in sse.body {}
            }
            sse.finish()
            await consumer.value
            // Give the termination callback a tick in case it's scheduled asynchronously.
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
