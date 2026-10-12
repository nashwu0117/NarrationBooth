import SwiftUI

/// How much is recorded per take.
enum TakeUnit: String, CaseIterable, Identifiable {
    case sentence   // one line of the script per take (stop after each sentence)
    case block      // one VO_ block per take
    case script     // the whole script in one continuous take; Space moves to the next line
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sentence: return T("一句一錄", "One sentence per take")
        case .block: return T("一段一錄", "One block per take")
        case .script: return T("整份一次錄", "Whole script in one take")
        }
    }

    var detail: String {
        switch self {
        case .sentence:
            return T("唸完一句按空白鍵停，聽一下沒問題再按空白鍵錄下一句。唸錯只要重錄那一句（點稿子上的任一句可以直接跳過去）。",
                     "Press Space after each sentence, check it, then Space again records the next one. A slip only costs that sentence (click any line to jump to it).")
        case .block:
            return T("每個 VO_ 段落錄一次，按空白鍵停止並跳到下一段。",
                     "Record each VO_ block in one go; Space stops and moves to the next block.")
        case .script:
            return T("按一次開始，之後每唸完一句按空白鍵換下一句，錄音不中斷；最後一句再按一次就結束（Esc 也可以停）。",
                     "Press Space to start, then Space after each sentence to move on without stopping; after the last one Space ends the take (Esc stops any time).")
        }
    }
}

/// User settings (UserDefaults), shared by the Settings window and the session.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var unit: TakeUnit { didSet { d.set(unit.rawValue, forKey: "takeUnit") } }
    @Published var autoCombine: Bool { didSet { d.set(autoCombine, forKey: "autoCombine") } }
    @Published var reviewTakes: Bool { didSet { d.set(reviewTakes, forKey: "reviewTakes") } }
    @Published var paceGuide: Bool { didSet { d.set(paceGuide, forKey: "paceGuide") } }
    /// Pace per language, in syllables per second of speech (see PaceLanguage for the defaults).
    @Published var paceRates: [String: Double] { didSet { d.set(paceRates, forKey: "paceRates") } }
    /// Language of the open script (set by the session; picks which pace the slider shows).
    @Published var paceLanguage: PaceLanguage = .zh

    func rate(_ l: PaceLanguage) -> Double { paceRates[l.rawValue] ?? l.defaultRate }
    func setRate(_ r: Double, _ l: PaceLanguage) {
        paceRates[l.rawValue] = (min(l.range.upperBound, max(l.range.lowerBound, r)) * 100).rounded() / 100
    }
    var currentRate: Double {
        get { rate(paceLanguage) }
        set { setRate(newValue, paceLanguage) }
    }
    @Published var autoPlay: Bool { didSet { d.set(autoPlay, forKey: "autoPlay") } }
    @Published var trimSilence: Bool { didSet { d.set(trimSilence, forKey: "trimSilence") } }
    @Published var sentenceGap: Double { didSet { d.set(sentenceGap, forKey: "sentenceGap") } }
    @Published var blockGap: Double { didSet { d.set(blockGap, forKey: "blockGap") } }

    private init() {
        unit = TakeUnit(rawValue: d.string(forKey: "takeUnit") ?? "") ?? .sentence
        autoCombine = d.object(forKey: "autoCombine") as? Bool ?? true
        reviewTakes = d.object(forKey: "reviewTakes") as? Bool ?? true
        paceGuide = d.object(forKey: "paceGuide") as? Bool ?? true
        paceRates = d.dictionary(forKey: "paceRates") as? [String: Double] ?? [:]
        autoPlay = d.object(forKey: "autoPlay") as? Bool ?? false
        trimSilence = d.object(forKey: "trimSilence") as? Bool ?? true
        sentenceGap = d.object(forKey: "sentenceGap") as? Double ?? 0.35
        blockGap = d.object(forKey: "blockGap") as? Double ?? 0.8
    }
}

struct SettingsView: View {
    @ObservedObject var p = Prefs.shared

    var body: some View {
        Form {
            Section(T("錄音方式", "Recording")) {
                Picker(T("每次錄", "Each take is"), selection: $p.unit) {
                    ForEach(TakeUnit.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(p.unit.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle(T("每錄完一次先停下來讓我聽（P 播放、R 重錄、空白鍵下一句）",
                         "Stop after each take so I can check it (P plays, R re-records, Space goes on)"), isOn: $p.reviewTakes)
                Toggle(T("錄完自動播放一次", "Play each take back automatically"), isOn: $p.autoPlay)
                    .disabled(!p.reviewTakes)
            }
            Section(T("步調提示", "Pacing guide")) {
                Toggle(T("錄音時，字會照節奏從灰色變白色", "While recording, the line fills from grey to white at a steady pace"), isOn: $p.paceGuide)
                LabeledContent(T("速度（%@稿）", "Pace (%@ script)", p.paceLanguage.name)) {
                    Slider(value: $p.currentRate, in: p.paceLanguage.range, step: p.paceLanguage == .en ? 0.05 : 0.1) { Text("") }
                        .frame(width: 160)
                    Text(p.paceLanguage.label(p.currentRate)).monospacedDigit().frame(width: 130, alignment: .leading)
                    Button(T("預設", "Default")) { p.paceRates[p.paceLanguage.rawValue] = nil }
                        .disabled(p.paceRates[p.paceLanguage.rawValue] == nil)
                }
                .disabled(!p.paceGuide)
                Text(T("白色追到哪，就唸到哪，不要超過它。逗號、句號和換氣記號「／」會停一下。錄音時也可以按 [ 和 ] 調慢、調快。打開稿子時會自動判斷語言，每種語言各自記住速度。預設值：中文每秒 4.3 字、英文每分鐘 150 字、日文和韓文每分鐘約 300 字，都是一般影片旁白清楚好懂的速度。",
                       "Read where the white is, and don't get ahead of it. Commas, full stops and breath marks (／) hold for a moment. Press [ and ] while recording to go slower or faster. The script's language is detected when you open it, and each language keeps its own pace. Defaults: English 150 wpm, Chinese 4.3 characters/s, Japanese and Korean ≈ 300 per minute, the usual clear narration pace for videos."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(T("合併", "Combining")) {
                Toggle(T("全部錄完後自動合併", "Combine automatically when every take is done"), isOn: $p.autoCombine)
                Toggle(T("修掉每一次錄音前後多餘的空白", "Trim the silence before and after each take"), isOn: $p.trimSilence)
                LabeledContent(T("句子之間的間隔", "Gap between sentences")) {
                    Slider(value: $p.sentenceGap, in: 0.1...1.0, step: 0.05) { Text("") }.frame(width: 180)
                    Text(String(format: "%.2f s", p.sentenceGap)).monospacedDigit().frame(width: 52)
                }
                LabeledContent(T("段落之間的間隔", "Gap between blocks")) {
                    Slider(value: $p.blockGap, in: 0.2...2.0, step: 0.1) { Text("") }.frame(width: 180)
                    Text(String(format: "%.1f s", p.blockGap)).monospacedDigit().frame(width: 52)
                }
                Text(T("合併後會產生：每個段落一個 VO_<名稱>.wav，加上整份的 <稿子名>_full.wav（鏡頭模式也會合併影片）。間隔用的是你錄到的真實環境音，聲音和影片用同樣的剪點。",
                       "Combining writes VO_<name>.wav for every block plus <script>_full.wav for the whole script (and the matching videos in camera mode). Gaps use the room tone you recorded, and audio and video share the same cuts."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 760)
        .padding(.vertical, 8)
    }
}
