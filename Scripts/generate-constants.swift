#!/usr/bin/env swift
// Regenerates Sources/Datastar/Generated/Constants.swift from
// sdk/datastar-sdk-config-v1.json, and mirrors the JSON into the test
// resources so `ConstantsParityTests` can load it via Bundle.module.
//
// Run from the package root:
//   swift Scripts/generate-constants.swift

import Foundation

// MARK: - Config model

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
        let description: String
        let `default`: String?
        let values: [EnumValue]
    }

    struct EnumValue: Decodable {
        let name: String?
        let value: String
        let description: String
    }
}

// MARK: - Helpers

func camelCase(_ pascal: String) -> String {
    guard let first = pascal.first else { return pascal }
    return first.lowercased() + pascal.dropFirst()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Locate package root

let cwd = FileManager.default.currentDirectoryPath
let configPath = "\(cwd)/sdk/datastar-sdk-config-v1.json"
guard FileManager.default.fileExists(atPath: configPath) else {
    fail("\(configPath) not found. Run this script from the package root.")
}

let jsonData: Data
do {
    jsonData = try Data(contentsOf: URL(fileURLWithPath: configPath))
} catch {
    fail("failed to read \(configPath): \(error)")
}

let config: Config
do {
    config = try JSONDecoder().decode(Config.self, from: jsonData)
} catch {
    fail("failed to parse \(configPath): \(error)")
}

// MARK: - Emit Swift

var out = ""
out += "// DO NOT EDIT — generated from sdk/datastar-sdk-config-v1.json.\n"
out += "// Regenerate with: swift Scripts/generate-constants.swift\n"
out += "\n"
out += "import Foundation\n"
out += "\n"

func emitStringEnum(
    name: String,
    def: Config.EnumDef,
    conformances: [String] = ["String", "Sendable", "CaseIterable", "Codable"]
) {
    out += "/// \(def.description)\n"
    out += "public enum \(name): \(conformances.joined(separator: ", ")) {\n"
    for v in def.values {
        out += "    /// \(v.description)\n"
        out += "    case \(v.value)\n"
    }
    if let defaultValue = def.`default` {
        out += "\n"
        out += "    public static let `default`: \(name) = .\(defaultValue)\n"
    }
    out += "}\n"
    out += "\n"
}

emitStringEnum(name: "ElementPatchMode", def: config.enums.ElementPatchMode)
emitStringEnum(name: "Namespace", def: config.enums.Namespace)

// EventType uses `name` (PascalCase) as the Swift case and `value` as the raw value.
out += "/// SSE event types emitted by Datastar servers.\n"
out += "public enum DatastarEventType: String, Sendable, CaseIterable {\n"
for v in config.enums.EventType.values {
    guard let name = v.name else { fail("EventType value missing `name`: \(v.value)") }
    out += "    /// \(v.description)\n"
    out += "    case \(camelCase(name)) = \"\(v.value)\"\n"
}
out += "}\n"
out += "\n"

// Defaults
out += "/// Protocol-level defaults shared across every Datastar SDK.\n"
out += "public enum DatastarDefaults {\n"
out += "    /// Default SSE retry duration (\(config.defaults.durations.sseRetryDuration) ms).\n"
out += "    public static let sseRetryDuration: Duration = .milliseconds(\(config.defaults.durations.sseRetryDuration))\n"
out += "    /// Whether element patches use the View Transitions API by default.\n"
out += "    public static let elementsUseViewTransitions: Bool = \(config.defaults.booleans.elementsUseViewTransitions)\n"
out += "    /// Whether signal patches only set missing signals by default.\n"
out += "    public static let patchSignalsOnlyIfMissing: Bool = \(config.defaults.booleans.patchSignalsOnlyIfMissing)\n"
out += "    /// Query parameter name and form key used for signals.\n"
out += "    public static let datastarKey: String = \"\(config.datastarKey)\"\n"
out += "}\n"
out += "\n"

// Dataline literals (internal)
out += "/// Dataline literal prefixes used on the SSE wire (each includes the trailing space).\n"
out += "enum DatalineLiteral {\n"
for literal in config.datalineLiterals {
    out += "    static let \(literal) = \"\(literal) \"\n"
}
out += "}\n"

// MARK: - Write outputs

let constantsPath = "\(cwd)/Sources/Datastar/Generated/Constants.swift"
let resourcesPath = "\(cwd)/Tests/DatastarTests/Resources/datastar-sdk-config-v1.json"

do {
    try FileManager.default.createDirectory(
        atPath: (constantsPath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        atPath: (resourcesPath as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true
    )
    try Data(out.utf8).write(to: URL(fileURLWithPath: constantsPath))
    try jsonData.write(to: URL(fileURLWithPath: resourcesPath))
} catch {
    fail("failed to write outputs: \(error)")
}

print("wrote \(constantsPath)")
print("wrote \(resourcesPath)")
