import AppKit
import AVFoundation
import Combine
import CoreAudio
import Foundation

struct DeviceChoice: Identifiable, Hashable {
    let id: String   // AVCaptureDevice.uniqueID
    let name: String
}

struct TakeInfo: Codable, Hashable {
    var seconds: Double
    var peakDB: Float
    var clipped: Bool
    var recordedAt: Date
    var video: Bool?
    var markers: [Double]?   // whole-script takes: start time of every line, in script order
    var pace: Double?        // speed against the pacing guide: 1.0 on pace, 1.2 = 20 % faster
}

/// One recording unit in the current take mode.
struct TakeSlot: Identifiable, Hashable {
    let id: String        // file stem in takes/: VO_01a_2 (sentence), VO_01a (block), FULL (whole script)
    let blockIndex: Int
    let line: Int?        // sentence mode: the line inside the block
}

/// One recording session: a script, an output folder, the takes recorded so far, and the combined files.
/// Folder layout:
///   <output>/<script>_recordings/takes/<slot>.wav (+ .mov)   raw takes
///   <output>/<script>_recordings/_old_takes/                 earlier takes of re-recorded slots
///   <output>/<script>_recordings/VO_<block>.wav (+ .mov)     combined, one per block
///   <output>/<script>_recordings/<script>_full.wav (+ .mov)  combined, whole script
///   <output>/<script>_recordings/session.json
@MainActor
final class Session: ObservableObject {
    @Published var blocks: [ScriptBlock] = []
    @Published var slots: [TakeSlot] = []
    @Published var index = 0                 // current slot
    @Published var cursor = 0                // whole-script mode: current line (flat index across the script)
    @Published var scriptName = ""
    @Published var outDir: URL?
    @Published var takes: [String: TakeInfo] = [:]
    @Published var mics: [DeviceChoice] = []
    @Published var micUID: String?
    @Published var cameras: [DeviceChoice] = []
    @Published var cameraUID: String?
    @Published var inputVolume: Float = 0.5
    @Published var canSetVolume = false
    @Published var message: String?
    /// Native sample rate of the selected mic (0 = unknown). Bluetooth mics report 16 kHz.
    @Published var micRate: Double = 0
    var micIsLowQuality: Bool { micRate > 0 && micRate < 44_100 }
    @Published var combining: String?        // progress text while combining
    @Published var combinedAt: Date?

    let rec = Recorder()
    let prefs = Prefs.shared
    private var markers: [Double] = []
    private var bag = Set<AnyCancellable>()
    private var enteredFullScreen = false
    private var mainWindow: NSWindow? { NSApp.windows.first { $0.isVisible && $0.canBecomeMain } }

    init() {
        prefs.$unit.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildSlots() }
        }.store(in: &bag)
    }

    var unit: TakeUnit { prefs.unit }
    var videoMode: Bool { rec.mode == .video }
    var current: TakeSlot? { slots.indices.contains(index) ? slots[index] : nil }
    var doneCount: Int { slots.filter { takes[$0.id] != nil }.count }
    var allDone: Bool { !slots.isEmpty && doneCount == slots.count }

    /// (block, line) of every line in script order — the whole-script take walks through these.
    var flatLines: [(block: Int, line: Int)] {
        blocks.indices.flatMap { b in blocks[b].lines.indices.map { (b, $0) } }
    }

    /// What the prompter shows: the block and the line to highlight (nil = the whole block).
    var shown: (block: Int, line: Int?)? {
        guard !blocks.isEmpty else { return nil }
        switch unit {
        case .script:
            let f = flatLines
            guard f.indices.contains(cursor) else { return (0, nil) }
            return (f[cursor].block, f[cursor].line)
        default:
            guard let s = current else { return nil }
            return (s.blockIndex, s.line)
        }
    }

    /// The take shown in the prompter (sentence: that line, block: that block, whole script: the one take).
    var shownTake: TakeInfo? { current.flatMap { takes[$0.id] } }

    /// What comes next, for the small preview under the prompter.
    var nextPreview: String? {
        guard let sh = shown else { return nil }
        func clean(_ s: String) -> String { s.replacingOccurrences(of: " ／ ", with: "  ").replacingOccurrences(of: "／", with: " ") }
        let block = blocks[sh.block]
        if unit != .block, let l = sh.line, l + 1 < block.lines.count { return clean(block.lines[l + 1]) }
        guard sh.block + 1 < blocks.count else { return nil }
        let nb = blocks[sh.block + 1]
        return "VO_\(nb.id) · " + clean(unit == .block ? nb.lines.joined(separator: " ") : nb.lines[0])
    }

    /// Recorded slots / all slots of one block (for the list).
    func progress(ofBlock b: Int) -> (done: Int, total: Int) {
        if unit == .script { return (takes["FULL"] != nil ? 1 : 0, 1) }
        let mine = slots.filter { $0.blockIndex == b }
        return (mine.filter { takes[$0.id] != nil }.count, mine.count)
    }

    func anyClipped(inBlock b: Int) -> Bool {
        slots.filter { $0.blockIndex == b }.contains { takes[$0.id]?.clipped == true }
    }

    // MARK: setup

    func boot() {
        // `NarrationBooth path/to/script.md` from a terminal opens that script
        if let path = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".md") || $0.hasSuffix(".txt") }) {
            open(URL(fileURLWithPath: path))
        }
        watchDevices()
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                if !ok {
                    self.message = T("沒有麥克風權限：系統設定 → 隱私權與安全性 → 麥克風 → 打開「NarrationBooth」",
                                     "No microphone access: System Settings → Privacy & Security → Microphone → allow NarrationBooth")
                }
                self.refreshDevices()
                // the mic chosen last time, if it's connected
                let saved = UserDefaults.standard.string(forKey: "micUID").flatMap { uid in self.mics.contains { $0.id == uid } ? uid : nil }
                self.selectMic(saved ?? self.micUID ?? AVCaptureDevice.default(for: .audio)?.uniqueID)
            }
        }
    }

    /// Mics and cameras that are plugged in or paired (Bluetooth, USB, iPhone) while the app is open show up right away.
    /// A newly connected mic is selected (unless a take is running); if the selected one goes away, it falls back to the default.
    private func watchDevices() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let dev = n.object as? AVCaptureDevice else { return }
            // Core Audio needs a moment before a Bluetooth input is ready to open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.refreshDevices()
                guard dev.hasMediaType(.audio), !self.rec.isRecording, self.combining == nil else { return }
                self.selectMic(dev.uniqueID, remember: true)
                self.message = T("已切換到 %@", "Switched to %@", dev.localizedName)
            }
        }
        nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let dev = n.object as? AVCaptureDevice else { return }
            let wasMine = dev.uniqueID == self.micUID
            if wasMine && self.rec.isRecording { self.stopRecording() }
            self.refreshDevices()
            if wasMine {
                self.selectMic(AVCaptureDevice.default(for: .audio)?.uniqueID)
                self.message = T("%@ 斷線了，改用預設麥克風", "%@ disconnected; using the default mic", dev.localizedName)
            }
            if dev.uniqueID == self.cameraUID {
                self.cameraUID = self.cameras.first?.id
                if self.videoMode { self.rec.setVideo(cameraUID: self.cameraUID) }
            }
        }
    }

    func refreshDevices() {
        mics = Recorder.microphones().map { DeviceChoice(id: $0.uniqueID, name: $0.localizedName) }
        cameras = Recorder.cameras().map { DeviceChoice(id: $0.uniqueID, name: $0.localizedName) }
        if micUID == nil { micUID = AVCaptureDevice.default(for: .audio)?.uniqueID }
        if cameraUID == nil { cameraUID = cameras.first?.id }
    }

    private var coreAudioDevice: AudioDeviceID? { micUID.flatMap { AudioDevices.coreAudioID(uid: $0) } }

    func selectMic(_ uid: String?, remember: Bool = false) {
        guard !rec.isRecording else { return }
        micUID = uid
        if remember, let uid { UserDefaults.standard.set(uid, forKey: "micUID") }
        rec.start(deviceUID: uid)
        if let id = coreAudioDevice {
            canSetVolume = AudioDevices.canSetInputVolume(id)
            inputVolume = AudioDevices.inputVolume(id) ?? 0.5
            // Bluetooth mics run in the hands-free profile on a Mac: 16 kHz, phone quality
            let sr = AudioDevices.sampleRate(id)
            micRate = sr
            if micIsLowQuality {
                message = T("注意：這支麥克風現在只有 %@ kHz（藍牙是電話音質）。想要好音質請用 USB／線材接收器，或改用內建麥克風。",
                            "Heads-up: this mic only delivers %@ kHz right now (Bluetooth runs at phone quality). For good sound, connect its receiver by USB or cable, or use the built-in mic.",
                            "\(Int(sr / 1000))")
            }
        } else {
            canSetVolume = false
            micRate = 0
        }
    }

    func setVolume(_ v: Float) {
        inputVolume = v
        if let id = coreAudioDevice { AudioDevices.setInputVolume(id, v) }
    }

    func setMode(_ mode: Recorder.Mode) {
        guard !rec.isRecording else { return }
        if mode == .audio {
            rec.mode = .audio
            rec.setVideo(cameraUID: nil)
            if enteredFullScreen, let w = mainWindow, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
            enteredFullScreen = false
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                guard ok else {
                    self.message = T("沒有相機權限：系統設定 → 隱私權與安全性 → 相機 → 打開「NarrationBooth」",
                                     "No camera access: System Settings → Privacy & Security → Camera → allow NarrationBooth")
                    return
                }
                self.refreshDevices()
                self.rec.mode = .video
                self.rec.setVideo(cameraUID: self.cameraUID)
                // full screen puts the window's centre (and the script) right under the built-in camera
                if let w = self.mainWindow, !w.styleMask.contains(.fullScreen) {
                    w.toggleFullScreen(nil)
                    self.enteredFullScreen = true
                }
            }
        }
    }

    func selectCamera(_ uid: String) {
        guard !rec.isRecording else { return }
        cameraUID = uid
        if videoMode { rec.setVideo(cameraUID: uid) }
    }

    // MARK: script

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .text, .init(filenameExtension: "md")!]
        p.allowsMultipleSelection = false
        p.message = T("選一份錄音稿（.txt 或 .md）", "Choose a script (.txt or .md)")
        if p.runModal() == .OK, let url = p.url { open(url) }
    }

    func open(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            message = T("讀不到這個檔案", "Couldn't read that file")
            return
        }
        let b = ScriptParser.parse(text)
        guard !b.isEmpty else {
            message = T("這份稿子裡找不到要唸的段落。格式說明：選單 Help → Script Format Guide",
                        "No lines to read in this script. See Help → Script Format Guide.")
            return
        }
        let dup = ScriptParser.duplicates(b)
        guard dup.isEmpty else {
            message = T("段落名稱重複：", "Duplicate block names: ") + dup.map { "VO_" + $0 }.joined(separator: ", ")
                + T("（每個 VO_ 名稱都要不一樣，不然錄音檔會互相覆蓋）", " (each VO_ name must be unique, or the files overwrite each other)")
            return
        }
        blocks = b
        prefs.paceLanguage = PaceLanguage.detect(b.flatMap(\.lines))
        scriptName = url.deletingPathExtension().lastPathComponent
        setOutDir(outputBase.appendingPathComponent(scriptName + "_recordings", isDirectory: true))
        message = nil
    }

    func rebuildSlots() {
        guard !rec.isRecording else { return }
        switch unit {
        case .sentence:
            slots = blocks.indices.flatMap { b in
                blocks[b].lines.indices.map { TakeSlot(id: "VO_\(blocks[b].id)_\($0 + 1)", blockIndex: b, line: $0) }
            }
        case .block:
            slots = blocks.indices.map { TakeSlot(id: "VO_\(blocks[$0].id)", blockIndex: $0, line: nil) }
        case .script:
            slots = blocks.isEmpty ? [] : [TakeSlot(id: "FULL", blockIndex: 0, line: nil)]
        }
        index = slots.firstIndex { takes[$0.id] == nil } ?? 0
        cursor = 0
    }

    /// Where recordings go: <output base>/<script name>_recordings/. The base is remembered between launches
    /// (default: ~/Downloads).
    @Published var outputBase: URL = {
        if let p = UserDefaults.standard.string(forKey: "outputBase"), FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }()

    /// Writes a starter script the user can fill in (examples/template.txt in the repo).
    func saveTemplate() {
        let p = NSSavePanel()
        p.nameFieldStringValue = T("我的稿子.txt", "my_script.txt")
        p.allowedContentTypes = [.plainText]
        p.message = T("存一份範本，照著格式寫你的稿子", "Save a template and write your script in this format")
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try ScriptTemplate.text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            message = T("存不了範本：", "Couldn't save the template: ") + error.localizedDescription
        }
    }

    func chooseOutDir() {
        guard !rec.isRecording else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = outputBase
        p.prompt = T("存在這裡", "Save here")
        p.message = T("選一個資料夾：每份稿子會在裡面建一個「稿子名_recordings」資料夾",
                      "Pick a folder. Each script gets its own \"<script>_recordings\" folder inside it.")
        guard p.runModal() == .OK, let url = p.url else { return }
        outputBase = url
        UserDefaults.standard.set(url.path, forKey: "outputBase")
        if !scriptName.isEmpty {
            setOutDir(url.appendingPathComponent(scriptName + "_recordings", isDirectory: true))
        }
    }

    private func setOutDir(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("takes"), withIntermediateDirectories: true)
        outDir = url
        takes = [:]
        if let data = try? Data(contentsOf: url.appendingPathComponent("session.json")),
           let saved = try? Self.decoder.decode(SavedSession.self, from: data) {
            takes = saved.takes.filter {
                FileManager.default.fileExists(atPath: url.appendingPathComponent("takes/\($0.key).wav").path)
            }
        }
        rebuildSlots()
    }

    func takeURL(_ slot: String, _ ext: String = "wav") -> URL? { outDir?.appendingPathComponent("takes/\(slot).\(ext)") }

    // MARK: recording

    /// Space.
    /// - Sentence / block mode, review on (default): start → stop (stay on the take so you can play it with P or
    ///   re-record with R) → Space again moves to the next line and starts recording it (if it isn't recorded yet).
    /// - Review off: start → stop and move to the next line.
    /// - Whole-script mode: start, then next line, and after the last line stop.
    func space() {
        if unit == .script && rec.isRecording {
            if cursor < flatLines.count - 1 {
                cursor += 1
                markers.append(rec.takeSeconds)
                paceStart = Date()
            } else {
                stopRecording()
            }
            return
        }
        if rec.isRecording { stopRecording(); return }
        if reviewing && unit != .script {
            reviewing = false
            guard advance() else { return }     // past the last line: nothing more to record
            // only start right away on a line that still needs a take; a recorded one is just shown
            if let c = current, takes[c.id] != nil { return }
        }
        startRecording()
    }

    /// The take that was just recorded is waiting to be listened to (P), re-recorded (R) or accepted (Space / →).
    @Published var reviewing = false

    /// When the pacing guide started for the line(s) on screen (nil = not recording).
    @Published var paceStart: Date?

    /// The pacing guide for one line, when it is being recorded right now.
    func paceTimeline(block b: Int, line i: Int) -> PaceTimeline? {
        guard prefs.paceGuide, rec.isRecording, paceStart != nil, let sh = shown, sh.block == b,
              blocks[b].lines.indices.contains(i) else { return nil }
        if unit == .block { return paceTimelines(blocks[b].lines, rate: prefs.currentRate)[i] }
        return sh.line == i ? PaceTimeline(line: blocks[b].lines[i], rate: prefs.currentRate) : nil
    }

    /// [ and ]: slower / faster.
    func nudgePace(_ d: Double) {
        prefs.currentRate = prefs.currentRate + (prefs.paceLanguage == .en ? d / 2 : d)
    }

    /// Re-record the line on screen (R, or the button while reviewing).
    func rerecord() {
        guard !rec.isRecording else { return }
        reviewing = false
        startRecording()
    }

    /// Moves to the next line in script order (never skips lines, recorded or not). At the end it goes to the first
    /// line still missing, if any. Returns false when there is nowhere to go.
    @discardableResult
    func nextNeedsTake() -> Bool {
        let next = index + 1 < slots.count ? index + 1 : slots.indices.first { takes[slots[$0].id] == nil }
        return next.map { takes[slots[$0].id] == nil } ?? false
    }

    private func advance() -> Bool {
        if index + 1 < slots.count { index += 1; return true }
        if let missing = slots.indices.first(where: { takes[slots[$0].id] == nil }) { index = missing; return true }
        message = T("全部錄完了 ✓  要重錄哪一句，點它或用 ← → 選。", "Everything is recorded ✓  To redo a line, click it or pick it with ← →.")
        return false
    }

    private var pendingOld: (slot: String, moved: [(from: URL, to: URL)], info: TakeInfo?)?

    func startRecording() {
        guard let slot = current, let url = takeURL(slot.id), combining == nil else { return }
        rec.stopPlayback()
        reviewing = false
        pendingOld = (slot.id, keepOldTake(slot.id), takes[slot.id])
        takes[slot.id] = nil
        if unit == .script {
            cursor = 0
            markers = [0]
        }
        do {
            try rec.startTake(to: url, movie: videoMode ? takeURL(slot.id, "mov") : nil)
            paceStart = Date()
        } catch {
            message = T("沒辦法建立錄音檔：", "Couldn't create the file: ") + error.localizedDescription
        }
    }

    func stopRecording() {
        guard rec.isRecording, let slot = current, let url = takeURL(slot.id) else { return }
        let (sec, peak, clip) = rec.stopTake()
        paceStart = nil
        let old = pendingOld
        pendingOld = nil
        if sec < 0.3 {  // an accidental tap: throw it away and put the previous take back
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("mov"))
            if let old, old.slot == slot.id {
                for m in old.moved { try? FileManager.default.moveItem(at: m.to, to: m.from) }
                takes[slot.id] = old.info
            }
            return
        }
        if rec.usedSafetyTrack {
            message = T("這句爆音了，已自動改用麥克風的安全音軌（小 6 dB、沒爆音）。", "That take clipped, so it was saved from the mic's safety track (6 dB lower, not clipped).")
        }
        var pace: Double?
        if unit != .script {
            let lines = slot.line.map { [blocks[slot.blockIndex].lines[$0]] } ?? blocks[slot.blockIndex].lines
            pace = paceRatio(take: url, lines: lines, rate: prefs.currentRate)
        }
        takes[slot.id] = TakeInfo(seconds: sec, peakDB: peak, clipped: clip, recordedAt: Date(), video: videoMode,
                                  markers: unit == .script ? markers : nil, pace: pace)
        save()
        if allDone && prefs.autoCombine { Task { await combine() } }   // re-recording a line later combines again
        if unit == .script { return }
        if prefs.reviewTakes {
            reviewing = true
            if prefs.autoPlay { rec.play(url) }
        } else if !allDone {
            advance()
        }
    }

    /// Re-recording never destroys a take: the old files move to _old_takes/<slot>_<time>.wav/.mov.
    /// Returns what was moved, so an accidental tap can put it back.
    private func keepOldTake(_ slot: String) -> [(from: URL, to: URL)] {
        guard let dir = outDir else { return [] }
        let old = dir.appendingPathComponent("_old_takes", isDirectory: true)
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        let stamp = f.string(from: Date())
        var moved: [(from: URL, to: URL)] = []
        for ext in ["wav", "mov"] {
            guard let url = takeURL(slot, ext), FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            let dest = old.appendingPathComponent("\(slot)_\(stamp).\(ext)")
            if (try? FileManager.default.moveItem(at: url, to: dest)) != nil { moved.append((url, dest)) }
        }
        return moved
    }

    /// Pick one line (click in the prompter).
    func select(block b: Int, line: Int) {
        guard !rec.isRecording, unit == .sentence else { return }
        if let i = slots.firstIndex(where: { $0.blockIndex == b && $0.line == line }) {
            index = i
            reviewing = false
        }
    }

    func playCurrent() {
        guard let slot = current, let url = takeURL(slot.id), FileManager.default.fileExists(atPath: url.path) else { return }
        if rec.isPlaying { rec.stopPlayback() } else { rec.play(url) }
    }

    func go(_ delta: Int) {
        guard !rec.isRecording else { return }
        reviewing = false
        if unit == .script {
            cursor = max(0, min(flatLines.count - 1, cursor + delta))
        } else if !slots.isEmpty {
            index = max(0, min(slots.count - 1, index + delta))
        }
    }

    /// Jump to a block from the list.
    func select(block b: Int) {
        guard !rec.isRecording else { return }
        reviewing = false
        if unit == .script {
            cursor = flatLines.firstIndex { $0.block == b } ?? cursor
        } else {
            index = slots.firstIndex { $0.blockIndex == b && takes[$0.id] == nil }
                ?? slots.firstIndex { $0.blockIndex == b } ?? index
        }
    }

    func revealFolder() {
        if let d = outDir { NSWorkspace.shared.activateFileViewerSelecting([d]) }
    }

    // MARK: combining

    /// The takes that cover a block, as (wav, mov, window) per line or per block, from whatever exists:
    /// sentence takes (all lines of the block) > a block take > the whole-script take cut at its line markers.
    private func sources(forBlock b: Int) -> [(wav: URL, mov: URL?, from: Double, to: Double)]? {
        guard let dir = outDir else { return nil }
        let fm = FileManager.default
        func mov(_ stem: String) -> URL? {
            let u = dir.appendingPathComponent("takes/\(stem).mov")
            return fm.fileExists(atPath: u.path) ? u : nil
        }
        let block = blocks[b]
        let lineStems = block.lines.indices.map { "VO_\(block.id)_\($0 + 1)" }
        if lineStems.allSatisfy({ takes[$0] != nil }) {
            return lineStems.map { (dir.appendingPathComponent("takes/\($0).wav"), mov($0), 0, .infinity) }
        }
        let blockStem = "VO_\(block.id)"
        if takes[blockStem] != nil {
            return [(dir.appendingPathComponent("takes/\(blockStem).wav"), mov(blockStem), 0, .infinity)]
        }
        if let full = takes["FULL"], let m = full.markers, m.count == flatLines.count {
            let flat = flatLines
            return flat.indices.filter { flat[$0].block == b }.map { i in
                (dir.appendingPathComponent("takes/FULL.wav"), mov("FULL"), max(0, m[i] - 0.05),
                 i + 1 < m.count ? m[i + 1] : .infinity)
            }
        }
        return nil
    }

    func combine() async {
        guard let dir = outDir, combining == nil, !rec.isRecording else { return }
        let trim = prefs.trimSilence, sGap = prefs.sentenceGap, bGap = prefs.blockGap
        let all = blocks.indices.compactMap { b in sources(forBlock: b).map { (b, $0) } }
        guard !all.isEmpty else {
            message = T("還沒有可以合併的錄音", "Nothing recorded to combine yet")
            return
        }
        combining = T("合併中…", "Combining…")
        var cache: [URL: [Float]] = [:]
        var fullPieces: [Piece] = []
        var videoOK = true
        do {
            for (n, (b, src)) in all.enumerated() {
                combining = T("合併中… %@/%@", "Combining… %@/%@", "\(n + 1)", "\(all.count)")
                var blockPieces: [Piece] = []
                for (k, s) in src.enumerated() {
                    if cache[s.wav] == nil { cache[s.wav] = try Combiner.read(s.wav) }
                    let samples = cache[s.wav]!
                    let firstInBlock = k == 0, lastInBlock = k == src.count - 1
                    // per-block file: a little padding at its ends; whole file: half the gap on each side of every cut
                    let r = Combiner.keep(samples, from: s.from, to: s.to, lead: firstInBlock ? 0.15 : sGap / 2,
                                          tail: lastInBlock ? 0.3 : sGap / 2, trim: trim)
                    blockPieces.append(Piece(wav: s.wav, mov: s.mov, start: r.0, end: r.1))
                    let isFirst = n == 0 && firstInBlock, isLast = n == all.count - 1 && lastInBlock
                    let f = Combiner.keep(samples, from: s.from, to: s.to,
                                          lead: isFirst ? 0.15 : (firstInBlock ? bGap / 2 : sGap / 2),
                                          tail: isLast ? 0.4 : (lastInBlock ? bGap / 2 : sGap / 2), trim: trim)
                    fullPieces.append(Piece(wav: s.wav, mov: s.mov, start: f.0, end: f.1))
                }
                let wav = dir.appendingPathComponent("VO_\(blocks[b].id).wav")
                try Combiner.joinAudio(blockPieces, cache: &cache, to: wav)
                if blockPieces.allSatisfy({ $0.mov != nil }) {
                    try await Combiner.joinVideo(blockPieces, audio: wav, to: dir.appendingPathComponent("VO_\(blocks[b].id).mov"))
                } else {
                    videoOK = false
                }
            }
            combining = T("合併整份…", "Combining the whole script…")
            let fullWav = dir.appendingPathComponent("\(scriptName)_full.wav")
            let dur = try Combiner.joinAudio(fullPieces, cache: &cache, to: fullWav)
            if videoOK && fullPieces.allSatisfy({ $0.mov != nil }) {
                try await Combiner.joinVideo(fullPieces, audio: fullWav, to: dir.appendingPathComponent("\(scriptName)_full.mov"))
            }
            combinedAt = Date()
            let missing = blocks.count - all.count
            message = T("合併好了：%1$@ 個段落 + 整份 %3$@ 秒的 %2$@_full.wav",
                        "Combined: %1$@ blocks + %2$@_full.wav (%3$@ s)",
                        "\(all.count)", scriptName, String(format: "%.0f", dur))
                + (missing > 0 ? T("（還有 %@ 段沒錄）", " (%@ blocks not recorded yet)", "\(missing)") : "")
        } catch {
            message = T("合併失敗：", "Combining failed: ") + error.localizedDescription
        }
        combining = nil
    }

    // MARK: session.json

    private struct SavedSession: Codable {
        var script: String
        var microphone: String
        var camera: String?
        var format: String
        var unit: String?
        var takes: [String: TakeInfo]
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func save() {
        guard let dir = outDir else { return }
        let s = SavedSession(script: scriptName,
                             microphone: mics.first { $0.id == micUID }?.name ?? "",
                             camera: videoMode ? rec.videoLabel : nil,
                             format: "WAV 48 kHz 24-bit mono, no processing" + (videoMode ? " + MOV (HEVC)" : ""),
                             unit: unit.rawValue,
                             takes: takes)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(s).write(to: dir.appendingPathComponent("session.json"))
    }
}
