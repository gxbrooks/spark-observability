# Problem to Incident — documentation guidelines

Technical policy for authoring and maintaining `Problem_to_Incident.adoc` and related Log to Incident specifications.

## Purpose

Authors and implementors must produce consistent, citable, prescriptive documentation for the Log to Incident reference implementation so developers can configure applications, Dynatrace, and ServiceNow without ambiguity.

## Definitions

**Specification** — A numbered configuration excerpt (JSON, properties, YAML, or Graphviz) that defines a deployable or verifiable setting.

**Figure** — A diagram (Graphviz listing block) with a descriptive caption; AsciiDoc assigns document-wide sequential figure numbers automatically.

**Key field** — A configuration property whose value directly affects log path matching, entity binding, event text, or incident correlation.

## Roles and Responsibilities

The **Standard Author** must apply these guidelines when editing `Problem_to_Incident.adoc` or sibling specs.

The **Implementor** must cite specification and figure numbers when opening defects, pull requests, or runbook steps.

## Statements

### 1. Document structure

1.1. The table of contents **must** use `:toclevels: 2` so only **H2** (`==`) and **H3** (`===`) headings appear in the left panel and PDF TOC.

1.2. Each major step **should** state what the **application developer**, **Dynatrace operator**, and **ServiceNow administrator** must configure separately.

### 2. Figures and specifications

2.1. Every Graphviz diagram **must** have a descriptive caption line immediately above the listing block (for example, `.Log to Incident end-to-end data flow`). The caption **must not** include a figure number — AsciiDoc auto-numbers figures sequentially (Figure 1, Figure 2, …) across the document.

2.2. Every configuration listing **must** have a unique specification identifier immediately above the block, formatted **`Specification {section}-{sequence}`** (for example, `Specification 2.5.4-1`).

2.3. Authors **must** cross-reference related specifications in prose (for example, Log4j `filePattern` **must** match Dynatrace custom log source path patterns in the cited specification).

2.4. CMDB relationship figures **must** include a legend explaining line styles in one or two words each.

2.5. Graphviz node identifiers **must not** use reserved DOT keywords (for example `NODE`, `graph`, `edge`); use descriptive names such as `K8S_NODE` or `LAB3_HOST`.

### 3. Diagram typography

3.1. End-to-end flow figures **should** use vertical layout (`rankdir=TB`).

3.2. End-to-end flow edge labels **should** use `labelangle=-90` and `labeldistance` large enough for one em dash of separation from the arrow shaft.

3.3. End-to-end flow figures in `Problem_to_Incident.adoc` **should** use Graphviz `fontsize` **9–10** on nodes and edges (graph-level **10**), with process-step node `height` **0.28–0.32** and `width` **1.8–2.2** when `fixedsize=true`, so ovals fit label height without excess padding.

3.4. The minimum readable node label size for HTML/PDF output is **8pt**; the recommended default for end-to-end flow diagrams is **9pt** nodes / **10pt** graph title.

3.5. CMDB and correlation figures **may** use **8–9pt** node labels when node text spans multiple CMDB class lines.

### 4. Configuration listings

4.1. Configuration listing font size **must** be **7pt** net in all output formats:

* **PDF:** `:listing-font-size: 7` plus custom theme `servicenow/docs/styles/problem-to-incident-theme.yml` (`code.font_size: 7`).
* **HTML:** `:docinfo:` with `docinfo/docinfo.html` beside the document (CSS targeting `.listingblock pre` at **7pt**). The `:listing-font-size:` attribute alone does **not** affect HTML.
* **Cursor preview:** may scale listings differently from export; use `render-adoc.sh` for WYSIWYG with PDF/HTML.

4.1a. Graphviz diagram node labels **should** use **9pt**; edge labels **should** use **8pt**. **Preview (Kroki)** and **export (local Graphviz)** use different renderers — layout will differ; see Figure 2 NOTE in the reference document.

4.1b. AsciiDoc does **not** read native draw.io (`.drawio`) files. Export to SVG/PNG and embed with `image::`.

4.1c. Graphviz export filenames **must** use the diagram caption as the `target` attribute (second positional on the `[graphviz]` block), with spaces replaced by underscores (for example `[graphviz, Log_to_Incident_end-to-end_data_flow]`). Delete stale `diag-graphviz-md5-*.png` files when regenerating.

4.2. Each specification **must** include a **Key fields** line (or table row) immediately before or after the listing that names match clauses, path patterns, variable substitutions, and extracted attributes in **bold**.

4.3. Prescriptive JSON **should** use inline `// KEY:` comments only when the comment documents a key field called out in the Key fields line.

### 5. Application and correlation design

5.1. The Log to Incident design process **must** begin with **application log design**: log file path layout, message text, and correlation granularity.

5.2. ServiceNow **`message_key`** design **must** be chosen at application or OpenPipeline design time; authors **must** document the chosen granularity (for example, per-pod vs global).

5.3. Lab log problems **should** include the **pod name** in Davis `event.name` and in ServiceNow **`message_key`** prefix (`K8sLog-{pod}-…`) so unrelated pods are not correlated into one problem.

5.4. Auto-created log incidents **must** use short description **`Event Log WARN`** or **`Event Log ERROR`** (derived from the log line or alert severity), not generic labels such as “Log Errors” or workload-specific prefixes.

5.5. ServiceNow Script Includes and business rules **must not** use workload-specific names (for example `SparkLogPodCiBind`); use pattern names such as **`K8sLogPodCiBind`**. See the reference document <<naming-conventions>> section.

5.6. **`em_event.resource`** and **`em_alert.resource`** **should** be the literal log path when the pod name is known (for example `/mnt/spark/logs/{pod}/spark-app.log` in the lab reference implementation).

5.7. **`em_event.cmdb_ci`** and **`em_alert.cmdb_ci`** **must** bind to **`cmdb_ci_kubernetes_pod`** when the log path or Dynatrace entity is a pod; **`incident.cmdb_ci`** **must** bind to **`cmdb_ci_service_discovered`** (Application Service from CSDM), not the pod.

### 6. CMDB model figures

6.1. CMDB figures **should** focus on **one scenario** at a time (for example, Spark Master WARN on `spark-master-0`).

6.2. CMDB figures **must** show CSDM objects created from **`*.csdm.yaml`** (Business Application, Business Service, Application Service) distinct from K8s-discovered and SGC-imported CIs.

6.3. CMDB figures **must** include only Dynatrace entity types **as materialized in ServiceNow** (`sys_object_source` → CMDB class), not abstract Grail-only types.

6.4. Event Management and ITSM objects (`em_event`, `em_alert`, `incident`) **must** use rectangle shape (not rounded) and a distinct fill color from CMDB/CSDM nodes.

## Commentary

Specification numbering enables precise review comments ("update Specification 2.5.4-1 matcher"). Figure auto-numbering avoids duplicate captions such as "Figure 1. Figure 2.2-1".

## References

1. link:Problem_to_Incident.adoc[Problem to Incident reference implementation]
2. link:../../../meta-standards/tpgs-for-tpgs.md[TPGs for TPGs — meta-standard]
3. link:../../../docs/Log_Architecture.md[Log architecture — NFS permissions]
