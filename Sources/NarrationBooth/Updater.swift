import AppKit
import CryptoKit
import Foundation

/// Checks GitHub Releases for a newer version: once a day at launch (quietly) and from the app menu.
/// "Install and Relaunch" downloads the release's .zip, checks it against the release's .sha256, unzips it, checks the
/// bundle (same bundle id, the announced version, intact code signature), moves the running copy to the Trash, puts
/// the new one in its place and reopens it. Anything that doesn't check out falls back to opening the download page.
enum Updater {
    static let repo = "nashwu0117/NarrationBooth"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedVersion"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let body: String?
        let assets: [Asset]

        var version: String { tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
        var zip: Asset? { assets.first { $0.name.lowercased().hasSuffix(".zip") } }
        var download: URL? { zip?.browser_download_url }
        /// "<zip name>.sha256", published next to the ZIP by Scripts/release.sh.
        var checksum: URL? {
            guard let z = zip else { return nil }
            return assets.first { $0.name == z.name + ".sha256" }?.browser_download_url
        }
    }

    /// Quiet daily check at launch.
    static func checkInBackgroundIfDue() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    @MainActor
    static func check(userInitiated: Bool) async {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("NarrationBooth/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let rel = try JSONDecoder().decode(Release.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            if isNewer(rel.version, than: currentVersion) {
                if !userInitiated, UserDefaults.standard.string(forKey: skippedKey) == rel.version { return }
                offer(rel)
            } else if userInitiated {
                alert(T("已經是最新版", "You're up to date"),
                      T("NarrationBooth %@ 是最新版本。", "NarrationBooth %@ is the latest version.", currentVersion))
            }
        } catch {
            if userInitiated {
                alert(T("沒辦法檢查更新", "Couldn't check for updates"),
                      T("請確認網路連線，或到 GitHub 頁面查看：", "Check your connection, or look on GitHub: ")
                        + "https://github.com/\(repo)/releases")
            }
        }
    }

    /// "1.10.0" > "1.9.2"; missing parts count as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @MainActor
    private static func offer(_ rel: Release) {
        let a = NSAlert()
        a.messageText = T("有新版本：NarrationBooth %@", "NarrationBooth %@ is available", rel.version)
        let notes = (rel.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        a.informativeText = T("你現在用的是 %@。", "You have %@.", currentVersion)
            + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(900)))
        let canInstall = rel.zip != nil && rel.checksum != nil
        a.addButton(withTitle: canInstall ? T("安裝並重新開啟", "Install and Relaunch") : T("下載", "Download"))
        a.addButton(withTitle: T("稍後", "Later"))
        a.addButton(withTitle: T("略過這個版本", "Skip This Version"))
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if canInstall { Task { await install(rel) } } else { NSWorkspace.shared.open(rel.download ?? rel.html_url) }
        case .alertThirdButtonReturn: UserDefaults.standard.set(rel.version, forKey: skippedKey)
        default: break
        }
    }

    // MARK: install

    struct InstallError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    @MainActor
    static func install(_ rel: Release) async {
        let progress = ProgressPanel(T("正在下載 NarrationBooth %@…", "Downloading NarrationBooth %@…", rel.version))
        do {
            guard let zipURL = rel.download, let sumURL = rel.checksum else { throw InstallError("no ZIP in this release") }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("NarrationBooth-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            // 1. download the ZIP and its checksum, and compare
            let (tmpZip, r1) = try await URLSession.shared.download(from: zipURL)
            guard (r1 as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError("download failed") }
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tmpZip, to: zip)
            let (sumData, r2) = try await URLSession.shared.data(from: sumURL)
            guard (r2 as? HTTPURLResponse)?.statusCode == 200,
                  let expected = String(decoding: sumData, as: UTF8.self).split(separator: " ").first?.lowercased() else {
                throw InstallError("checksum missing")
            }
            let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw InstallError(T("下載的檔案和官方指紋不符", "the download doesn't match its checksum")) }

            // 2. unzip and check what came out
            progress.text = T("正在安裝…", "Installing…")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("NarrationBooth.app")
            guard let info = Bundle(url: newApp)?.infoDictionary,
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  info["CFBundleShortVersionString"] as? String == rel.version else {
                throw InstallError(T("下載的不是預期的 NarrationBooth 版本", "the download isn't the expected NarrationBooth version"))
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

            // 3. swap: the running copy goes to the Trash (recoverable), the new one takes its place
            let current = Bundle.main.bundleURL
            guard current.pathExtension == "app" else { throw InstallError("not running from an app bundle") }
            var trashed: NSURL?
            try FileManager.default.trashItem(at: current, resultingItemURL: &trashed)
            do {
                try FileManager.default.moveItem(at: newApp, to: current)
            } catch {
                if let t = trashed as URL? { try? FileManager.default.moveItem(at: t, to: current) }   // put the old one back
                throw InstallError(T("沒辦法放進 %@（權限不足？）", "couldn't write to %@ (permissions?)", current.deletingLastPathComponent().path))
            }

            // 4. reopen once this process has quit (quitting saves a take in progress)
            let pid = ProcessInfo.processInfo.processIdentifier
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", current.path]
            try p.run()
            progress.close()
            NSApp.terminate(nil)
        } catch {
            progress.close()
            let a = NSAlert()
            a.messageText = T("沒辦法自動更新", "Couldn't update automatically")
            a.informativeText = (error.localizedDescription) + T("\n\n可以改用手動下載：解壓縮後把 NarrationBooth 拖到「應用程式」。",
                                                               "\n\nYou can download it yourself instead: unzip it and drag NarrationBooth into Applications.")
            a.addButton(withTitle: T("下載", "Download"))
            a.addButton(withTitle: T("稍後", "Later"))
            if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(rel.download ?? rel.html_url) }
        }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw InstallError("\((tool as NSString).lastPathComponent) failed") }
    }

    @MainActor
    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

/// A small floating window with a spinner while an update downloads and installs.
@MainActor
final class ProgressPanel {
    private let panel: NSPanel
    private let label: NSTextField

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(_ text: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90), styleMask: [.titled, .hudWindow, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "NarrationBooth"
        label = NSTextField(labelWithString: text)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let stack = NSStackView(views: [spinner, label])
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        panel.contentView = stack
        panel.center()
        panel.isFloatingPanel = true
        panel.orderFrontRegardless()
    }

    func close() { panel.close() }
}
