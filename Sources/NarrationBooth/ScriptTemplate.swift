import Foundation

/// Starter script written by Help → Save Script Template… (same text as examples/template.txt).
enum ScriptTemplate {
    static let guideURL = URL(string: "https://github.com/nashwu0117/NarrationBooth/blob/main/docs/SCRIPT_FORMAT.md")!

    static let text = """
    # My Video Title
    // NarrationBooth script. Lines starting with // are notes for you; they don't show up while recording.
    // Each block starts with a line VO_<name> and becomes one file, VO_<name>.wav
    // <name> can use letters, numbers, _ and -, and must be unique (01a, 01b, intro, outro-2 ...).
    // Write one sentence per line (in one-sentence-per-take mode each line is one take). Put " / " (or 「／」) where you want to take a breath.
    // ## lines group blocks into sections.

    ## 01 Opening

    VO_01a
    Hi everyone / welcome back to the channel.
    Today we're looking at why the sky is blue.

    VO_01b
    It sounds like a simple question / but the answer goes back to 1871.

    ## 02 Main part

    VO_02a
    Sunlight looks white / but it's really every colour mixed together.
    When it hits the air / the blue part gets scattered the most.

    VO_02b
    中文也可以 / 一句一行。
    「／」和前後有空格的半形斜線都是換氣記號。

    ## 03 Ending

    VO_03a
    That's it for today / see you next time.

    """
}
