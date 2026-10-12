import Foundation

/// A WAV file whose writer never closed it (crash, force quit, power loss) has the audio but wrong sizes in its header,
/// so nothing will open it. This rewrites the RIFF and data chunk sizes to match what is actually on disk.
enum WAVRepair {
    /// Returns true when the header had to be fixed.
    @discardableResult
    static func fixHeader(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forUpdating: url) else { return false }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd(), size > 44 else { return false }
        try? h.seek(toOffset: 0)
        guard let head = try? h.read(upToCount: 4096), head.count >= 12,
              String(decoding: head[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: head[8..<12], as: UTF8.self) == "WAVE" else { return false }

        func u32(_ o: Int) -> UInt32 { head[o..<o + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
        func le(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

        // walk the chunks to the "data" chunk
        var o = 12
        while o + 8 <= head.count {
            let id = String(decoding: head[o..<o + 4], as: UTF8.self)
            let len = Int(u32(o + 4))
            if id == "data" {
                let actual = UInt32(clamping: Int(size) - (o + 8))
                guard u32(o + 4) != actual || u32(4) != UInt32(clamping: Int(size) - 8) else { return false }   // already fine
                try? h.seek(toOffset: 4)
                h.write(le(UInt32(clamping: Int(size) - 8)))
                try? h.seek(toOffset: UInt64(o + 4))
                h.write(le(actual))
                return true
            }
            o += 8 + len + (len & 1)
        }
        return false
    }
}
