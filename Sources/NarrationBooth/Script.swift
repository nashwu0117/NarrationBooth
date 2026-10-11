import Foundation

/// One recording unit: a VO block (`VO_01a`) with its sentences. Each block is saved as `VO_<key>.wav`.
struct ScriptBlock: Identifiable, Hashable {
    let id: String          // file key, e.g. "01a"
    let section: String     // heading above it ("01 Dunedin → Tunnel Beach"), may be empty
    let lines: [String]     // one sentence per line; 「／」 marks a breath
}

/// Script format (full spec: docs/SCRIPT_FORMAT.md), for .txt and .md files:
/// - `VO_<name>` on its own line (bold `**VO_<name>**` is fine) starts a block; the lines under it are its sentences.
///   `<name>` = letters, digits, `_` or `-`; it becomes the file name VO_<name>.wav, so it must be unique.
/// - `# Title` names the script; `##` / `###` lines are section headings (shown in the list); `//` lines are notes.
/// - A breath mark is 「／」 or a slash with spaces around it (` / `).
/// - Anything before the first `VO_` line is ignored (instructions, notes).
/// - A file with no `VO_` lines at all: every paragraph (blank-line separated) becomes a block 001, 002, …
enum ScriptParser {
    /// Block names used more than once (they would overwrite each other's files).
    static func duplicates(_ blocks: [ScriptBlock]) -> [String] {
        Dictionary(grouping: blocks, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
    }

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
            line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: " / ", with: " ／ ")   // ASCII breath mark → 「／」
                .trimmingCharacters(in: .whitespaces)
        }
        func isNote(_ s: String) -> Bool { s.hasPrefix("//") }

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
                    // `# Title` names the whole script; `##` / `###` start a section shown in the block list
                    if curKey != nil { flush() }
                    let level = s.prefix { $0 == "#" }.count
                    let title = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    if level >= 2, !title.isEmpty { section = title }
                    continue
                }
                if s == "---" || s.isEmpty || s.hasPrefix("|") || s.hasPrefix(">") || isNote(s) { continue }
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
            if s.isEmpty { flushPara() } else if !s.hasPrefix("#") && !isNote(s) { para.append(s) }
        }
        flushPara()
        return blocks
    }
}
