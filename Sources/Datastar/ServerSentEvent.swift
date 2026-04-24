import Foundation

/// A Server-Sent Events frame, ready to be encoded to bytes.
///
/// Matches the Datastar wire format: `event:` line, optional `id:` line,
/// optional `retry:` line, one or more `data:` lines, terminating blank line.
/// Line endings are `\n` to match the reference Go and TypeScript SDKs.
///
/// Internal — the only public emission path is `ServerSentEventGenerator`.
struct ServerSentEvent {
    var name: String
    var id: String?
    var retry: Duration?
    var data: [String]

    init(name: String, id: String? = nil, retry: Duration? = nil, data: [String]) {
        self.name = name
        self.id = id
        self.retry = retry
        self.data = data
    }

    /// Encode to the on-the-wire byte representation.
    func encoded() -> [UInt8] {
        var out: [UInt8] = []
        Self.append(&out, "event: ")
        Self.append(&out, name)
        out.append(0x0A) // \n

        if let id, !id.isEmpty {
            Self.append(&out, "id: ")
            Self.append(&out, id)
            out.append(0x0A)
        }

        if let retry {
            Self.append(&out, "retry: ")
            Self.append(&out, String(retry.milliseconds))
            out.append(0x0A)
        }

        for line in data {
            Self.append(&out, "data: ")
            Self.append(&out, line)
            out.append(0x0A)
        }

        out.append(0x0A) // terminating blank line
        return out
    }

    @inline(__always)
    private static func append(_ buffer: inout [UInt8], _ string: String) {
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
