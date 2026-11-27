#!/usr/bin/env python3
"""Build specifications/servicenow/docs/eShop_Architecture.pptx (native, editable shapes).

Slides: title; synchronous API calls; order process through the event bus; queue readers and
writers; CSDM model; Kubernetes tagging levels; deployment snippets (Catalog API, RabbitMQ).
The diagrams reuse the look of the Claude Desktop renderings: flat 50-stop fills, 600-stop
0.5 pt outlines, 800-stop titles, sentence case, thin grey connectors with open arrowheads.
Code uses VS Code Dark+ colours.

Usage: venv/bin/python specifications/servicenow/docs/tools/build_eshop_architecture_pptx.py [out.pptx]
"""
import re
import sys
from pathlib import Path

from lxml import etree
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.util import Emu, Inches, Pt

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "eShop_Architecture.pptx"
FONT = "Arial"
MONO = "Consolas"

RAMPS = {  # fill (50), stroke (600), title (800), subtitle (600)
    "purple": ("EEEDFE", "534AB7", "3C3489", "534AB7"),
    "teal": ("E1F5EE", "0F6E56", "085041", "0F6E56"),
    "gray": ("F1EFE8", "888780", "2C2C2A", "5F5E5A"),
    "amber": ("FAEEDA", "854F0B", "633806", "854F0B"),
    "coral": ("FAECE7", "993C1D", "712B13", "993C1D"),
}
INK = "2C2C2A"       # primary text
MUTED = "5F5E5A"     # secondary text
LINE = "73726C"      # connector grey (desktop lineColor)
DARK_BG = "26215C"   # purple 900, title slide

prs = Presentation()
prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
BLANK = prs.slide_layouts[6]


def rgb(h):
    return RGBColor.from_string(h)


def text_frame(shape, margin=0.05):
    tf = shape.text_frame
    tf.word_wrap = True
    for side in ("left", "right", "top", "bottom"):
        setattr(tf, f"margin_{side}", Inches(margin))
    return tf


def add_text(slide, x, y, w, h, runs, size=14, color=INK, bold=False, align=PP_ALIGN.LEFT,
             anchor=MSO_ANCHOR.TOP, font=FONT, margin=0.0, name=None):
    """runs: str, or list of paragraphs; a paragraph is a str or a list of (text, {opts})."""
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        tb.name = name
    tf = text_frame(tb, margin)
    tf.vertical_anchor = anchor
    paras = [runs] if isinstance(runs, str) else runs
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        for text, opts in ([(para, {})] if isinstance(para, str) else para):
            r = p.add_run()
            r.text = text
            f = r.font
            f.name = opts.get("font", font)
            f.size = Pt(opts.get("size", size))
            f.bold = opts.get("bold", bold)
            f.italic = opts.get("italic", False)
            f.color.rgb = rgb(opts.get("color", color))
    return tb


def title(slide, text, sub=None):
    add_text(slide, 0.6, 0.35, 12.1, 0.6, text, size=30, bold=True, name="Title")
    if sub:
        add_text(slide, 0.6, 0.95, 12.1, 0.4, sub, size=14, color=MUTED, name="Subtitle")


def box(slide, x, y, w, h, ramp, head, sub=None, head_size=14, sub_size=12, radius=0.08, name=None,
        line_w=0.75, align=PP_ALIGN.CENTER):
    fill, stroke, tcol, scol = RAMPS[ramp]
    s = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    s.adjustments[0] = min(0.5, radius / min(w, h))
    s.fill.solid()
    s.fill.fore_color.rgb = rgb(fill)
    s.line.color.rgb = rgb(stroke)
    s.line.width = Pt(line_w)
    _unstyle(s)
    if name:
        s.name = name
    tf = text_frame(s, 0.06)
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.alignment = align
    r = p.add_run()
    r.text = head
    r.font.name, r.font.size, r.font.bold, r.font.color.rgb = FONT, Pt(head_size), True, rgb(tcol)
    if sub:
        for line in sub.split("\n"):
            p2 = tf.add_paragraph()
            p2.alignment = align
            r2 = p2.add_run()
            r2.text = line
            r2.font.name, r2.font.size, r2.font.color.rgb = FONT, Pt(sub_size), rgb(scol)
    return s


def arrow(slide, x1, y1, x2, y2, color=LINE, width=1.0, head="arrow", dash=None):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    _unstyle(c)
    c.line.color.rgb = rgb(color)
    c.line.width = Pt(width)
    ln = c.line._get_or_add_ln()
    if dash:
        d = etree.SubElement(ln, qn("a:prstDash"))
        d.set("val", dash)
    if head:
        t = etree.SubElement(ln, qn("a:tailEnd"))
        t.set("type", head)
        t.set("w", "med")
        t.set("len", "med")
    return c


def _unstyle(shape):
    """Remove the theme style reference (shadow/effects); colours are set explicitly."""
    st = shape._element.find(qn('p:style'))
    if st is not None:
        shape._element.remove(st)


def notes(slide, text):
    slide.notes_slide.notes_text_frame.text = text


# ---------------------------------------------------------------- 1. Title
s = prs.slides.add_slide(BLANK)
bg = s.background.fill
bg.solid()
bg.fore_color.rgb = rgb(DARK_BG)
add_text(s, 0.8, 2.3, 11.5, 1.0, "eShop on brooks-lab", size=44, bold=True, color="FFFFFF")
add_text(s, 0.8, 3.35, 11.5, 0.6, "Architecture, queues, CSDM model and Kubernetes tagging", size=22, color="CECBF6")
add_text(s, 0.8, 4.3, 11.5, 0.9,
         ["dotnet/eShop on a 3-node kubeadm cluster (Lab1, Lab2 apps; Lab3 shared services)",
          "Observed by Dynatrace (tenant pdt20158) and modelled in ServiceNow (Demo1)"],
         size=16, color="AFA9EC")
notes(s, "Source: dotnet/eShop commit 3c6e531, live RabbitMQ bindings and the brooks-lab CSDM "
         "spec specifications/servicenow/regions/brooks-lab/eshop.csdm.yaml.")

# ---------------------------------------------------------------- 2. Synchronous calls
# Coordinates are the desktop SVG's (680-unit viewBox) scaled to the slide.
SC, X0, Y0 = 0.0128, 2.31, 1.45


def P(x, y):
    return X0 + x * SC, Y0 + y * SC


def sbox(slide, x, y, w, h, ramp, head, sub=None):
    bx, by = P(x, y)
    return box(slide, bx, by, w * SC, h * SC, ramp, head, sub, head_size=13, sub_size=11)


def sarrow(slide, x1, y1, x2, y2):
    a, b = P(x1, y1)
    c, d = P(x2, y2)
    arrow(slide, a, b, c, d)


s = prs.slides.add_slide(BLANK)
title(s, "Synchronous API calls", "HTTP and gRPC between the shopper, the load generator and the eShop APIs")
sbox(s, 150, 30, 160, 44, "gray", "Shopper browser")
sarrow(s, 230, 74, 230, 118)
sbox(s, 150, 120, 160, 56, "purple", "WebApp", "Blazor UI")
sbox(s, 430, 120, 160, 56, "gray", "Load generator", "Synthetic orders")
for x2 in (100, 218, 336, 452):
    sarrow(s, 210 + (x2 - 100) * 40 / 352, 176, x2, 228)
sarrow(s, 490, 176, 230, 228)
sarrow(s, 510, 176, 470, 228)
for i, (h, sub) in enumerate([("Identity API", "identitydb"), ("Catalog API", "catalogdb"),
                              ("Basket API", "gRPC, Redis"), ("Ordering API", "orderingdb"),
                              ("Webhooks API", "webhooksdb")]):
    sbox(s, 39 + i * 122, 230, 114, 56, "purple", h, sub)
sarrow(s, 584, 286, 584, 338)
sbox(s, 464, 340, 176, 44, "teal", "Webhook subscribers")
add_text(s, 0.6, 6.7, 12.1, 0.4,
         "Every API validates JWTs from Identity API. The load generator gets a token from Identity API, "
         "reads the catalog and posts orders; WebApp to Basket API is gRPC.", size=12, color=MUTED)
notes(s, "Order Processor and Payment Processor have no synchronous callers; they work only through "
         "the event bus and orderingdb (next slide).")

# ---------------------------------------------------------------- 3. Order process (sequence)
s = prs.slides.add_slide(BLANK)
title(s, "Order process through the event bus",
      "Exchange eshop_event_bus routes each integration event to the subscriber queues [in brackets]")
actors = ["Load generator", "Ordering API", "Order Processor", "Catalog API", "Payment Processor",
          "Basket, WebApp, Webhooks"]
AX0, AW, AGAP, AY, AH = 0.55, 1.85, 0.2, 1.5, 0.5
cx = []
for i, a in enumerate(actors):
    x = AX0 + i * (AW + AGAP)
    box(s, x, AY, AW, AH, "purple", a, head_size=12)
    cx.append(x + AW / 2)
TOP, ROW = AY + AH + 0.32, 0.345
msgs = [  # (from, to, label, sync) ; ("note", i, j, text)
    (0, 1, "POST /api/orders (HTTP)", True),
    (1, 5, "OrderStarted [Basket] and Submitted [Ordering.webapp]", False),
    ("note", 2, 2, "polls orderingdb for orders past grace period"),
    (2, 1, "GracePeriodConfirmed [Ordering]", False),
    (1, 3, "AwaitingValidation [Catalog]", False),
    (1, 5, "AwaitingValidation [Ordering.webapp]", False),
    (3, 1, "StockConfirmed or StockRejected [Ordering]", False),
    (1, 4, "StockConfirmed [PaymentProcessor]", False),
    (1, 5, "StockConfirmed [Ordering.webapp]", False),
    (4, 1, "PaymentSucceeded or PaymentFailed [Ordering]", False),
    (1, 3, "Paid [Catalog] decrement stock", False),
    (1, 5, "Paid [Ordering.webapp and Webhooks]", False),
    ("note", 1, 5, "Rejected or Failed leads to Cancelled [Ordering.webapp]"),
]
bottom = TOP + len(msgs) * ROW
for x in cx:
    arrow(s, x, AY + AH, x, bottom + 0.05, color="B4B2A9", width=0.75, head=None)
for k, m in enumerate(msgs):
    y = TOP + k * ROW
    if m[0] == "note":
        _, i, j, text = m
        x1 = min(cx[i], cx[j]) - (1.95 if i == j else 0.95)
        x2 = max(cx[i], cx[j]) + (1.95 if i == j else 0.95)
        box(s, x1, y - 0.04, x2 - x1, 0.27, "teal", text, head_size=11, radius=0.04)
        # the note title uses the 800 stop but should read as body text
        s.shapes[-1].text_frame.paragraphs[0].runs[0].font.bold = False
        continue
    i, j, label, sync = m
    arrow(s, cx[i], y + 0.2, cx[j] + (-0.03 if j > i else 0.03), y + 0.2, color="3D3D3A", width=1.0,
          head="triangle" if sync else "arrow")
    lw = max(abs(cx[j] - cx[i]), 3.2)
    lx = (cx[i] + cx[j]) / 2 - lw / 2
    add_text(s, lx, y - 0.07, lw, 0.26, label, size=11, color="3D3D3A",
             align=PP_ALIGN.CENTER)
notes(s, "Solid head = synchronous HTTP; open head = asynchronous event. Shipped and user Cancelled "
         "need PUT /ship or /cancel, which nothing in the lab calls. Ordering API handlers delay 10 s, "
         "which caps throughput at about 3 orders per minute.")

# ---------------------------------------------------------------- 4. Queues table
s = prs.slides.add_slide(BLANK)
title(s, "Queues, writers and readers",
      "Writers publish to the exchange; a queue's writers are the publishers of the events bound to it")
rows = [
    ("Queue", "Reader (service instance)", "Events routed to it (writer)"),
    ("Ordering", "eShop Ordering API", "GracePeriodConfirmed (Order Processor); OrderStockConfirmed / Rejected "
     "(Catalog API); OrderPaymentSucceeded / Failed (Payment Processor)"),
    ("Catalog", "eShop Catalog API", "OrderStatusChangedToAwaitingValidation, ...ToPaid (Ordering API)"),
    ("PaymentProcessor", "eShop Payment Processor", "OrderStatusChangedToStockConfirmed (Ordering API)"),
    ("Basket", "eShop Basket API", "OrderStarted (Ordering API)"),
    ("Ordering.webapp", "eShop WebApp", "OrderStatusChangedTo Submitted, AwaitingValidation, StockConfirmed, Paid, "
     "Shipped, Cancelled (Ordering API)"),
    ("Webhooks", "eShop Webhooks API", "OrderStatusChangedToPaid, ...ToShipped (Ordering API); "
     "ProductPriceChanged (Catalog API)"),
    ("OrderProcessor", "eShop Order Processor", "None: declared at startup, nothing bound; Order Processor "
     "polls orderingdb instead"),
]
tbl = s.shapes.add_table(len(rows), 3, Inches(0.6), Inches(1.55), Inches(12.1), Inches(5.2)).table
for c, wdt in enumerate((2.1, 2.6, 7.4)):
    tbl.columns[c].width = Inches(wdt)
tbl.rows[0].height = Inches(0.45)
for r in range(1, len(rows)):
    tbl.rows[r].height = Inches(0.66)
for r, row in enumerate(rows):
    for c, val in enumerate(row):
        cell = tbl.cell(r, c)
        cell.fill.solid()
        cell.fill.fore_color.rgb = rgb("534AB7" if r == 0 else ("FFFFFF" if r % 2 else "F6F5FD"))
        cell.margin_left = cell.margin_right = Inches(0.08)
        tf = cell.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        run = p.add_run()
        run.text = val
        run.font.name, run.font.size = (MONO if (c == 0 and r) else FONT), Pt(14 if c < 2 or r == 0 else 13)
        run.font.bold = r == 0 or (c == 1)
        run.font.color.rgb = rgb("FFFFFF" if r == 0 else ("3C3489" if c == 1 else INK))
notes(s, "Live bindings on brooks-lab: rabbitmqctl list_bindings in namespace eshop. Ordering API "
         "writes to every queue except its own, which is why the Ordering queue backs up under stress.")

# ---------------------------------------------------------------- 5. CSDM model
s = prs.slides.add_slide(BLANK)
title(s, "ServiceNow CSDM model",
      "Business services per functional component; shared platforms as technology management services")
box(s, 3.0, 1.45, 4.2, 0.5, "purple", "eShop", "Business application", head_size=13, sub_size=10)
bs = [("eShop Storefront", ["eShop WebApp", "eShop Basket API", "eShop Redis"]),
      ("eShop Identity", ["eShop Identity API"]),
      ("eShop Catalog", ["eShop Catalog API"]),
      ("eShop Ordering", ["eShop Ordering API", "eShop Order Processor"]),
      ("eShop Payment Processing", ["eShop Payment Processor"]),
      ("eShop Partner Notifications", ["eShop Webhooks API"])]
tms = [("PostgreSQL", ["eShop PostgreSQL"]),
       ("RabbitMQ", ["eShop RabbitMQ", "Queues (dynamic CI group)"]),
       ("Kubernetes Platform", ["Clusters (dynamic CI group)", "eShop Load Generator", "Spark workloads (shared)"])]
CW, CG, CX0 = 1.3, 0.08, 0.45
rowy = {"bs": 2.35, "bso": 3.4, "si": 4.2}
for i, (name, sis) in enumerate(bs + tms):
    x = CX0 + i * (CW + CG) + (0.25 if i >= len(bs) else 0)
    ramp = "purple" if i < len(bs) else "teal"
    kind = "Business service" if i < len(bs) else "Technology service"
    box(s, x, rowy["bs"], CW, 0.8, ramp, name, kind, head_size=10.5, sub_size=9)
    arrow(s, x + CW / 2, rowy["bs"] + 0.8, x + CW / 2, rowy["bso"] - 0.02)
    box(s, x, rowy["bso"], CW, 0.5, "gray", "Production", "offering", head_size=11, sub_size=9)
    arrow(s, x + CW / 2, rowy["bso"] + 0.5, x + CW / 2, rowy["si"] - 0.02)
    for k, si in enumerate(sis):
        box(s, x, rowy["si"] + k * 0.58, CW, 0.5, "amber" if "group" in si or "shared" in si else ramp,
            si, head_size=10, radius=0.05)
    if i < len(bs):
        arrow(s, 5.1, 1.95, x + CW / 2, rowy["bs"] - 0.02, width=0.75)
add_text(s, 9.0, 1.45, 3.9, 0.55,
         [[("No depends_on between instances: ", {"bold": True}),
           ("dependencies are left for the SGC for Dynatrace SaaS to bring in.", {})]],
         size=11, color=MUTED)
add_text(s, 0.6, 6.45, 12.1, 0.7,
         [[("Purple", {"bold": True, "color": "534AB7"}), (" business side   ", {}),
           ("Teal", {"bold": True, "color": "0F6E56"}), (" technology side   ", {}),
           ("Amber", {"bold": True, "color": "854F0B"}), (" dynamic CI groups and shared members   ", {}),
           ("Instances bind to pods by the servicenow.com/service-instance label.", {})]],
         size=11, color=MUTED)
notes(s, "Offerings are '<service> - Production'. Instances link to offerings with Depends on::Used by "
         "(BSO parent, instance child), the brooks-lab convention. Infrastructure alerts land on a "
         "technology offering; impacted business offerings come from the service map, not the incident's "
         "single service-offering field.")

# ---------------------------------------------------------------- 6. Tagging levels
s = prs.slides.add_slide(BLANK)
title(s, "Kubernetes tagging levels: alert one level above the pod",
      "Pods and ReplicaSets are replaced on every rollout; the workload keeps its name and identity")
levels = [("Cluster", "brooks-lab", "gray", "Kubernetes Platform TMO (dynamic CI group)"),
          ("Namespace", "eshop", "gray", "app.kubernetes.io/part-of: eshop"),
          ("Workload (Deployment)", "catalog-api", "amber", "ALERT HERE: Dynatrace cloud application, SN Deployment CI"),
          ("ReplicaSet", "catalog-api-54f45dcf75", "gray", "changes on every rollout"),
          ("Pod", "catalog-api-54f45dcf75-52tcw", "purple", "labels copied by KVA to cmdb_key_value"),
          ("Container", "catalog-api", "gray", "log lines, OneAgent process group")]
for k, (lvl, ex, ramp, why) in enumerate(levels):
    y = 1.55 + k * 0.82
    ind = k * 0.25
    box(s, 0.6 + ind, y, 4.4, 0.62, ramp, lvl, ex, head_size=13, sub_size=11, align=PP_ALIGN.LEFT)
    add_text(s, 5.25 + ind, y + 0.15, 3.0, 0.4, why, size=11,
             color="633806" if ramp == "amber" else MUTED, bold=ramp == "amber")
    if k:
        arrow(s, 0.85 + ind - 0.25, y - 0.2, 0.85 + ind - 0.25, y + 0.31, head=None, width=0.75)
        arrow(s, 0.85 + ind - 0.25, y + 0.31, 0.6 + ind, y + 0.31, width=0.75, head=None)
# label flow (right)
box(s, 9.3, 1.55, 3.45, 0.75, "purple", "servicenow.com/service-instance", "eShop-Catalog-API (pod label)",
    head_size=11, sub_size=11)
arrow(s, 11.0, 2.3, 11.0, 2.62)
box(s, 9.3, 2.65, 3.45, 0.75, "gray", "KVA + tag-based mapping", "cmdb_key_value to svc_ci_assoc", head_size=11,
    sub_size=11)
arrow(s, 11.0, 3.4, 11.0, 3.72)
box(s, 9.3, 3.75, 3.45, 0.75, "purple", "eShop Catalog API", "service instance (SN)", head_size=11, sub_size=11)
box(s, 9.3, 4.9, 3.45, 0.95, "teal", "Dynatrace log pipeline",
    "workload name to sn-service-instance;\nalert entity = cloud application", head_size=11, sub_size=11)
arrow(s, 11.0, 4.9, 11.0, 4.52)
add_text(s, 9.3, 6.0, 3.45, 0.9, "Both paths resolve to the same service instance name, so an alert "
         "binds to eShop Catalog API whichever pod raised it.", size=11, color=MUTED)
notes(s, "Dynatrace: davis events use dt.davis.is_entity_remapping_allowed=false and bind to the "
         "cloud application (workload). ServiceNow: the incident script resolves sn-service-instance "
         "('eShop-Catalog-API') to the service instance 'eShop Catalog API'.")


# ---------------------------------------------------------------- 7-8. Deployment snippets
DARK = {"bg": "1E1E1E", "key": "9CDCFE", "str": "CE9178", "num": "B5CEA8", "kw": "569CD6",
        "com": "6A9955", "punc": "D4D4D4"}
KEY_RE = re.compile(r"^(\s*)(- )?([A-Za-z0-9_.\-/]+)(:)(\s?)(.*)$")


def yaml_runs(line):
    """VS Code Dark+ tokens for one YAML line: keys light blue, strings orange, numbers green,
    booleans and kinds blue, comments green."""
    if line.strip().startswith("#"):
        return [(line, DARK["com"])]
    out, comment = [], ""
    if " #" in line and not line.strip().startswith("-") or "  #" in line:
        idx = line.index("  #") if "  #" in line else line.index(" #")
        line, comment = line[:idx], line[idx:]
    m = KEY_RE.match(line)
    if m:
        ind, dash, key, colon, sp, val = m.groups()
        out += [(ind, DARK["punc"])]
        if dash:
            out.append((dash, DARK["punc"]))
        out += [(key, DARK["kw"] if key.startswith(("apiVersion", "kind")) and False else DARK["key"]),
                (colon + sp, DARK["punc"])]
        if val:
            v = val.strip()
            if re.fullmatch(r"-?\d+(\.\d+)?", v):
                col = DARK["num"]
            elif v in ("true", "false", "null"):
                col = DARK["kw"]
            else:
                col = DARK["str"]
            out.append((val, col))
    else:
        stripped = line.lstrip()
        ind = line[: len(line) - len(stripped)]
        out += [(ind, DARK["punc"])]
        if stripped.startswith("- "):
            out += [("- ", DARK["punc"]), (stripped[2:], DARK["str"])]
        else:
            out.append((stripped, DARK["str"]))
    if comment:
        out.append((comment, DARK["com"]))
    return out


def code_slide(heading, sub, code, callouts, note_text, highlight="servicenow.com/service-instance"):
    s = prs.slides.add_slide(BLANK)
    title(s, heading, sub)
    lines = code.strip("\n").split("\n")
    cx, cy, cw, lh = 0.6, 1.45, 7.9, 0.187
    panel = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(cx), Inches(cy), Inches(cw),
                               Inches(0.3 + lh * len(lines)))
    panel.adjustments[0] = 0.02
    panel.fill.solid()
    panel.fill.fore_color.rgb = rgb(DARK["bg"])
    panel.line.fill.background()
    _unstyle(panel)
    panel.name = "Code panel"
    for k, ln in enumerate(lines):
        if highlight in ln:
            hl = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(cx + 0.05), Inches(cy + 0.15 + k * lh),
                                    Inches(cw - 0.1), Inches(lh))
            hl.fill.solid()
            hl.fill.fore_color.rgb = rgb("3A3D41")
            hl.line.fill.background()
            _unstyle(hl)
    paras = [[(t, {"color": c, "font": MONO}) for t, c in yaml_runs(ln) if t] or [(" ", {})] for ln in lines]
    tb = add_text(s, cx + 0.15, cy + 0.15, cw - 0.3, lh * len(lines), paras, size=10.5, font=MONO, name="Code")
    for p in tb.text_frame.paragraphs:
        p.line_spacing = Pt(13.46)
    for k, (head, body, ramp) in enumerate(callouts):
        box(s, 8.85, 1.5 + k * 1.32, 3.9, 1.15, ramp, head, body, head_size=12, sub_size=11,
            align=PP_ALIGN.LEFT)
    notes(s, note_text)


CATALOG = """
apiVersion: apps/v1
kind: Deployment               # workload level: the alert target
metadata:
  name: catalog-api
  namespace: eshop             # namespace level
  labels:
    app: catalog-api
    app.kubernetes.io/part-of: eshop
    servicenow.com/service-instance: eShop-Catalog-API
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog-api
  template:                    # pod level: ephemeral copies
    metadata:
      labels:
        app: catalog-api
        app.kubernetes.io/part-of: eshop
        servicenow.com/service-instance: eShop-Catalog-API
    spec:
      nodeSelector:
        kubernetes.io/hostname: lab1
      containers:
        - name: catalog-api    # container level: logs
          env:
            - name: Logging__Console__FormatterName
              value: simple
"""
code_slide("Deployment snippet: Catalog API",
           "Business service eShop Catalog; service instance eShop Catalog API",
           CATALOG,
           [("Workload labels", "Name the service instance on the\nDeployment so the workload CI and\n"
             "Dynatrace cloud application carry it", "amber"),
            ("Pod template labels", "Every pod inherits the same value;\nKVA copies it to cmdb_key_value for\n"
             "tag-based Service Mapping", "purple"),
            ("Single-line logs", "warn:/fail:/crit: lines parsed by the\neShop log pipeline into\n"
             "WARN / ERROR / CRITICAL alerts", "teal"),
            ("Alert one level up", "Problems bind to catalog-api (the\nworkload), not to a pod name that\n"
             "disappears on the next rollout", "gray")],
           "Excerpt of the rendered manifest (k8s/eshop/apps.yaml.j2), rewritten in block style. "
           "Label values come from eshop_service_instances in playbooks/eshop/common/vars.yml.")

RABBIT = """
apiVersion: apps/v1
kind: Deployment               # workload level: the alert target
metadata:
  name: rabbitmq
  namespace: eshop
  labels:
    app: rabbitmq
    app.kubernetes.io/part-of: eshop
    servicenow.com/service-instance: eShop-RabbitMQ
spec:
  strategy:
    type: Recreate
  template:                    # pod level
    metadata:
      labels:
        app: rabbitmq
        servicenow.com/service-instance: eShop-RabbitMQ
      annotations:             # Dynatrace Prometheus scrape
        metrics.dynatrace.com/scrape: "true"
        metrics.dynatrace.com/port: "15692"
        metrics.dynatrace.com/path: /metrics/per-object
    spec:
      hostname: rabbitmq       # stable broker identity
      containers:
        - name: rabbitmq
          image: rabbitmq:4.1-management
"""
code_slide("Deployment snippet: RabbitMQ",
           "Technology service RabbitMQ; service instance eShop RabbitMQ; queue CIs from RabbitMQ discovery",
           RABBIT,
           [("Platform instance", "eShop RabbitMQ sits under the\nRabbitMQ - Production technology\noffering", "teal"),
            ("Per-queue metrics", "/metrics/per-object gives one series\nper queue: backlog and consumer\nalerts per queue",
             "amber"),
            ("Queue CIs", "cmdb_ci_appl_rabbitmq_queue, contained\nby the broker; grouped by the RabbitMQ\n"
             "Queues dynamic CI group", "purple"),
            ("Stable hostname", "Broker node name survives pod\nrestarts, so the broker CI keeps\nits identity", "gray")],
           "Excerpt of the rendered manifest (k8s/eshop/infra.yaml.j2). Queue alerts bind to the queue CI "
           "(ResolveApplicationService.applyQueueCiBinding); broker alerts to the workload.")

prs.save(OUT)
print(OUT)
