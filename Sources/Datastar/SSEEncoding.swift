import Foundation

/// A Server-Sent Events frame, ready to be encoded to bytes.
///
/// Matches the Datastar wire format: `event:` line, optional `id:` line,
/// optional `retry:` line, one or more `data:` lines, terminating blank line.
/// Line endings are `\n` to match the reference Go and TypeScript SDKs.
public struct SSEEvent {
    public var name: String
    public var id: String?
    public var retry: Duration?
    public var data: [String]

    public init(name: String, id: String? = nil, retry: Duration? = nil, data: [String]) {
        self.name = name
        self.id = id
        self.retry = retry
        self.data = data
    }
}

public enum SSEEncoding {
    /// Encode an event to its on-the-wire byte representation.
    public static func encode(_ event: SSEEvent) -> [UInt8] {
        var out: [UInt8] = []
        append(&out, "event: ")
        append(&out, event.name)
        out.append(0x0A) // \n

        if let id = event.id, !id.isEmpty {
            append(&out, "id: ")
            append(&out, id)
            out.append(0x0A)
        }

        if let retry = event.retry {
            append(&out, "retry: ")
            append(&out, String(retry.milliseconds))
            out.append(0x0A)
        }

        for line in event.data {
            append(&out, "data: ")
            append(&out, line)
            out.append(0x0A)
        }

        out.append(0x0A) // terminating blank line
        return out
    }

    @inline(__always)
    static func append(_ buffer: inout [UInt8], _ string: String) {
        buffer.append(contentsOf: string.utf8)
    }
}

extension Duration {
    /// Total milliseconds, rounded toward zero. Used for the SSE `retry:` line.
    fileprivate var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    }
}
