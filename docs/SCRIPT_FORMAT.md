# NarrationBooth script format

NarrationBooth reads plain-text scripts (`.txt` or `.md`, UTF-8). A script is a list of **blocks**, and each block is a
list of sentences. However you record (one sentence, one block or the whole script per take), every block ends up as
one file, `VO_<name>.wav` (plus `VO_<name>.mov` in camera mode).

Start from the template: [`examples/template.txt`](../examples/template.txt), or in the app
**Help → Save Script Template…**.

[中文說明在下面](#中文說明)

## Example

```text
# Why the sky is blue
// Notes for yourself start with // and never show up while recording.

## 01 Opening

VO_01a
Hi everyone / welcome back to the channel.
Today we're looking at why the sky is blue.

VO_01b
It sounds like a simple question / but the answer goes back to 1871.

## 02 Main part

VO_02a
Sunlight looks white / but it's really every colour mixed together.
```

This gives three files, `VO_01a.wav`, `VO_01b.wav` and `VO_02a.wav`, listed under "01 Opening" and "02 Main part".
In the default one-sentence-per-take mode it is four takes (VO_01a has two sentences), joined automatically at the end.

## Rules

| Line | Meaning |
|---|---|
| `VO_<name>` | Starts a block. Put it **on its own line**. `**VO_<name>**` (Markdown bold) also works. |
| any other text | A sentence of the current block. Write **one sentence per line**: each line is one take in one-sentence-per-take mode and one step of the prompter. |
| ` / ` or `／` | A **breath mark** inside a sentence, highlighted in the prompter. ASCII slash needs a space on both sides (`a / b`), so URLs and dates like `24/7` are left alone. |
| `# Title` | The script's title. Ignored by the prompter. |
| `## Section` / `### Section` | A section heading. Groups the blocks that follow it in the left-hand list. |
| `// note` | A note for you. Never shown. |
| blank line | Ignored (use it to keep the file readable). |
| anything before the first `VO_` line | Ignored, so instructions or notes can go at the top. |

### Block names

- Allowed characters: letters `A–Z a–z`, digits `0–9`, `_` and `-`. No spaces.
  Good: `01a`, `02b`, `intro`, `outro-2`, `scene_3`. Not allowed: `01 a`, `開場`, `#1`.
- Every name must be **unique** in the file. The app refuses a script with duplicate names, because the takes would
  overwrite each other.
- Names sort the way you write them; the recording order is the order in the file, not alphabetical.
- Tip: number blocks by section (`01a`, `01b`, `02a` …) so you can add a block later without renaming the rest.

### Files without any `VO_` line

Also accepted: every paragraph (text separated by a blank line) becomes a block, named `001`, `002`, `003` … in order.
Handy for quick reads, but naming your blocks is better for editing.

### Common mistakes

| Problem | Fix |
|---|---|
| "No lines to read in this script" | A `VO_` line needs at least one sentence under it, and the `VO_` line must be on its own. |
| A block shows two sentences on one row | Put each sentence on a new line. |
| Breath mark not highlighted | Use `／`, or put spaces around the ASCII slash: ` / `. |
| "Duplicate block names" | Rename one of them; each `VO_` name must be different. |
| Garbled characters | Save the file as UTF-8 (TextEdit: Format → Make Plain Text, then save as UTF-8). |

## What you get

```text
<output folder>/<script name>_recordings/
├── VO_01a.wav             WAV, 48 kHz, 24-bit, mono, unprocessed (takes joined)
├── VO_01a.mov             camera mode only (HEVC)
├── VO_01b.wav
├── <script name>_full.wav the whole script in one file
├── takes/                 the raw takes the files above are made from
├── _old_takes/            earlier takes of anything you re-recorded (never deleted)
└── session.json           length, peak level and clipping flag of each take
```

---

## 中文說明

NarrationBooth 讀純文字稿（`.txt` 或 `.md`，UTF-8 編碼）。稿子由很多**段落（block）**組成，每段有好幾句。不管你選一句一錄、一段一錄還是整份一次錄，最後**每一段都會合併成一個檔案**：`VO_<名稱>.wav`（鏡頭模式另外有 `VO_<名稱>.mov`），另外還有整份的 `<稿子名>_full.wav`。

可以直接從範本開始：[`examples/template.txt`](../examples/template.txt)，或在 App 選單 **Help → Save Script Template…** 存一份。

### 範例

```text
# 為什麼天空是藍的
// 兩個斜線開頭是你自己的備註，錄音時不會顯示。

## 01 開場

VO_01a
哈囉大家好 / 歡迎回到我的頻道。
今天要來講天空為什麼是藍的。

VO_01b
聽起來很簡單 ／ 但答案要從 1871 年講起。
```

這樣會錄出 `VO_01a.wav`、`VO_01b.wav` 兩個檔，在左邊清單的「01 開場」底下。

### 規則

| 寫法 | 意思 |
|---|---|
| `VO_<名稱>` | 開始一段，**要自己一行**。寫成粗體 `**VO_<名稱>**` 也可以。 |
| 其他文字 | 這一段的句子。**一句一行**：一句一錄模式下，一行就是一次錄音。 |
| ` / ` 或 `／` | **換氣記號**，在提詞畫面會變色。半形斜線前後要有空格（`a / b`），所以網址或 `24/7` 不會被誤認。 |
| `# 標題` | 整份稿子的標題，提詞時不顯示。 |
| `## 分區` / `### 分區` | 分區標題，把後面的段落分組顯示在左邊清單。 |
| `// 備註` | 你自己的備註，不會顯示。 |
| 空白行 | 不影響，可以讓檔案好讀。 |
| 第一個 `VO_` 之前的所有內容 | 全部略過，可以放說明或筆記。 |

### 段落名稱

- 只能用英文字母、數字、`_`、`-`，不能有空格。可以：`01a`、`02b`、`intro`、`outro-2`。不行：`01 a`、`開場`、`#1`。
- 同一份稿子裡**名稱不能重複**，不然錄音檔會互相覆蓋，App 會直接提醒你。
- 錄音順序就是稿子裡由上到下的順序。
- 建議照分區編號（`01a`、`01b`、`02a`…），之後要插一段也不用全部改名。

### 沒有寫 `VO_` 的檔案

也能讀：每一段文字（用空白行隔開）自動變成一段，依序叫 `001`、`002`、`003`…。適合隨手唸，但要剪片的話還是自己取名比較好找。

### 常見問題

| 狀況 | 解法 |
|---|---|
| 「這份稿子裡找不到要唸的段落」 | `VO_` 那行要自己一行，底下至少要有一句。 |
| 兩句擠在同一行 | 每一句換行。 |
| 換氣記號沒變色 | 用全形「／」，或半形斜線前後加空格「 / 」。 |
| 「段落名稱重複」 | 把其中一個改名，每個 `VO_` 名稱都要不一樣。 |
| 出現亂碼 | 用 UTF-8 存檔（文字編輯：格式 → 製作純文字，存檔時選 UTF-8）。 |
