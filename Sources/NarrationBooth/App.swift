import AppKit
import AVFoundation
import SwiftUI

@main
struct NarrationBoothApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup("NarrationBooth") {
            BoothView()
                .environmentObject(session)
                .environmentObject(session.rec)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    session.boot()
                    Updater.checkInBackgroundIfDue()
                }
                .onOpenURL { session.open($0) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(T("檢查更新…", "Check for Updates…")) { Task { await Updater.check(userInitiated: true) } }
            }
            CommandGroup(after: .saveItem) {
                Button(T("合併錄音", "Combine Takes")) { Task { await session.combine() } }.keyboardShortcut("j")
            }
            CommandGroup(replacing: .help) {
                Button(T("稿子格式說明", "Script Format Guide")) { NSWorkspace.shared.open(ScriptTemplate.guideURL) }
                Button(T("存一份稿子範本…", "Save Script Template…")) { session.saveTemplate() }
            }
            CommandMenu(T("語言", "Language")) {
                Button("繁體中文") { setLanguage("zh") }
                Button("English") { setLanguage("en") }
            }
            CommandGroup(replacing: .newItem) {
                Button(T("開啟稿子…", "Open Script…")) { session.openPanel() }.keyboardShortcut("o")
                Button(T("選擇存檔資料夾…", "Choose Output Folder…")) { session.chooseOutDir() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView() }
    }
}

/// Saves the choice and asks to relaunch (the UI language is read once at launch).
func setLanguage(_ code: String) {
    UserDefaults.standard.set(code, forKey: "uiLanguage")
    let a = NSAlert()
    a.messageText = code == "zh" ? "重新開啟後換成繁體中文" : "Relaunch to switch to English"
    a.runModal()
}

// MARK: - palette

enum Booth {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let line = Color.white.opacity(0.08)
    static let text = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let dim = Color.white.opacity(0.45)
    static let red = Color(red: 0.95, green: 0.27, blue: 0.24)
    static let green = Color(red: 0.36, green: 0.82, blue: 0.48)
    static let amber = Color(red: 0.98, green: 0.73, blue: 0.25)
}

// MARK: - main view

struct BoothView: View {
    @EnvironmentObject var s: Session
    @EnvironmentObject var rec: Recorder

    var body: some View {
        HStack(spacing: 0) {
            if !s.videoMode {
                BlockList().frame(width: 280)
                Rectangle().fill(Booth.line).frame(width: 1)
            }
            VStack(spacing: 0) {
                if s.videoMode {
                    // camera mode: the script comes first, right under the camera; the device bar goes below it
                    if s.blocks.isEmpty { EmptyState() } else { CameraPrompter() }
                    Rectangle().fill(Booth.line).frame(height: 1)
                    TopBar()
                } else {
                    TopBar()
                    Rectangle().fill(Booth.line).frame(height: 1)
                    if s.blocks.isEmpty { EmptyState() } else { Prompter() }
                }
                Rectangle().fill(Booth.line).frame(height: 1)
                MeterPanel()
                Controls()
            }
        }
        .background(Booth.bg)
        .foregroundStyle(Booth.text)
        .preferredColorScheme(.dark)
    }
}

/// Camera mode = teleprompter layout. The window goes full screen so its centre is the camera's centre; the current
/// block is a narrow, centred column at the very top, just under the lens, so reading looks like eye contact.
struct CameraPrompter: View {
    @EnvironmentObject var s: Session
    @EnvironmentObject var rec: Recorder
    /// horizontal shift that puts the text column under the screen's centre (= the built-in camera), even when the
    /// window isn't full screen or sits off-centre; 0 in full screen
    @State private var towardCamera: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                if let sh = s.shown {
                    let b = s.blocks[sh.block]
                    HStack(spacing: 8) {
                        Text("VO_\(b.id)").font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(rec.isRecording ? Booth.red : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        if rec.isRecording {
                            Text(String(format: T("● 錄影中  %.1f 秒", "● REC  %.1f s"), rec.takeSeconds))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Booth.red)
                        } else if s.unit != .script, s.shownTake != nil {
                            Text(T("已錄 ✓（空白鍵重錄）", "Recorded ✓ (Space to redo)")).font(.system(size: 12)).foregroundStyle(Booth.green)
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(b.lines.enumerated()), id: \.offset) { i, line in
                            let on = sh.line == nil || sh.line == i
                            breathText(line).font(.system(size: on ? 30 : 20, weight: .medium)).lineSpacing(6)
                                .opacity(on ? 1 : 0.32)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 620)
                }
                if let n = s.nextPreview {
                    Text(n).font(.system(size: 15)).foregroundStyle(Booth.dim).multilineTextAlignment(.center)
                        .lineLimit(2).frame(maxWidth: 620)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(x: towardCamera)

            CameraPreview(session: rec.session)
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(rec.isRecording ? Booth.red : Booth.line, lineWidth: 2))
                .padding(18)
        }
        .onAppear(perform: alignToCamera)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in alignToCamera() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in alignToCamera() }
        .overlay(alignment: .topLeading) {
            Text(T("看鏡頭：字在鏡頭正下方", "Look here: the text sits right under the camera"))
                .font(.system(size: 11)).foregroundStyle(Booth.dim).padding(10)
        }
    }
}

extension CameraPrompter {
    func alignToCamera() {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }), let screen = w.screen else { return }
        let shift = screen.frame.midX - w.frame.midX
        // keep the column inside the window
        let limit = max(0, w.frame.width / 2 - 340)
        towardCamera = max(-limit, min(limit, shift))
    }
}

extension URL {
    /// ~/Downloads/x instead of /Users/name/Downloads/x
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

/// 「／」 = breath mark, shown in amber
func breathText(_ line: String) -> Text {
    let parts = line.components(separatedBy: "／")
    var t = Text("")
    for (i, p) in parts.enumerated() {
        if i > 0 { t = t + Text(" ／ ").foregroundColor(Booth.amber) }
        t = t + Text(p.trimmingCharacters(in: .whitespaces))
    }
    return t
}

struct TopBar: View {
    @EnvironmentObject var s: Session
    @EnvironmentObject var rec: Recorder
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { s.openPanel() } label: { Label(T("開啟稿子", "Open Script"), systemImage: "doc.text") }
                    .buttonStyle(.borderedProminent).tint(Color.white.opacity(0.14))
                Text(s.scriptName.isEmpty ? T("還沒開啟稿子", "No script yet") : s.scriptName)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    Picker("", selection: $prefs.unit) {
                        ForEach(TakeUnit.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    SettingsLink { Text(T("更多設定…", "More Settings…")) }
                } label: {
                    Label(prefs.unit.title, systemImage: "rectangle.split.3x1")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(rec.isRecording)
                .help(T("每次錄一句、一段，或整份一次錄", "Record a sentence, a block, or the whole script per take"))
                Picker("", selection: Binding(get: { rec.mode }, set: { s.setMode($0) })) {
                    Label(T("只錄聲音", "Voice only"), systemImage: "waveform").tag(Recorder.Mode.audio)
                    Label(T("鏡頭＋聲音", "Camera + voice"), systemImage: "video").tag(Recorder.Mode.video)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                .disabled(rec.isRecording)
            }
            HStack(spacing: 12) {
                Image(systemName: "mic").foregroundStyle(Booth.dim)
                Picker("", selection: Binding(get: { s.micUID ?? "" }, set: { s.selectMic($0) })) {
                    ForEach(s.mics) { d in Text(d.name).tag(d.id) }
                }
                .labelsHidden().frame(width: 210).disabled(rec.isRecording)
                if s.canSetVolume {
                    Text(T("輸入音量", "Input level")).font(.system(size: 11)).foregroundStyle(Booth.dim)
                    Slider(value: Binding(get: { Double(s.inputVolume) }, set: { s.setVolume(Float($0)) }), in: 0...1)
                        .frame(width: 110)
                }
                if s.videoMode {
                    Image(systemName: "video").foregroundStyle(Booth.dim).padding(.leading, 6)
                    Picker("", selection: Binding(get: { s.cameraUID ?? "" }, set: { s.selectCamera($0) })) {
                        ForEach(s.cameras) { d in Text(d.name).tag(d.id) }
                    }
                    .labelsHidden().frame(width: 200).disabled(rec.isRecording)
                }
                Button { s.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(T("重新整理裝置清單", "Refresh devices"))
                Spacer()
                Button { s.chooseOutDir() } label: {
                    Label((s.outDir ?? s.outputBase).abbreviatedPath, systemImage: "folder")
                        .lineLimit(1).truncationMode(.head).frame(maxWidth: 280, alignment: .leading)
                }
                .help(T("錄音存在：", "Saving to: ") + (s.outDir ?? s.outputBase).abbreviatedPath + T("（點一下換位置）", " (click to change)"))
                .disabled(rec.isRecording)
                Text(formatLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(Booth.dim).lineLimit(1)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .padding(.top, 22)
        .background(Booth.panel)
    }

    var formatLabel: String {
        let audio = "WAV 48 kHz · 24-bit"
        return s.videoMode && !rec.videoLabel.isEmpty ? "\(rec.videoLabel) + \(audio)" : audio
    }
}

// MARK: - left list

struct BlockList: View {
    @EnvironmentObject var s: Session
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(prefs.unit.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Booth.dim)
                if !s.slots.isEmpty {
                    ProgressView(value: Double(s.doneCount), total: Double(s.slots.count)).tint(Booth.green)
                    Text(T("錄好 \(s.doneCount) / \(s.slots.count)", "Recorded \(s.doneCount) / \(s.slots.count)"))
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(s.blocks.enumerated()), id: \.element.id) { i, b in
                            if !b.section.isEmpty, i == 0 || s.blocks[i - 1].section != b.section {
                                Text(b.section).font(.system(size: 11, weight: .semibold)).foregroundStyle(Booth.dim)
                                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                            }
                            BlockRow(block: b, selected: s.shown?.block == i, progress: s.progress(ofBlock: i),
                                     clipped: s.anyClipped(inBlock: i))
                                .id(b.id)
                                .onTapGesture { s.select(block: i) }
                        }
                    }
                }
                .onChange(of: s.shown?.block) { _, i in
                    if let i, s.blocks.indices.contains(i) { withAnimation { proxy.scrollTo(s.blocks[i].id, anchor: .center) } }
                }
            }
            if s.outDir != nil {
                Button { s.revealFolder() } label: {
                    Label(T("打開錄音資料夾", "Show recordings"), systemImage: "folder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).padding(12)
            }
        }
        .background(Booth.panel)
    }
}

struct BlockRow: View {
    let block: ScriptBlock
    let selected: Bool
    let progress: (done: Int, total: Int)
    let clipped: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if progress.done == progress.total {
                    Image(systemName: clipped ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(clipped ? Booth.amber : Booth.green)
                } else if progress.done > 0 {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(Booth.green)
                } else {
                    Image(systemName: "circle").foregroundStyle(Booth.dim)
                }
            }
            .font(.system(size: 12)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("VO_\(block.id)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if progress.total > 1 {
                        Text("\(progress.done)/\(progress.total)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Booth.dim)
                    }
                }
                Text(block.lines.first ?? "").font(.system(size: 12)).foregroundStyle(Booth.dim).lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.white.opacity(0.09) : .clear)
        .contentShape(Rectangle())
    }
}

// MARK: - teleprompter (+ camera preview in camera mode)

struct Prompter: View {
    @EnvironmentObject var s: Session
    @EnvironmentObject var rec: Recorder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let sh = s.shown { CurrentCard(block: s.blocks[sh.block], highlight: sh.line) }
            if let n = s.nextPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("下一句", "Next")).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(n).font(.system(size: 17)).lineLimit(2)
                }
                .foregroundStyle(Booth.dim).padding(.horizontal, 24).frame(maxWidth: 680, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

struct CurrentCard: View {
    @EnvironmentObject var s: Session
    @EnvironmentObject var rec: Recorder
    let block: ScriptBlock
    let highlight: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("VO_\(block.id)" + (highlight.map { " · \($0 + 1)/\(block.lines.count)" } ?? ""))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(rec.isRecording ? Booth.red : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                if rec.isRecording {
                    Text(String(format: T("● 錄音中  %.1f 秒", "● Recording  %.1f s"), rec.takeSeconds))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Booth.red)
                } else if s.unit != .script, let t = s.shownTake {
                    Text(String(format: T("已錄 %.1f 秒 · 最大 %.0f dB", "Recorded %.1f s · peak %.0f dB"), t.seconds, t.peakDB)
                         + (t.clipped ? T(" · 有爆音，建議重錄", " · clipped, re-record") : ""))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(t.clipped ? Booth.amber : Booth.green)
                }
                Spacer()
                Text(block.section).font(.system(size: 12)).foregroundStyle(Booth.dim)
            }
            ForEach(Array(block.lines.enumerated()), id: \.offset) { i, line in
                let on = highlight == nil || highlight == i
                breathText(line).font(.system(size: on ? (s.videoMode ? 30 : 34) : 22, weight: .medium)).lineSpacing(8)
                    .opacity(on ? 1 : 0.32)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Booth.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(rec.isRecording ? Booth.red : Booth.line, lineWidth: rec.isRecording ? 2 : 1))
    }
}

/// Live camera picture (mirrored like a selfie view; the recording itself is not mirrored).
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.frame = v.bounds
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        v.layer?.addSublayer(layer)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct EmptyState: View {
    @EnvironmentObject var s: Session

    private let example = """
    ## 01 Opening

    VO_01a
    Hi everyone / welcome back to the channel.
    Today we're looking at why the sky is blue.

    VO_01b
    It sounds like a simple question / but ...
    """

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 40)).foregroundStyle(Booth.dim)
            Text(T("開啟一份稿子（.txt / .md）就可以開始錄", "Open a script (.txt / .md) to start recording"))
                .font(.system(size: 18, weight: .medium))
            HStack(alignment: .top, spacing: 22) {
                Text(example)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Booth.text.opacity(0.85))
                    .padding(14).frame(width: 330, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 7) {
                    Text(T("稿子格式", "Script format")).font(.system(size: 13, weight: .semibold))
                    rule("VO_01a", T("一行一個 VO_名稱 開始一段（一段 = 一個錄音檔）", "a VO_name line starts a block (one block = one file)"))
                    rule(T("一句一行", "1 line"), T("每一行是一句", "one sentence per line"))
                    rule(" / ", T("換氣的地方（也可以用「／」）", "where to breathe (「／」 works too)"))
                    rule("## ", T("分區標題，顯示在左邊清單", "section heading, shown in the list"))
                    rule("// ", T("自己的備註，錄音時不會顯示", "your notes, hidden while recording"))
                }
                .frame(width: 330, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button(T("開啟稿子…", "Open Script…")) { s.openPanel() }
                    .buttonStyle(.borderedProminent).tint(Booth.red).controlSize(.large)
                Button(T("存一份範本", "Save a Template")) { s.saveTemplate() }.controlSize(.large)
                Button(T("完整格式說明", "Full Format Guide")) { NSWorkspace.shared.open(ScriptTemplate.guideURL) }
                    .buttonStyle(.link)
            }
            if let m = s.message { Text(m).foregroundStyle(Booth.amber).font(.system(size: 13)).multilineTextAlignment(.center) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func rule(_ key: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Booth.amber)
                .frame(width: 64, alignment: .leading)
            Text(text).font(.system(size: 12)).foregroundStyle(Booth.dim)
        }
    }
}

// MARK: - meter

struct MeterPanel: View {
    @EnvironmentObject var rec: Recorder
    @EnvironmentObject var s: Session

    var advice: (String, Color) {
        let p = rec.peakHoldDB
        if !rec.running { return (rec.errorText ?? T("麥克風沒有在運作", "Microphone is not running"), Booth.amber) }
        if p >= -1 { return (T("爆音了！調低輸入音量或退後一點", "Clipping! Lower the input level or back off"), Booth.red) }
        if p > -6 { return (T("有點大聲，退後一點點", "A bit hot, back off slightly"), Booth.amber) }
        if p >= -20 { return (T("音量剛好 ✓", "Level is good ✓"), Booth.green) }
        if p >= -32 { return (T("太小聲：靠近一點，或調高輸入音量", "Too quiet: move closer or raise the input level"), Booth.amber) }
        return (T("試著講句話，看音量條有沒有動", "Say something and watch the meter"), Booth.dim)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(advice.0).font(.system(size: 14, weight: .semibold)).foregroundStyle(advice.1)
                Spacer()
                Text(String(format: T("峰值 %5.1f dB   平均 %5.1f dB", "peak %5.1f dB   avg %5.1f dB"), rec.peakHoldDB, rec.rmsDB))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Booth.dim)
            }
            LevelBar(peak: rec.peakDB, hold: rec.peakHoldDB).frame(height: 22)
            HStack(spacing: 10) {
                Button {
                    rec.measureNoise()
                } label: {
                    Label(rec.measuringNoise ? T("安靜 3 秒…", "Stay quiet 3 s…") : T("測環境噪音", "Measure room noise"),
                          systemImage: "ear")
                }
                .buttonStyle(.bordered).disabled(rec.measuringNoise || rec.isRecording)
                if let n = rec.noiseFloorDB {
                    Text(noiseText(n).0).font(.system(size: 12)).foregroundStyle(noiseText(n).1)
                }
                Spacer()
                Text(T("綠色區 = 講話時峰值該停的位置（−20 ～ −6 dB）", "Green zone = where speech peaks should land (−20 to −6 dB)"))
                    .font(.system(size: 11)).foregroundStyle(Booth.dim)
            }
            if let m = s.message, !s.blocks.isEmpty { Text(m).font(.system(size: 12)).foregroundStyle(Booth.amber) }
            if let e = rec.errorText, rec.running { Text(e).font(.system(size: 12)).foregroundStyle(Booth.amber) }
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(Booth.panel)
    }

    func noiseText(_ db: Float) -> (String, Color) {
        if db < -60 { return (String(format: T("環境噪音 %.0f dB：很安靜 ✓", "Room noise %.0f dB: very quiet ✓"), db), Booth.green) }
        if db < -50 { return (String(format: T("環境噪音 %.0f dB：可以錄", "Room noise %.0f dB: fine"), db), Booth.green) }
        return (String(format: T("環境噪音 %.0f dB：有點吵（冷氣、風扇、窗外？）", "Room noise %.0f dB: noisy (AC, fan, window?)"), db), Booth.amber)
    }
}

struct LevelBar: View {
    let peak: Float, hold: Float
    let lo: Float = -60

    func x(_ db: Float, _ w: CGFloat) -> CGFloat { CGFloat((max(lo, min(0, db)) - lo) / -lo) * w }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                Rectangle().fill(Booth.green.opacity(0.16))
                    .frame(width: x(-6, w) - x(-20, w)).offset(x: x(-20, w))
                Rectangle().fill(Booth.red.opacity(0.18))
                    .frame(width: w - x(-1, w)).offset(x: x(-1, w))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Booth.green, Booth.green, Booth.amber, Booth.red],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: x(peak, w)).opacity(0.9)
                Rectangle().fill(Color.white.opacity(0.85)).frame(width: 2, height: h).offset(x: max(0, x(hold, w) - 1))
                ForEach([-48, -36, -24, -20, -12, -6, -3, 0], id: \.self) { d in
                    Text("\(d)").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.white.opacity(0.5))
                        .offset(x: min(w - 14, x(Float(d), w) + 2), y: h / 2 - 5)
                }
            }
            .animation(.linear(duration: 0.05), value: peak)
        }
    }
}

// MARK: - controls

struct Controls: View {
    @EnvironmentObject var s: Session
    @EnvironmentObject var rec: Recorder

    var recordTitle: String {
        if rec.isRecording {
            if s.unit == .script {
                return s.cursor < s.flatLines.count - 1 ? T("下一句（空白鍵）", "Next line (Space)") : T("結束（空白鍵）", "Finish (Space)")
            }
            return T("停止（空白鍵）→ 下一句", "Stop (Space) → next")
        }
        if s.shownTake != nil { return T("重錄（空白鍵）", "Re-record (Space)") }
        return s.unit == .script ? T("開始錄整份（空白鍵）", "Record the script (Space)") : T("開始錄（空白鍵）", "Record (Space)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { s.go(-1) } label: { Label(T("上一個", "Previous"), systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: []).disabled(rec.isRecording).fixedSize()
            Button { s.space() } label: {
                HStack(spacing: 10) {
                    Image(systemName: rec.isRecording ? (s.unit == .script ? "forward.fill" : "stop.fill") : "record.circle")
                    Text(recordTitle)
                }
                .font(.system(size: 15, weight: .semibold)).frame(minWidth: 220).padding(.vertical, 6)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent).tint(rec.isRecording ? Booth.red.opacity(0.85) : Booth.red)
            .disabled(s.current == nil || !rec.running || s.combining != nil)
            Button { s.go(1) } label: { Label(T("下一個", "Next"), systemImage: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: []).disabled(rec.isRecording).fixedSize()
            // Esc stops any take (in whole-script mode it ends the take early)
            Button("") { s.stopRecording() }.keyboardShortcut(.escape, modifiers: []).opacity(0).frame(width: 0)
            Spacer()
            if let c = s.combining {
                ProgressView().controlSize(.small)
                Text(c).font(.system(size: 12)).foregroundStyle(Booth.dim)
            } else if s.doneCount > 0 {
                // once everything is recorded and combined the button turns into the "done" badge (click to combine again)
                let done = s.allDone && s.combinedAt != nil
                Button { Task { await s.combine() } } label: {
                    Label(done ? T("已合併 ✓", "Combined ✓") : T("合併（⌘J）", "Combine (⌘J)"),
                          systemImage: done ? "checkmark.circle.fill" : "square.stack.3d.down.forward")
                }
                .foregroundStyle(done ? Booth.green : .primary)
                .help(T("把錄好的句子接成每段一個檔，再加上整份的 _full 檔", "Join the takes into one file per block plus a _full file"))
                .disabled(rec.isRecording).fixedSize()
            }
            Button { s.playCurrent() } label: { Label(T("試聽（P）", "Play (P)"), systemImage: "play.circle") }
                .keyboardShortcut("p", modifiers: [])
                .disabled(rec.isRecording || s.shownTake == nil).fixedSize()
        }
        .controlSize(.large)
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(Booth.panel)
    }
}
