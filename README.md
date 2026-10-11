# NarrationBooth

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
- **Teleprompter.** Big text, one sentence per line, breath marks (`／`) highlighted, the next block shown underneath. In camera mode the text sits at the top of the screen, close to the lens.
- **Level meter that tells you what to do.** "Too quiet: move closer", "Clipping! Lower the input level". A green zone shows where speech peaks should land (−20 to −6 dBFS).
- **Room-noise check.** Three seconds of silence tells you whether the room is quiet enough.
- **Mic picker and input level**, including USB / audio-interface mics and an iPhone used as a Continuity mic or camera.
- **Retakes never destroy anything.** Re-record a block and the old take moves to `_old_takes/`.
- **Resumable.** Close the app and open the same script later; it picks up at the first block you haven't recorded.

## Requirements

- macOS 14 Sonoma or later, Apple silicon or Intel
- Xcode 16+ or the Swift 6 toolchain (only to build it)

## Build and run

```bash
git clone https://github.com/nashwu0117/NarrationBooth.git
cd NarrationBooth
Scripts/package_app.sh          # builds the app: NarrationBooth.app
open NarrationBooth.app
```

`INSTALL=1 Scripts/package_app.sh` also copies the app to `/Applications`.
The app is signed ad hoc for local use. The first launch asks for microphone (and, in camera mode, camera) access.
If you rebuild, macOS may ask again.

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

Recordings go to `~/Downloads/<script name>_recordings/` unless you pick another folder. Each folder holds
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
- **鏡頭模式**：邊看稿邊對鏡頭講，同時錄 `VO_01a.mov`（HEVC，鏡頭支援就 4K，否則 1080p），和聲音檔同時開始。
- **提詞**：大字、一句一行，「／」換氣記號用顏色標出來，下面預告下一段；鏡頭模式下稿子在螢幕上方，眼睛比較靠近鏡頭。
- **會告訴你怎麼調的音量表**：「太小聲：靠近一點」「爆音了！調低輸入音量」，綠色區就是講話時峰值該停的位置。
- **測環境噪音**、**選麥克風／調輸入音量**（支援 USB 麥克風、錄音介面、iPhone 當麥克風或鏡頭）。
- **重錄不會蓋掉舊的**：舊的那次會移到 `_old_takes/`。
- **可以接著錄**：下次打開同一份稿子，會從還沒錄的那段開始。

編譯方式見上面的 *Build and run*。介面預設英文，可以從選單「Language → 繁體中文」切換。

## License

[MIT](LICENSE) © 2026 Nash Wu
