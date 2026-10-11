import AppKit
import AVFoundation
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
}

/// One recording session: a script, an output folder, and the takes recorded so far.
/// Files: <folder>/VO_<key>.wav (+ VO_<key>.mov in camera mode) for the latest take, older takes in <folder>/_old_takes/,
/// metadata in <folder>/session.json.
@MainActor
final class Session: ObservableObject {
    @Published var blocks: [ScriptBlock] = []
    @Published var index = 0
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

    let rec = Recorder()
    private var enteredFullScreen = false
    private var mainWindow: NSWindow? { NSApp.windows.first { $0.isVisible && $0.canBecomeMain } }

    var current: ScriptBlock? { blocks.indices.contains(index) ? blocks[index] : nil }
    var doneCount: Int { blocks.filter { takes[$0.id] != nil }.count }
    var videoMode: Bool { rec.mode == .video }

    // MARK: setup

    func boot() {
        // `NarrationBooth path/to/script.md` from a terminal opens that script
        if let path = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".md") || $0.hasSuffix(".txt") }) {
            open(URL(fileURLWithPath: path))
        }
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                if !ok {
                    self.message = T("沒有麥克風權限：系統設定 → 隱私權與安全性 → 麥克風 → 打開「NarrationBooth」",
                                     "No microphone access: System Settings → Privacy & Security → Microphone → allow NarrationBooth")
                }
                self.refreshDevices()
                self.selectMic(self.micUID ?? AVCaptureDevice.default(for: .audio)?.uniqueID)
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

    func selectMic(_ uid: String?) {
        guard !rec.isRecording else { return }
        micUID = uid
        rec.start(deviceUID: uid)
        if let id = coreAudioDevice {
            canSetVolume = AudioDevices.canSetInputVolume(id)
            inputVolume = AudioDevices.inputVolume(id) ?? 0.5
        } else {
            canSetVolume = false
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
            message = T("這份稿子裡找不到要唸的段落", "No lines to read in this script")
            return
        }
        blocks = b
        scriptName = url.deletingPathExtension().lastPathComponent
        setOutDir(outputBase.appendingPathComponent(scriptName + "_recordings", isDirectory: true))
        message = nil
    }

    /// Where recordings go: <output base>/<script name>_recordings/. The base is remembered between launches
    /// (default: ~/Downloads).
    @Published var outputBase: URL = {
        if let p = UserDefaults.standard.string(forKey: "outputBase"), FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }()

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
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        outDir = url
        takes = [:]
        if let data = try? Data(contentsOf: url.appendingPathComponent("session.json")),
           let saved = try? Self.decoder.decode(SavedSession.self, from: data) {
            takes = saved.takes.filter { FileManager.default.fileExists(atPath: url.appendingPathComponent("VO_\($0.key).wav").path) }
        }
        index = blocks.firstIndex { takes[$0.id] == nil } ?? 0
    }

    func audioURL(_ key: String) -> URL? { outDir?.appendingPathComponent("VO_\(key).wav") }
    func movieURL(_ key: String) -> URL? { outDir?.appendingPathComponent("VO_\(key).mov") }

    // MARK: recording

    func toggleRecord() {
        guard let block = current, let url = audioURL(block.id) else { return }
        if rec.isRecording {
            let (sec, peak, clip) = rec.stopTake()
            if sec < 0.3 {  // an accidental tap: don't keep it
                try? FileManager.default.removeItem(at: url)
                return
            }
            takes[block.id] = TakeInfo(seconds: sec, peakDB: peak, clipped: clip, recordedAt: Date(), video: videoMode)
            save()
            if index < blocks.count - 1 { index += 1 }
        } else {
            rec.stopPlayback()
            keepOldTake(block.id)
            do {
                try rec.startTake(to: url, movie: videoMode ? movieURL(block.id) : nil)
            } catch {
                message = T("沒辦法建立錄音檔：", "Couldn't create the file: ") + error.localizedDescription
            }
        }
    }

    /// Re-recording never destroys a take: the old files move to _old_takes/VO_<key>_<time>.wav/.mov
    private func keepOldTake(_ key: String) {
        guard let dir = outDir else { return }
        let old = dir.appendingPathComponent("_old_takes", isDirectory: true)
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        let stamp = f.string(from: Date())
        for (url, ext) in [(audioURL(key), "wav"), (movieURL(key), "mov")] {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: url, to: old.appendingPathComponent("VO_\(key)_\(stamp).\(ext)"))
        }
        takes[key] = nil
    }

    func playCurrent() {
        guard let block = current, let url = audioURL(block.id), FileManager.default.fileExists(atPath: url.path) else { return }
        if rec.isPlaying { rec.stopPlayback() } else { rec.play(url) }
    }

    func go(_ delta: Int) {
        guard !rec.isRecording, !blocks.isEmpty else { return }
        index = max(0, min(blocks.count - 1, index + delta))
    }

    func revealFolder() {
        if let d = outDir { NSWorkspace.shared.activateFileViewerSelecting([d]) }
    }

    // MARK: session.json

    private struct SavedSession: Codable {
        var script: String
        var microphone: String
        var camera: String?
        var format: String
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
                             takes: takes)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(s).write(to: dir.appendingPathComponent("session.json"))
    }
}
