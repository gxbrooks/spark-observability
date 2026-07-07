# Problem to Incident

Prescriptive AsciiDoc for the Log to Incident flow. Source: [Problem_to_Incident.adoc](Problem_to_Incident.adoc).

Rendering and preview are documented in [../README.md](../README.md) (repo-wide; not per-document scripts).

## draw.io diagrams

| Role | Path |
|------|------|
| Source (edit here) | `spark-csdm-cmdb-model.drawio`, `Grafana ServiceNow Model.drawio` (peers of this `.adoc`) |
| Export (generated) | `images/*.svg` (gitignored; rebuilt by render) |
| Embed in adoc | `image::images/{basename}.svg[...]` |

From repo root (`spark-observability`):

```bash
.vscode/bin/export-drawio.sh servicenow/docs/Problem_to_Incident svg
.vscode/bin/render-adoc.sh servicenow/docs/Problem_to_Incident/Problem_to_Incident.adoc
```

The legacy `figures/` directory is deprecated; do not save diagrams there.

### Troubleshooting stale diagrams in HTML/PDF

`render-adoc.sh` exports **only what is saved on disk** at:

`servicenow/docs/Problem_to_Incident/spark-csdm-cmdb-model.drawio`

If the PDF or HTML shows an old diagram:

1. **Save the `.drawio` file** in your editor (draw.io / VS Code). Unsaved buffer changes are not exported.
2. **draw.io desktop:** If **File → Save** does not update the file on disk, use **File → Save As** once to bind the diagram to the repo path (`servicenow/docs/Problem_to_Incident/spark-csdm-cmdb-model.drawio`). Later **Save** calls work after that. This often happens when the diagram was opened from a recent-file list, a copy, or another app without a resolved path.
3. Confirm the source timestamp updated:
   `stat servicenow/docs/Problem_to_Incident/spark-csdm-cmdb-model.drawio`
4. Re-run `.vscode/bin/render-adoc.sh …` and check the log for `exporter=drawio-cli` and a fresh `source mtime=`.
5. Close and reopen `Problem_to_Incident.pdf` in the viewer (editors often cache open PDFs).

Exports land in `images/*.svg` (gitignored). HTML and PDF both embed that SVG at build time.
