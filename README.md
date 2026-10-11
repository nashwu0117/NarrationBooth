<p align="center"><img src="docs/icon.png" width="160" alt="NarrationBooth icon"></p>

<h1 align="center">NarrationBooth</h1>

A teleprompter recorder for Mac, made for voice-over and talking-head videos (explainers, tutorials, travel vlogs).
Open your script, read one block at a time, and every take is saved as a clean, studio-quality file that is ready to edit.

![NarrationBooth](docs/screenshot.jpg)

## Why

Recording narration with a phone voice memo works, until you edit it: one long file, a 16 kHz compressed format,
stray pauses, retakes buried in the middle, and no way of knowing your level until it's too late.
NarrationBooth records the way editors want it:

- **One file per script block.** `VO_01a.wav`, `VO_01b.wav`… named after the block, so they drop straight into your edit.
- **Studio format.** WAV, 48 kHz, 24-bit, mono, with no processing, no auto-gain and no noise suppression. You get exactly what the mic hears.
- **Camera mode.** Record yourself on camera while reading. Each take also saves `VO_01a.mov` (HEVC, 4K when the camera supports it, 1080p otherwise), starting together with the WAV.
- **Teleprompter.** Big text, one sentence per line, breath marks (`／`) highlighted, the next block shown underneath.
- **Eye contact in camera mode.** The window goes full screen and the script becomes a narrow, centred column right under the built-in camera, so reading looks like looking into the lens. (If you keep the window smaller, the text still shifts toward the camera.)
- **Level meter that tells you what to do.** "Too quiet: move closer", "Clipping! Lower the input level". A green zone shows where speech peaks should land (−20 to −6 dBFS).
- **Room-noise check.** Three seconds of silence tells you whether the room is quiet enough.
- **Mic picker and input level**, including USB / audio-interface mics and an iPhone used as a Continuity mic or camera.
- **Retakes never destroy anything.** Re-record a block and the old take moves to `_old_takes/`.
- **Resumable.** Close the app and open the same script later; it picks up at the first block you haven't recorded.

## Download

Get the latest **NarrationBooth-x.y.z.dmg** from [Releases](https://github.com/nashwu0117/NarrationBooth/releases/latest),
open it, and drag **NarrationBooth** onto the **Applications** folder next to it.

> **First launch (one time):** NarrationBooth isn't signed with an Apple developer certificate, so macOS blocks it the
> first time. To allow it:
> 1. Open NarrationBooth from Applications. macOS says it can't be opened; click **Done** (or **OK**).
> 2. Open **System Settings → Privacy & Security**, scroll down to **Security**, and next to
>    *"NarrationBooth" was blocked…* click **Open Anyway**. Confirm with your password, then click **Open Anyway** again.
>
> From then on it opens normally. (Terminal alternative: `xattr -dr com.apple.quarantine /Applications/NarrationBooth.app`)

### Updates

NarrationBooth checks GitHub for a new release once a day (and from **NarrationBooth → Check for Updates…**).
When there is one, it shows what changed and a **Download** button; open the new DMG and drag the app onto
Applications to replace the old one. Your settings and recordings are kept.

## Requirements

- macOS 14 Sonoma or later, Apple silicon or Intel
- Xcode 16+ or the Swift 6 toolchain (only to build it)

## Build from source

```bash
git clone https://github.com/nashwu0117/NarrationBooth.git
cd NarrationBooth
Scripts/package_app.sh          # builds the app: NarrationBooth.app
open NarrationBooth.app
```

`INSTALL=1 Scripts/package_app.sh` also copies the app to `/Applications`.
Local builds are signed with your *Apple Development* identity when you have one (so macOS keeps the microphone
and camera permission across rebuilds), otherwise ad hoc.
The first launch asks for microphone (and, in camera mode, camera) access.

### Releasing (maintainers)

```bash
Scripts/release.sh 1.1.0 "What changed"   # bump version, build, make the DMG, tag, push, publish the GitHub release
```

`Scripts/make_dmg.sh` builds `dist/NarrationBooth-<version>.dmg`. Release builds are signed ad hoc, so downloads
carry no personal certificate; users allow the app once under Privacy & Security (see *Download*).

## Writing a script

Plain `.txt` or `.md`. Mark each recording block with a line `VO_<name>` (bold is fine: `**VO_01a**`), then put
one sentence per line underneath. Headings (`# …`) become section labels. Anything above the first `VO_` line is
ignored, so you can keep notes there. See [`examples/sample_script.md`](examples/sample_script.md).

```markdown
## 01 Opening

**VO_01a**

Hi everyone ／ welcome back to the channel.
Today we're looking at why the sky is blue.

**VO_01b**

It sounds like a simple question ／ but the answer goes all the way back to 1871.
```

A file without any `VO_` markers also works: every paragraph becomes a block (`001`, `002`, …).

## Recording

| Key | Action |
|---|---|
| Space | Start recording the current block / stop and move to the next |
| ← → | Previous / next block |
| P | Play the current take |
| ⌘O | Open a script |
| ⇧⌘O | Choose the output folder |

Pick where recordings go with the **folder button** in the top bar (remembered between launches; default `~/Downloads`).
Each script gets its own `<script name>_recordings/` folder there, holding
`VO_<name>.wav` (+ `.mov`), `_old_takes/` and a `session.json` with the length, peak level and clipping flag of each take.

Tips: speak at your normal pace, keep peaks in the green zone, and if you stumble, just press Space twice
(stop, then record again) to redo that block.

## Language

The interface is in English. Traditional Chinese is available from the **Language** menu (relaunch to apply).

---

## 中文說明

給 Mac 用的提詞錄音工具，適合錄旁白和真人出鏡的知識型影片。打開稿子，一段一段唸，每段都存成可以直接剪的高音質檔案。

- **一段一個檔**：`VO_01a.wav`、`VO_01b.wav`……直接用段落代號命名。
- **錄音室規格**：WAV 48 kHz、24-bit、單聲道，不做任何處理（沒有自動增益、沒有降噪），錄到的就是麥克風聽到的。
- **鏡頭模式**：邊看稿邊對鏡頭講，同時錄 `VO_01a.mov`（HEVC，鏡頭支援就 4K，否則 1080p），和聲音檔同時開始。視窗會全螢幕，稿子縮成窄欄放在鏡頭正下方，唸稿時看起來就像在看鏡頭。
- **提詞**：大字、一句一行，「／」換氣記號用顏色標出來，下面預告下一段。
- **選存檔位置**：上方的資料夾按鈕可以選錄音存在哪裡，會記住你的選擇（預設是「下載」）。
- **會告訴你怎麼調的音量表**：「太小聲：靠近一點」「爆音了！調低輸入音量」，綠色區就是講話時峰值該停的位置。
- **測環境噪音**、**選麥克風／調輸入音量**（支援 USB 麥克風、錄音介面、iPhone 當麥克風或鏡頭）。
- **重錄不會蓋掉舊的**：舊的那次會移到 `_old_takes/`。
- **可以接著錄**：下次打開同一份稿子，會從還沒錄的那段開始。

**下載安裝**：到 [Releases](https://github.com/nashwu0117/NarrationBooth/releases/latest) 下載 `NarrationBooth-x.y.z.dmg`，打開後把 NarrationBooth 拖到旁邊的「應用程式」資料夾。
**第一次打開（只要一次）**：這個 App 沒有用 Apple 開發者憑證簽章，所以 macOS 第一次會擋下來：
1. 從「應用程式」打開 NarrationBooth，出現「無法打開」時按「完成」。
2. 打開「系統設定 → 隱私權與安全性」，往下捲到「安全性」，在「已阻擋 NarrationBooth…」旁邊按**強制打開**（或「仍要打開」），輸入密碼後再按一次**強制打開**。

之後就能正常打開。（也可以在終端機執行 `xattr -dr com.apple.quarantine /Applications/NarrationBooth.app`）

**自動更新**：App 每天會檢查一次 GitHub 有沒有新版本（也可以從選單「Check for Updates…」手動檢查），有新版會顯示更新內容和下載按鈕，下載後一樣拖進「應用程式」取代舊版，設定和錄音都會保留。

介面預設英文，可以從選單「Language → 繁體中文」切換。

## License

[MIT](LICENSE) © 2026 Nash Wu
