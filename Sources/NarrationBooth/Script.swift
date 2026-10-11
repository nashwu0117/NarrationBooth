import Foundation

/// One recording unit: a VO block (`VO_01a`) with its sentences. Each block is saved as `VO_<key>.wav`.
struct ScriptBlock: Identifiable, Hashable {
    let id: String          // file key, e.g. "01a"
    let section: String     // heading above it ("01 Dunedin → Tunnel Beach"), may be empty
    let lines: [String]     // one sentence per line; 「／」 marks a breath
}

/// Reads the recording sheets Claude writes (EPn_錄音專用稿.md / .txt) and plain text files.
/// - `**VO_xxx**` or `VO_xxx` on its own line starts a block; lines after it (until the next block) are its sentences.
/// - `# …` / `### …` lines are section headings.
/// - Anything before the first `VO_` marker (the instructions) is skipped.
/// - A file with no `VO_` markers at all: every paragraph (blank-line separated) becomes a block 001, 002, …
enum ScriptParser {
    static func parse(_ text: String) -> [ScriptBlock] {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let marker = try! NSRegularExpression(pattern: #"^\**\s*VO_([A-Za-z0-9_\-]+)\s*\**\s*$"#)
        func key(of line: String) -> String? {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard let m = marker.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }
        func clean(_ line: String) -> String {
            line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        }

        if raw.contains(where: { key(of: $0) != nil }) {
            var blocks: [ScriptBlock] = []
            var section = "", curKey: String?, curLines: [String] = []
            func flush() {
                if let k = curKey, !curLines.isEmpty { blocks.append(ScriptBlock(id: k, section: section, lines: curLines)) }
                curKey = nil; curLines = []
            }
            for line in raw {
                if let k = key(of: line) { flush(); curKey = k; continue }
                let s = clean(line)
                if s.hasPrefix("#") {
                    let title = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    // a new episode / section heading ends the current block
                    if curKey != nil { flush() }
                    if !title.isEmpty, !title.hasPrefix("EP") || title.count > 4 { section = title }
                    continue
                }
                if s == "---" || s.isEmpty || s.hasPrefix("|") || s.hasPrefix(">") { continue }
                if curKey != nil { curLines.append(s) }
            }
            flush()
            return blocks
        }

        // plain text: paragraphs
        var blocks: [ScriptBlock] = [], para: [String] = []
        func flushPara() {
            if !para.isEmpty { blocks.append(ScriptBlock(id: String(format: "%03d", blocks.count + 1), section: "", lines: para)) }
            para = []
        }
        for line in raw {
            let s = clean(line)
            if s.isEmpty { flushPara() } else if !s.hasPrefix("#") { para.append(s) }
        }
        flushPara()
        return blocks
    }
}
