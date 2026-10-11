import AVFoundation

/// One stretch of a take to keep, in seconds from the start of the take. The WAV and the MOV of a take start together,
/// so the same range cuts both.
struct Piece {
    let wav: URL
    let mov: URL?
    let start: Double
    let end: Double
}

/// Joins takes into finished files: VO_<block>.wav / .mov and <script>_full.wav / .mov.
/// Gaps between pieces are real room tone kept around the speech (each side keeps half the gap), never inserted silence,
/// so the audio and the video can share exactly the same cuts and stay in sync.
enum Combiner {
    static let rate = 48_000.0

    // MARK: audio

    static func read(_ url: URL) throws -> [Float] {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return [] }
        try f.read(into: buf)
        guard let ch = buf.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
    }

    static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false,
                                       AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        try? FileManager.default.removeItem(at: url)
        let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        var i = 0
        while i < samples.count {
            let n = min(65_536, samples.count - i)
            let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
            b.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress! + i, count: n) }
            try f.write(from: b)
            i += n
        }
    }

    /// First and last moment of speech inside [from, to] seconds: 20 ms windows louder than `threshold` dBFS
    /// (relative to the take's own peak so quiet mics work too).
    static func speech(_ s: [Float], from: Double, to: Double) -> (Double, Double)? {
        let a = max(0, Int(from * rate)), b = min(s.count, Int(to * rate))
        guard b - a > 960 else { return nil }
        let win = 960
        var peak: Float = 0
        for i in a..<b { peak = max(peak, abs(s[i])) }
        guard peak > 0.002 else { return nil }
        let gate = max(peak * 0.06, 0.003)   // ≈ −24 dB under the take's peak, never below −50 dBFS
        var first: Int?, last: Int?
        var i = a
        while i + win <= b {
            var sum: Float = 0
            for j in i..<(i + win) { sum += s[j] * s[j] }
            if sqrt(sum / Float(win)) > gate * 0.5 {
                if first == nil { first = i }
                last = i + win
            }
            i += win
        }
        guard let f = first, let l = last else { return nil }
        return (Double(f) / rate, Double(l) / rate)
    }

    /// Range to keep from a take window: the speech plus `lead` / `tail` seconds of what was recorded around it.
    static func keep(_ s: [Float], from: Double, to: Double, lead: Double, tail: Double, trim: Bool) -> (Double, Double) {
        let total = Double(s.count) / rate
        let lo = max(0, from), hi = min(total, to)
        guard trim, let (a, b) = speech(s, from: lo, to: hi) else { return (lo, hi) }
        return (max(lo, a - lead), min(hi, b + tail))
    }

    /// Writes the pieces back to back. Returns the duration.
    @discardableResult
    static func joinAudio(_ pieces: [Piece], cache: inout [URL: [Float]], to url: URL) throws -> Double {
        var out: [Float] = []
        for p in pieces {
            if cache[p.wav] == nil { cache[p.wav] = try read(p.wav) }
            let s = cache[p.wav]!
            let a = max(0, Int(p.start * rate)), b = min(s.count, Int(p.end * rate))
            guard b > a else { continue }
            var seg = Array(s[a..<b])
            let f = min(240, seg.count / 2)          // 5 ms fades: no clicks at the cuts
            for k in 0..<f {
                seg[k] *= Float(k) / Float(f)
                seg[seg.count - 1 - k] *= Float(k) / Float(f)
            }
            out += seg
        }
        try write(out, to: url)
        return Double(out.count) / rate
    }

    // MARK: video

    /// Cuts the same ranges out of the camera takes and lays the joined WAV under them as the sound.
    static func joinVideo(_ pieces: [Piece], audio: URL, to url: URL) async throws {
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        var cursor = CMTime.zero
        for p in pieces {
            guard let mov = p.mov else { continue }
            let asset = AVURLAsset(url: mov)
            guard let src = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur = try await asset.load(.duration)
            let start = CMTime(seconds: p.start, preferredTimescale: 600)
            let end = CMTimeMinimum(CMTime(seconds: p.end, preferredTimescale: 600), dur)
            guard end > start else { continue }
            let range = CMTimeRange(start: start, end: end)
            try vTrack.insertTimeRange(range, of: src, at: cursor)
            vTrack.preferredTransform = try await src.load(.preferredTransform)
            cursor = cursor + range.duration
        }
        let wav = AVURLAsset(url: audio)
        if let a = try await wav.loadTracks(withMediaType: .audio).first {
            let d = CMTimeMinimum(try await wav.load(.duration), cursor)
            try aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: a, at: .zero)
        }
        try? FileManager.default.removeItem(at: url)
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHEVCHighestQuality] {
            guard let ex = AVAssetExportSession(asset: comp, presetName: preset) else { continue }
            ex.outputURL = url
            ex.outputFileType = .mov
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in ex.exportAsynchronously { c.resume() } }
            if ex.status == .completed { return }
            try? FileManager.default.removeItem(at: url)
        }
        throw NSError(domain: "NarrationBooth", code: 1, userInfo: [NSLocalizedDescriptionKey: "video export failed"])
    }
}
