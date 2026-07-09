# ServiceNow documentation (AsciiDoc)

## Integrated preview in Cursor (side panel)

The **AsciiDoc** extension renders `[graphviz]` diagrams in **AsciiDoc: Open Preview to the Side** via [Kroki](https://kroki.io) (diagram source is sent to kroki.io; curl to kroki.io must return 200).

Requirements:

1. Extension **AsciiDoc** (`asciidoctor.asciidoctor-vscode`) installed.
2. **Kroki enabled** — set in user settings (`~/myenv/dotfiles/cursor/settings.json`, synced by `assert_myenv.sh`) and in `spark-observability/.vscode/settings.json`.
3. Diagram blocks use **`----`** listing delimiters (not `....`).
4. **Reload Cursor window** after settings change (Kroki registers at extension startup).
5. Command Palette → **AsciiDoc: Open Preview to the Side** → then **AsciiDoc: Refresh Preview** after edits.

If preview still shows raw `digraph {` text, Kroki is not active — reload the window and confirm `asciidoc.extensions.enableKroki` is `true` in **Cursor Settings → AsciiDoc → Extensions**.

**Preview vs PDF layout:** side preview sends `[graphviz]` blocks to **Kroki** (remote). **HTML/PDF export** uses **local Graphviz** via `asciidoctor-diagram`. Diagram layout and label placement will differ. Use the CLI render below for WYSIWYG with exported PDF. To align preview with export, set `"asciidoc.extensions.enableKroki": false` (requires local `dot`).

**Listing and table font size:** `:listing-font-size: 8` and theme `table.font_size: 9` affect PDF; HTML export uses `docinfo/docinfo.html`; preview listing/table sizing uses `docinfo/docinfo.css` via `asciidoc.preview.additionalStyles`. Re-export after changing either.

**Inline code in dark preview:** `asciidoc.preview.additionalStyles` must be **plain CSS** files (the extension injects them as `<link rel="stylesheet">` — HTML/`<style>` wrappers are ignored). Use `.vscode/asciidoc-preview.css` so backtick literals use `--vscode-editor-foreground` on Cursor Dark / High Contrast. After changing it: reload the window, then **AsciiDoc: Refresh Preview**.

## Export PDF from Cursor

**AsciiDoc: Export PDF** must run `asciidoctor-pdf` with `-r asciidoctor-diagram`. Configured via:

- User settings: `asciidoc.pdf.asciidoctorPdfCommandArgs`: `["-r", "asciidoctor-diagram"]`
- Repo wrapper: `.vscode/bin/asciidoctor-pdf-with-diagrams.sh` (when `spark-observability` is the workspace folder)

After changing settings: **reload window**, then export again. PDF must **not** contain `digraph` source lines.

## CLI render (any `.adoc` in this repo)

```bash
.vscode/bin/render-adoc.sh path/to/document.adoc
```

Or **Terminal → Run Task → AsciiDoc: Render HTML + PDF** with an `.adoc` file open.

Paths are relative to the **spark-observability** repo root (not the parent `repos/` directory).

Toolchain: `~/repos/myenv/assert_myenv.sh` (asciidoctor, asciidoctor-pdf, asciidoctor-diagram, graphviz).

## Problem to Incident

See [Problem_to_Incident/Problem_to_Incident.adoc](Problem_to_Incident/Problem_to_Incident.adoc).
