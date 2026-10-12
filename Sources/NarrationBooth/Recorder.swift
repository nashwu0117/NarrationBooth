import AVFoundation
import Combine
import CoreAudio

/// Mic capture with AVCaptureSession (input-only, so a missing/odd output device can't stop it — AVAudioEngine did).
/// Live meter + takes written as 48 kHz / 24-bit / mono WAV. No voice processing, no AGC, no compression: the file is
/// exactly what the mic hears. The capture output delivers 48 kHz stereo float (see `Channels`); the file stores
/// 24-bit integer PCM, mono.
final class Recorder: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate,
                      AVCaptureFileOutputRecordingDelegate {
    enum Mode: String, CaseIterable { case audio, video }
    // meter (dBFS), published on the main thread ~20×/s
    @Published var rmsDB: Float = -120
    @Published var peakDB: Float = -120
    @Published var peakHoldDB: Float = -120
    // current take
    @Published var isRecording = false
    @Published var takeSeconds: Double = 0
    @Published var takePeakDB: Float = -120
    @Published var clipped = false
    // device / status
    @Published var running = false
    @Published var deviceRate: Double = 48_000
    @Published var errorText: String?
    @Published var noiseFloorDB: Float?
    @Published var measuringNoise = false
    // camera (video mode)
    @Published var mode: Mode = .audio
    @Published var videoLabel = ""

    private var videoInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()

    static let fileRate: Double = 48_000
    let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "booth.audio")
    private let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.fileRate, channels: 1,
                                           interleaved: false)!
    private var inChannels = 1                    // capture queue only: 1 or 2, matches the mic

    /// Float, non-interleaved, at the mic's own channel count (a mono mic asked for stereo comes back 3 dB down).
    static func captureSettings(channels: Int) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Recorder.fileRate, AVNumberOfChannelsKey: channels,
         AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true,
         AVLinearPCMIsBigEndianKey: false]
    }
    private let lock = NSLock()

    /// What the two channels of the input carry. Wireless-mic receivers (DJI Mic, RØDE…) send two channels: either a
    /// second mic, or a "safety track", the same voice 6 dB quieter. Letting macOS fold them into mono would add the
    /// safety track on top of the voice (+0.5 dB, and it clips sooner). Instead: one voice → record the main channel,
    /// keep the safety track on the side, and if the main channel clipped during the take, the take is saved from the
    /// safety track (6 dB lower, not clipped); two voices → mix them.
    enum Channels { case unknown, same, safety, two }
    private var channels: Channels = .unknown     // capture queue only; reset when the mic changes
    private var safetySamples: [Float] = []       // guarded by lock: the take's safety track (safety mode only)
    private var mainClipped = false               // guarded by lock
    private var takeURL: URL?
    /// The last take was saved from the safety track because the main channel clipped.
    @Published var usedSafetyTrack = false
    private var file: AVAudioFile?            // guarded by lock (written on the capture queue)
    private var framesWritten: AVAudioFramePosition = 0
    private var holdUntil = Date.distantPast
    private var lastPublish = Date.distantPast
    private var noiseSamples: [Float] = []
    private var player: AVAudioPlayer?

    override init() {
        super.init()
        output.audioSettings = Self.captureSettings(channels: 1)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    // MARK: session

    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    /// Video mode on/off: adds the camera + a movie output to the same session (macOS allows the WAV data output and
    /// the movie output side by side, so every take gets VO_x.wav for the edit and VO_x.mov for the picture).
    func setVideo(cameraUID: String?) {
        session.beginConfiguration()
        if let v = videoInput { session.removeInput(v); videoInput = nil }
        if session.outputs.contains(movieOutput) { session.removeOutput(movieOutput) }
        guard mode == .video else {
            session.sessionPreset = .high
            session.commitConfiguration()
            videoLabel = ""
            return
        }
        let cam = cameraUID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? Recorder.cameras().first
        guard let cam, let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else {
            session.commitConfiguration()
            errorText = T("抓不到鏡頭：系統設定 → 隱私權與安全性 → 相機 → 打開「NarrationBooth」",
                          "No camera: System Settings → Privacy & Security → Camera → allow NarrationBooth")
            return
        }
        session.addInput(input)
        videoInput = input
        for preset in [AVCaptureSession.Preset.hd4K3840x2160, .hd1920x1080, .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            break
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if let c = movieOutput.connection(with: .video) {  // HEVC: every Apple-silicon Mac encodes it in hardware
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: c)
        }
        session.commitConfiguration()
        let d = cam.activeFormat.formatDescription.dimensions
        videoLabel = "\(cam.localizedName) · \(d.width)×\(d.height) HEVC"
    }

    func start(deviceUID: String?) {
        errorText = nil
        session.beginConfiguration()
        for i in session.inputs { session.removeInput(i) }
        let dev = deviceUID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .audio)
        guard let dev, let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else {
            session.commitConfiguration()
            errorText = T("抓不到麥克風：請到「系統設定 → 隱私權與安全性 → 麥克風」允許「NarrationBooth」",
                          "No microphone: System Settings → Privacy & Security → Microphone → allow NarrationBooth")
            running = false
            return
        }
        session.addInput(input)
        // two-channel inputs (wireless receivers) are handled in toMono; anything wider just uses its first two
        let devChannels = Self.inputChannels(dev)
        let want = devChannels >= 2 ? 2 : 1
        output.audioSettings = Self.captureSettings(channels: want)
        queue.async { [weak self] in
            self?.inChannels = want
            self?.channels = .unknown
        }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        queue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
            let ok = self.session.isRunning
            DispatchQueue.main.async {
                self.running = ok
                if !ok { self.errorText = T("麥克風啟動失敗（可能被其他 App 佔用）", "Couldn't start the microphone (in use by another app?)") }
            }
        }
        deviceRate = AudioDevices.coreAudioID(uid: dev.uniqueID).map(AudioDevices.sampleRate) ?? Recorder.fileRate
    }

    static func inputChannels(_ dev: AVCaptureDevice) -> Int {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(dev.activeFormat.formatDescription) else { return 1 }
        return Int(asbd.pointee.mChannelsPerFrame)
    }

    func stop() {
        if isRecording { _ = stopTake() }
        queue.async { [weak self] in self?.session.stopRunning() }
        running = false
    }

    // MARK: capture queue

    private func toMono(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ out: UnsafeMutablePointer<Float>, _ n: Int) {
        if channels == .unknown {
            // decide once, on the first buffer with sound in it (silence can't tell the cases apart)
            var el: Float = 0, eSame: Float = 0, eSafety: Float = 0
            for i in 0..<n where abs(l[i]) < 0.99 {   // clipped samples would hide the relationship
                el += l[i] * l[i]
                eSame += (l[i] - r[i]) * (l[i] - r[i])
                eSafety += (l[i] - 2 * r[i]) * (l[i] - 2 * r[i])
            }
            if el / Float(n) > 1e-6 {   // louder than −60 dBFS
                channels = eSame < el * 0.01 ? .same : eSafety < el * 0.01 ? .safety : .two
            }
        }
        switch channels {
        case .two:
            for i in 0..<n { out[i] = (l[i] + r[i]) * 0.7071 }
        case .safety, .same, .unknown:
            out.update(from: l, count: n)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        let n = CMSampleBufferGetNumSamples(sb)
        let chans = inChannels
        guard n > 0,
              let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.fileRate,
                                           channels: AVAudioChannelCount(chans), interleaved: false),
              let src = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(n)),
              let buf = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: AVAudioFrameCount(n)) else { return }
        src.frameLength = AVAudioFrameCount(n)
        buf.frameLength = AVAudioFrameCount(n)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(n),
                                                           into: src.mutableAudioBufferList) == noErr,
              let l = src.floatChannelData?[0], let data = buf.floatChannelData?[0] else { return }
        var safety: UnsafePointer<Float>?
        if chans == 2, let r = src.floatChannelData?[1] {
            toMono(l, r, data, n)
            if channels == .safety { safety = UnsafePointer(r) }
        } else {
            data.update(from: l, count: n)
        }
        var sum: Float = 0, pk: Float = 0
        for i in 0..<n {
            let v = data[i]
            sum += v * v
            pk = max(pk, abs(v))
        }
        let rms = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        let peak = 20 * log10(max(pk, 1e-6))

        lock.lock()
        if let f = file {
            try? f.write(from: buf)
            framesWritten += AVAudioFramePosition(n)
            if let safety {
                safetySamples.append(contentsOf: UnsafeBufferPointer(start: safety, count: n))
                // same −0.5 dB line as the clip warning
                if !mainClipped, (0..<n).contains(where: { abs(l[$0]) > 0.944 }) { mainClipped = true }
            }
        }
        let written = framesWritten
        lock.unlock()

        let now = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.measuringNoise { self.noiseSamples.append(rms) }
            if self.isRecording {
                self.takePeakDB = max(self.takePeakDB, peak)
                if peak > -0.5 { self.clipped = true }
                self.takeSeconds = Double(written) / Recorder.fileRate
            }
            if peak >= self.peakHoldDB || now > self.holdUntil {
                self.peakHoldDB = peak
                self.holdUntil = now.addingTimeInterval(1.5)
            }
            if now.timeIntervalSince(self.lastPublish) > 0.045 {
                self.rmsDB = rms
                self.peakDB = peak
                self.lastPublish = now
            }
        }
    }

    // MARK: takes

    private var pendingFile: AVAudioFile?   // camera mode: the WAV starts when the movie actually starts (same t=0)

    func startTake(to url: URL, movie: URL? = nil) throws {
        let withMovie = movie != nil && mode == .video && session.outputs.contains(movieOutput)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Recorder.fileRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.lock()
        framesWritten = 0
        safetySamples = []
        mainClipped = false
        if withMovie { pendingFile = f } else { file = f }
        lock.unlock()
        takeURL = url
        usedSafetyTrack = false
        if withMovie, let movie { movieOutput.startRecording(to: movie, recordingDelegate: self) }
        takePeakDB = -120
        takeSeconds = 0
        clipped = false
        isRecording = true
    }

    /// Closes the file. Returns (seconds, peak dBFS, clipped).
    @discardableResult
    func stopTake() -> (Double, Float, Bool) {
        if movieOutput.isRecording { movieOutput.stopRecording() }
        lock.lock()
        file = nil   // AVAudioFile flushes and closes when released
        pendingFile = nil
        let frames = framesWritten
        let safety = mainClipped ? safetySamples : []
        safetySamples = []
        lock.unlock()
        isRecording = false
        // the main channel clipped: save the take from the safety track instead (same voice, 6 dB lower)
        if !safety.isEmpty, let url = takeURL, (try? Combiner.write(safety, to: url)) != nil {
            let pk = safety.reduce(Float(0)) { max($0, abs($1)) }
            let peak = 20 * log10(max(pk, 1e-6))
            usedSafetyTrack = true
            clipped = peak > -0.5
            takePeakDB = peak
        }
        return (Double(frames) / Recorder.fileRate, takePeakDB, clipped)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        lock.lock()
        if let f = pendingFile { file = f; pendingFile = nil }
        lock.unlock()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection],
                    error: Error?) {
        guard let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true else { return }
        DispatchQueue.main.async { self.errorText = T("影片沒有存好：", "Video not saved: ") + error.localizedDescription }
    }

    // MARK: noise floor test (3 s of silence)

    func measureNoise() {
        noiseSamples = []
        noiseFloorDB = nil
        measuringNoise = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.measuringNoise = false
            let s = self.noiseSamples.sorted()
            self.noiseFloorDB = s.isEmpty ? nil : s[s.count / 2]
        }
    }

    // MARK: playback

    @Published private(set) var isPlaying = false
    private var playTimer: Timer?

    func play(_ url: URL) {
        player?.stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        isPlaying = player?.isPlaying ?? false
        // AVAudioPlayer has no Combine hook for "finished": poll so the Play/Stop button flips back
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if !(self.player?.isPlaying ?? false) { self.isPlaying = false; t.invalidate() }
        }
    }

    func stopPlayback() {
        player?.stop()
        isPlaying = false
        playTimer?.invalidate()
    }
}
