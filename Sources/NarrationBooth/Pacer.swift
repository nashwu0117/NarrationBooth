import SwiftUI

/// Karaoke-style pacing guide: while a take records, the line fills from grey to white at a steady speaking pace, so
/// you can see where you should be and don't rush. The pace is in syllables per second: one Chinese / Japanese / Korean
/// character or digit is one syllable, an English word counts its vowel groups. Punctuation and breath marks hold the
/// fill for a moment, like a speaker would.
struct PaceTimeline {
    struct Glyph {
        let text: String
        let start: Double
        let end: Double
        let breath: Bool
    }

    static let commaPause = 0.25     // ，、：；,
    static let stopPause = 0.40      // 。！？…
    static let breathPause = 0.30    // ／
    static let linePause = 0.45      // between the lines of a block
    static let leadIn = 0.5          // time to draw breath after pressing Space

    let glyphs: [Glyph]
    /// When the last syllable should be done (trailing pauses not counted).
    let duration: Double

    init(line: String, rate: Double, from t0: Double = 0) {
        let unit = 1 / max(rate, 0.5)
        var out: [Glyph] = []
        var t = t0, spokenEnd = t0
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "／" {
                out.append(Glyph(text: " ／ ", start: t, end: t, breath: true))
                t += Self.breathPause
                i += 1
            } else if c.isWhitespace {
                // a space next to a breath mark is already part of " ／ "
                let nextIsBreath = i + 1 < chars.count && chars[i + 1] == "／"
                let prevIsBreath = i > 0 && chars[i - 1] == "／"
                if !nextIsBreath && !prevIsBreath { out.append(Glyph(text: " ", start: t, end: t, breath: false)) }
                i += 1
            } else if c.isASCII && c.isLetter {
                // an English word: its letters share the word's syllables
                var j = i
                while j < chars.count, chars[j].isASCII, chars[j].isLetter || chars[j] == "'" { j += 1 }
                let word = String(chars[i..<j])
                let d = Double(Self.syllables(word)) * unit
                for (k, ch) in word.enumerated() {
                    out.append(Glyph(text: String(ch), start: t + d * Double(k) / Double(word.count),
                                     end: t + d * Double(k + 1) / Double(word.count), breath: false))
                }
                t += d
                spokenEnd = t
                i = j
            } else if "，、：；,;:".contains(c) {
                out.append(Glyph(text: String(c), start: t, end: t, breath: false))
                t += Self.commaPause
                i += 1
            } else if "。！？!?….".contains(c) {
                out.append(Glyph(text: String(c), start: t, end: t, breath: false))
                t += Self.stopPause
                i += 1
            } else if c.isPunctuation || c.isSymbol {
                out.append(Glyph(text: String(c), start: t, end: t, breath: false))   // 「」（）— etc. take no time
                i += 1
            } else {
                out.append(Glyph(text: String(c), start: t, end: t + unit, breath: false))
                t += unit
                spokenEnd = t
                i += 1
            }
        }
        glyphs = out
        duration = spokenEnd
    }

    /// Rough English syllable count: groups of vowels, a silent final "e" dropped, at least one.
    static func syllables(_ word: String) -> Int {
        let w = word.lowercased()
        var n = 0, inVowel = false
        for ch in w {
            let v = "aeiouy".contains(ch)
            if v && !inVowel { n += 1 }
            inVowel = v
        }
        if w.hasSuffix("e") && !w.hasSuffix("le") && n > 1 { n -= 1 }
        return max(1, n)
    }

    /// The line as Text: grey ahead of the guide, white behind it, the current syllable in between.
    func text(at t: Double) -> Text {
        var out = Text("")
        for g in glyphs {
            if g.breath {
                out = out + Text(g.text).foregroundColor(Booth.amber)
                continue
            }
            let f = g.end > g.start ? min(1, max(0, (t - g.start) / (g.end - g.start))) : (t >= g.start ? 1 : 0)
            out = out + Text(g.text).foregroundColor(Color(white: 0.42 + 0.52 * f))
        }
        return out
    }
}

/// The timelines of the lines being recorded: one line (sentence mode, whole-script mode) or the lines of a block one
/// after another (block mode).
func paceTimelines(_ lines: [String], rate: Double) -> [PaceTimeline] {
    var t = 0.0
    return lines.map { line in
        let tl = PaceTimeline(line: line, rate: rate, from: t)
        t = tl.duration + PaceTimeline.linePause
        return tl
    }
}

/// How fast a take was read compared with the guide: 1.0 = on pace, 1.2 = 20 % faster.
func paceRatio(take url: URL, lines: [String], rate: Double) -> Double? {
    guard let s = try? Combiner.read(url), let (a, b) = Combiner.speech(s, from: 0, to: Double(s.count) / Combiner.rate),
          b - a > 0.5, let expected = paceTimelines(lines, rate: rate).last?.duration, expected > 0.5 else { return nil }
    return expected / (b - a)
}

/// Seconds since the guide started (negative during the lead-in), refreshed every frame while recording.
struct PacedLine: View {
    let timeline: PaceTimeline
    let start: Date?
    let size: CGFloat

    var body: some View {
        if let start {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                timeline.text(at: ctx.date.timeIntervalSince(start) - PaceTimeline.leadIn)
                    .font(.system(size: size, weight: .medium))
            }
        } else {
            timeline.text(at: -1).font(.system(size: size, weight: .medium))
        }
    }
}
