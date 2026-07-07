# Observability — Service Management Documentation

Technical policy for authoring and maintaining observability and service-management reference documents — including Log to Incident implementations, Dynatrace ↔ ServiceNow mappings, CSDM models, and related prescriptive specifications.

## Summary

This TPG governs a **class of documents** that describe how observability signals (logs, metrics, problems, events) flow into ServiceNow Event Management and ITSM, and how Configuration Items are chosen for alerts and incidents. Examples include `Problem_to_Incident.adoc`, `spark-logs.md`, and sibling specs under `servicenow/docs/`.

Authors **must** produce consistent, citable, prescriptive documentation so implementors can configure applications, Dynatrace, and ServiceNow without ambiguity. Rendered **HTML and PDF** outputs **must** be checked in beside the source `.adoc` after substantive edits so reviewers can diff narrative and layout without running local tooling.

## Purpose

Implementors and standard authors share one vocabulary for:

* **Spark Service-Side Log Pattern** — Kubernetes pod logs; incident CI via **Contains** traversal from pod to Application Service.
* **Spark Client-Side Log Pattern** — host-independent PySpark drivers; incident CI via **log path contract** to a manual logical Application Service.

Older labels such as “Pattern A” / “Pattern B” **must not** be used in new Spark Log to Incident prose; Docker and legacy docs may retain Pattern A/B where already defined in `docker_model.md`.

## Definitions

**Specification** — A numbered configuration excerpt (JSON, properties, YAML, or Graphviz) that defines a deployable or verifiable setting.

**Figure** — A diagram (Graphviz listing block, draw.io export, or embedded SVG) with a descriptive caption; AsciiDoc assigns document-wide sequential figure numbers automatically.

**Key field** — A configuration property whose value directly affects log path matching, entity binding, event text, or incident correlation.

## Roles and Responsibilities

The **Standard Author** must apply these guidelines when editing observability / service-management TPGs and reference implementations.

The **Implementor** must cite specification and figure numbers when opening defects, pull requests, or runbook steps.

## Statements

### 1. Document structure

1.1. The table of contents **must** use `:toclevels: 2` so only **H2** (`==`) and **H3** (`===`) headings appear in the left panel and PDF TOC.

1.2. Each major step **should** state what the **application developer**, **Dynatrace operator**, and **ServiceNow administrator** must configure separately.

1.3. Log to Incident reference documents **must** follow **one shared step flow** (Steps 0–5). Where service-side and client-side patterns diverge, authors **must** place **parallel subsections** adjacent to each other (for example, `==== Log emission` then `===== Service-side` / `===== Client-side`; `==== Incident correlation` then `===== Service-side` / `===== Client-side`).

1.4. Section headers **must** be short and **must not** include parenthetical qualifiers. Elaborations belong in the paragraph immediately following the header (for example, use `==== CMDB model` not `==== CMDB model (enterprise)`).

1.5. Before **every** table, authors **must** include one or two sentences stating the table’s context and what the reader should look for or take away.

1.6. Before **every** figure, authors **must** introduce the figure’s purpose or relevance to the surrounding step.

### 2. Figures and specifications

2.1. Every Graphviz diagram **must** have a descriptive caption line immediately above the listing block. The caption **must not** include a figure number — AsciiDoc auto-numbers figures sequentially.

2.2. Every configuration listing **must** have a unique specification identifier immediately above the block, formatted **`Specification {section}-{sequence}`**.

2.3. Authors **must** cross-reference related specifications in prose.

2.4. CMDB relationship figures **must** include a legend explaining line styles in one or two words each.

2.5. Graphviz node identifiers **must not** use reserved DOT keywords; use descriptive names such as `K8S_NODE` or `LAB3_HOST`.

### 3. Diagram assets and layout

3.1. **draw.io sources** (`.drawio`) **must** live as **peers** of the document `.adoc` file (same directory). The legacy `figures/` subtree is **deprecated** — do not add `.drawio` files there. `export-drawio.sh` exports only `*.drawio` in the document directory itself (`maxdepth 1`).

3.2. Exported raster/vector assets (SVG, PNG from draw.io; PNG from Graphviz via asciidoctor-diagram) **must** live under an **`images/`** subdirectory beside the document. The **`images/`** directory **may** be gitignored when assets are reproducible from `.drawio` / Graphviz sources; authors **must** re-export before checking in HTML/PDF.

3.3. **HTML and PDF** renderings (`Problem_to_Incident.html`, `Problem_to_Incident.pdf`, etc.) **must** be committed after substantive documentation changes so review does not require local Graphviz or draw.io.

3.4. Export draw.io before HTML/PDF build (from repo root `spark-observability`):

```bash
.vscode/bin/export-drawio.sh servicenow/docs/Problem_to_Incident svg
.vscode/bin/render-adoc.sh servicenow/docs/Problem_to_Incident/Problem_to_Incident.adoc
```

3.5. AsciiDoc does **not** read native draw.io files. Embed exports with `image::images/{name}.svg[...]`.

3.6. Other ASCII-friendly tools (**PlantUML**, **D2**, **Mermaid**) support limited manual positioning; none match draw.io for multi-group CMDB layouts. Prefer draw.io when aesthetics dominate and Graphviz when auto-layout suffices.

3.7. **Publication-quality diagrams (draw.io)** — For fixed layout and readable CMDB figures:

* Author `.drawio` beside the `.adoc` document.
* Export to `images/*.svg` via `export-drawio.sh`.
* Embed with `image::images/{basename}.svg[Caption,width=100%,align=center]`.
* `render-adoc.sh` runs `export-drawio.sh` automatically when `.drawio` files exist in the document directory.

### 4. Diagram typography

4.1. End-to-end flow figures **should** use vertical layout (`rankdir=TB`).

4.2. End-to-end flow figures **should** use tight vertical spacing (`ranksep` **0.18–0.25**, `nodesep` **0.12–0.18**).

4.3. End-to-end flow edge labels **must** be single-line; use horizontal labels (`labelangle=0`, adequate `labeldistance`) placed **outside** node boxes — not stacked multi-line labels when horizontal space exists.

4.4. End-to-end flow node `height` **0.26–0.30** and `width` **2.0–2.4** when `fixedsize=true`.

4.5. CMDB and correlation figures **may** use **8–9pt** node labels when node text spans multiple CMDB class lines.

4.6. **Preview (Kroki)** and **export (local Graphviz)** use different renderers — layout will differ; use `render-adoc.sh` for WYSIWYG with PDF/HTML.

### 5. Tables and listings

5.1. Configuration listing font size **must** be **8pt** net in all output formats (`:listing-font-size: 8`, theme `code.font_size: 8`, `docinfo` CSS).

5.2. Table body and header font size **must** be **9pt** in HTML, PDF, and preview via `docinfo/docinfo.html` and theme `table.font_size: 9`.

5.3. Cross-references **must** use explicit reftext: `<<anchor-id,Display text>>` so preview and PDF show readable link text even when the anchor is forward-referenced. Place block anchors on section titles: `==== Section title [#anchor-id]` or `[#anchor-id]` immediately above the heading.

5.4. **Cursor / Kroki preview** may show **undefined** cross-reference links for forward references or when the preview engine is not full Asciidoctor; **PDF/HTML export via `render-adoc.sh`** is authoritative.

5.5. Each specification **must** include a **Key fields** line naming match clauses, path patterns, and extracted attributes in **bold**.

5.6. Graphviz export filenames **must** use the diagram caption as the `[graphviz]` block `target` attribute, with spaces replaced by underscores.

### 6. Application and correlation design

6.1. Log to Incident design **must** begin with **application log design**: log file path layout, message text, and correlation granularity.

6.2. ServiceNow **`message_key`** **must** be chosen at application or OpenPipeline design time; document the chosen granularity (per-pod vs global vs client instance).

6.3. Lab log problems **should** include the **pod name** or **client path key** in Davis `event.name` and in ServiceNow **`message_key`** so unrelated workloads are not correlated into one problem.

6.4. Auto-created log incidents **must** use short description **`Event Log WARN`** or **`Event Log ERROR`**, not generic labels such as “Log Errors”.

6.5. ServiceNow Script Includes and business rules **must not** use workload-specific names; use pattern names such as **`K8sLogPodCiBind`**.

6.6. **`em_event.cmdb_ci`** / **`em_alert.cmdb_ci`** bind to infrastructure CIs (pod, HOST, process). **`incident.cmdb_ci`** **must** bind to **`cmdb_ci_service_discovered`** (Application Service).

6.7. Document **known limitations** explicitly (for example, Davis problem bundling) in a dedicated subsection with enough detail for later remediation.

### 7. CMDB model figures

7.1. CMDB figures **should** focus on **one scenario** at a time.

7.2. CMDB figures **must** show CSDM objects from **`*.csdm.yaml`** distinct from discovered / SGC-imported CIs.

7.3. CMDB figures **must** include only Dynatrace entity types materialized in ServiceNow.

7.4. Event Management and ITSM objects **must** use rectangle shape and a distinct fill color from CMDB/CSDM nodes.

## Commentary

Specification numbering enables precise review comments. Figure auto-numbering avoids duplicate captions. Checking in HTML/PDF trades repository size for reviewability; regenerate with `render-adoc.sh` whenever `.adoc`, `.drawio`, or theme/CSS changes.

## References

1. link:Problem_to_Incident.adoc[Problem to Incident reference implementation]
2. link:../../../meta-standards/tpgs-for-tpgs.md[TPGs for TPGs — meta-standard]
3. link:../../../docs/Log_Architecture.md[Log architecture — NFS permissions]
