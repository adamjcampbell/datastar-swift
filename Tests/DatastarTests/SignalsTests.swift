import Foundation
import Testing
@testable import Datastar

@Suite("DatastarSignals decoding")
struct SignalsTests {
    struct MySignals: Decodable, Equatable {
        let count: Int
        let label: String
    }

    @Test("Body JSON decodes into the target type")
    func fromBody() throws {
        let body = Data(#"{"count":7,"label":"hi"}"#.utf8)
        let signals = try DatastarSignals.decode(MySignals.self, fromBody: body)
        #expect(signals == MySignals(count: 7, label: "hi"))
    }

    @Test("Query-value JSON decodes into the target type")
    func fromQuery() throws {
        let value = #"{"count":3,"label":"q"}"#
        let signals = try DatastarSignals.decode(MySignals.self, fromQueryValue: value)
        #expect(signals == MySignals(count: 3, label: "q"))
    }

    @Test("Malformed JSON throws DecodingError")
    func malformed() {
        #expect(throws: DecodingError.self) {
            _ = try DatastarSignals.decode(
                MySignals.self,
                fromBody: Data("not-json".utf8)
            )
        }
    }
}
