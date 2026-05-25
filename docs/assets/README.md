# README image assets

The repo README references three images here. Until they exist, GitHub will render the alt-text. Drop these in (any aspect ratio that looks good — the README hints sizes):

| File | What it should show | Suggested dimensions |
|---|---|---|
| `banner.png` | Project banner / logo. The padlock-and-config aesthetic ("safe to paste your secrets") works well. Plain wordmark also fine. | 1440×360 (rendered at 720 wide) |
| `demo.gif` | Animated terminal capture of `fofoconfig edit <path>` running through a real edit: diff renders → `y/N` prompt → `.fofobak` written → file modified. ~15–25 seconds. Use [vhs](https://github.com/charmbracelet/vhs) or [asciinema-agg](https://github.com/asciinema/agg) for crisp output. | 1600×800 (rendered at 800 wide) |
| `architecture.png` | Visual of the architecture box-and-arrow diagram already in the README (launcher → ACP client → hermes acp → operator endpoint). Either a clean exported diagram (excalidraw / draw.io) or a styled version of the ASCII layout. | 1440×720 (rendered at 720 wide) |

Until images exist, the alt-text and the ASCII architecture block in the README still tell the whole story.
