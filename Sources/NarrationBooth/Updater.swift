import AppKit
import Foundation

/// Checks GitHub Releases for a newer version: once a day at launch (quietly) and from the app menu.
/// A newer release shows its notes and a Download button that opens the release's .zip (or the release page).
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
        var download: URL? {
            assets.first { $0.name.lowercased().hasSuffix(".zip") }?.browser_download_url
                ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
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
            + T("\n\n下載後打開 ZIP，把 NarrationBooth 拖到「應用程式」資料夾取代舊版（第一次一樣要到「隱私權與安全性」按「強制打開」）。",
                "\n\nUnzip the download and drag NarrationBooth into Applications to replace this version (then allow it once under Privacy & Security → Open Anyway).")
        a.addButton(withTitle: T("下載", "Download"))
        a.addButton(withTitle: T("稍後", "Later"))
        a.addButton(withTitle: T("略過這個版本", "Skip This Version"))
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(rel.download ?? rel.html_url)
        case .alertThirdButtonReturn: UserDefaults.standard.set(rel.version, forKey: skippedKey)
        default: break
        }
    }

    @MainActor
    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
