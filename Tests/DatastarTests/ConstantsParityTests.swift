import Foundation
import Testing
@testable import Datastar

/// Load the canonical SDK config JSON and assert every value present in the
/// spec is reflected in the generated Swift constants. Fails if the committed
/// `Generated/Constants.swift` has drifted from `sdk/datastar-sdk-config-v1.json`.
@Suite("Constants ↔ canonical JSON parity")
struct ConstantsParityTests {
    struct Config: Decodable {
        let datastarKey: String
        let defaults: Defaults
        let datalineLiterals: [String]
        let enums: Enums

        struct Defaults: Decodable {
            let booleans: Booleans
            let durations: Durations

            struct Booleans: Decodable {
                let elementsUseViewTransitions: Bool
                let patchSignalsOnlyIfMissing: Bool
            }
            struct Durations: Decodable {
                let sseRetryDuration: Int
            }
        }

        struct Enums: Decodable {
            let ElementPatchMode: EnumDef
            let EventType: EnumDef
            let Namespace: EnumDef
        }

        struct EnumDef: Decodable {
            let `default`: String?
            let values: [EnumValue]
        }

        struct EnumValue: Decodable {
            let name: String?
            let value: String
        }
    }

    static func loadConfig() throws -> Config {
        guard let url = Bundle.module.url(
            forResource: "datastar-sdk-config-v1",
            withExtension: "json"
        ) else {
            Issue.record("datastar-sdk-config-v1.json missing from test resources")
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    @Test("ElementPatchMode cases and default match the spec")
    func elementPatchModeParity() throws {
        let config = try Self.loadConfig()
        let expected = Set(config.enums.ElementPatchMode.values.map(\.value))
        let actual = Set(ElementPatchMode.allCases.map(\.rawValue))
        #expect(expected == actual, "ElementPatchMode cases drifted from spec")
        #expect(ElementPatchMode.default.rawValue == config.enums.ElementPatchMode.default)
    }

    @Test("Namespace cases and default match the spec")
    func namespaceParity() throws {
        let config = try Self.loadConfig()
        let expected = Set(config.enums.Namespace.values.map(\.value))
        let actual = Set(Namespace.allCases.map(\.rawValue))
        #expect(expected == actual, "Namespace cases drifted from spec")
        #expect(Namespace.default.rawValue == config.enums.Namespace.default)
    }

    @Test("EventType raw values match the spec")
    func eventTypeParity() throws {
        let config = try Self.loadConfig()
        let expected = Set(config.enums.EventType.values.map(\.value))
        let actual = Set(DatastarEventType.allCases.map(\.rawValue))
        #expect(expected == actual, "DatastarEventType cases drifted from spec")
    }

    @Test("Defaults match the spec")
    func defaultsParity() throws {
        let config = try Self.loadConfig()
        #expect(
            DatastarDefaults.sseRetryDuration == .milliseconds(config.defaults.durations.sseRetryDuration)
        )
        #expect(
            DatastarDefaults.elementsUseViewTransitions == config.defaults.booleans.elementsUseViewTransitions
        )
        #expect(
            DatastarDefaults.patchSignalsOnlyIfMissing == config.defaults.booleans.patchSignalsOnlyIfMissing
        )
        #expect(DatastarDefaults.datastarKey == config.datastarKey)
    }
}
