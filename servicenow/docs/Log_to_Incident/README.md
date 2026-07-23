# Log to Incident

Prescriptive AsciiDoc for the Log to Incident process (business process plus platform implementations). Source: [Log_to_Incident.adoc](Log_to_Incident.adoc).

Kept as **AsciiDoc** (not Markdown) so Graphviz figures and the HTML/PDF export pipeline continue to work.

## Render HTML + PDF

Source listings use **Rouge** (server-side) for HTML and PDF color. Cursor preview uses **highlight.js** via workspace `asciidoc.preview.asciidoctorAttributes`. Install Rouge with `~/repos/myenv/assert_myenv.sh` (or `assert/assert_gems.sh`) if missing.

From the spark-observability repo root:

```bash
.vscode/bin/export-drawio.sh servicenow/docs/Log_to_Incident svg
.vscode/bin/render-adoc.sh servicenow/docs/Log_to_Incident/Log_to_Incident.adoc
```

SVG exports default to an **opaque white** page background (a full-bleed `<rect>` is injected, because CSS `background` on `<svg>` is ignored by many viewers). Pass draw.io’s `-t` / `--transparent` to skip that and keep a transparent background:

```bash
.vscode/bin/export-drawio.sh -t servicenow/docs/Log_to_Incident svg
```

Or **Terminal → Run Task → AsciiDoc: Render HTML + PDF** with `Log_to_Incident.adoc` open.

## Document structure

| Chapter | Role |
|---------|------|
| **Purpose** | Why the process exists |
| **Log to Incident** | Technology-agnostic business process |
| **Using ServiceNow and Dynatrace** | Reference implementation (Steps 0–5) |
| **Appendix A — Legacy and SGO-Dynatrace coexistence** | Connector migration notes |

Companion note (Markdown): [CMDB_Mapping.md](CMDB_Mapping.md) — client vs service Dynatrace + CMDB differences and how they map `incident.cmdb_ci`.

Future chapters **may** add other platform pairs (for example Elastic Stack and ServiceNow) without renaming the process.

## draw.io save (desktop)

draw.io sources (`.drawio`) live as peers of `Log_to_Incident.adoc` in this directory. Exports and Graphviz PNGs from `asciidoctor-diagram` go under **`images/`** (`:imagesoutdir: images` in the `.adoc`). That directory is gitignored; regenerate with the render commands above before reviewing HTML/PDF.

1. Save the diagram in draw.io (**File → Save**).
2. **draw.io desktop:** If **File → Save** does not update the file on disk, use **File → Save As** once to bind the diagram to the repo path. Later **Save** calls work after that.
3. Export SVG (or run `export-drawio.sh` as above), then render the AsciiDoc.
4. Confirm the `.drawio` mtime advanced (`stat` on the file).
5. Close and reopen `Log_to_Incident.pdf` in the viewer (editors often cache open PDFs).
