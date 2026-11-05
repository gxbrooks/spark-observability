#!/usr/bin/env python3
"""Generate servicenow/docs/DT_SN_Concepts.odp (LibreOffice Impress)."""

from __future__ import annotations

import zipfile
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "DT_SN_Concepts.odp"

STYLE = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  office:version="1.3">
  <office:font-face-decls>
    <style:font-face style:name="Arial" svg:font-family="Arial"/>
    <style:font-face style:name="DejaVu Sans" svg:font-family="&apos;DejaVu Sans&apos;"/>
  </office:font-face-decls>
  <office:styles>
    <style:style style:name="dp1" style:family="drawing-page">
      <style:drawing-page-properties draw:background-size="full" draw:fill="solid" draw:fill-color="#0b1424"/>
    </style:style>
    <style:style style:name="gr1" style:family="graphic">
      <style:graphic-properties draw:stroke="solid" draw:stroke-color="#00bcd4" draw:stroke-width="0.04cm"
        draw:fill="solid" draw:fill-color="#132238" draw:shadow="visible" draw:shadow-offset-x="0.08cm" draw:shadow-offset-y="0.08cm"/>
    </style:style>
    <style:style style:name="gr2" style:family="graphic">
      <style:graphic-properties draw:stroke="solid" draw:stroke-color="#4fc3f7" draw:stroke-width="0.04cm"
        draw:fill="solid" draw:fill-color="#1a3358"/>
    </style:style>
    <style:style style:name="gr3" style:family="graphic">
      <style:graphic-properties draw:stroke="solid" draw:stroke-color="#80cbc4" draw:stroke-width="0.04cm"
        draw:fill="solid" draw:fill-color="#12304a"/>
    </style:style>
    <style:style style:name="P1" style:family="paragraph">
      <style:text-properties fo:font-size="14pt" fo:font-weight="bold" fo:color="#e8f4ff"/>
    </style:style>
    <style:style style:name="P2" style:family="paragraph">
      <style:text-properties fo:font-size="11pt" fo:color="#b0c4de"/>
    </style:style>
    <style:style style:name="T1" style:family="text">
      <style:text-properties fo:font-size="28pt" fo:font-weight="bold" fo:color="#ffffff"/>
    </style:style>
    <style:style style:name="T2" style:family="text">
      <style:text-properties fo:font-size="16pt" fo:color="#90caf9"/>
    </style:style>
  </office:styles>
  <office:automatic-styles>
    <style:page-layout style:name="pm1">
      <style:page-layout-properties fo:page-width="28cm" fo:page-height="21cm" style:print-orientation="landscape"/>
    </style:page-layout>
  </office:automatic-styles>
  <office:master-styles>
    <style:master-page style:name="Standard" style:page-layout-name="pm1" draw:style-name="dp1"/>
  </office:master-styles>
</office:document-styles>"""

META = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/" office:version="1.3">
  <office:meta>
    <meta:generator>spark-observability build_dt_sn_concepts_odp.py</meta:generator>
    <dc:title>ServiceNow and Dynatrace Model Enrichment and Cross Correlation</dc:title>
    <dc:description>High-level data flow for CSDM, runtime specs, playbooks, and platform outputs.</dc:description>
  </office:meta>
</office:document-meta>"""

MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.presentation"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""


def box(x: str, y: str, w: str, h: str, text: str, style: str = "gr1") -> str:
    return f"""
      <draw:rect draw:style-name="{style}" text:style-name="P1" svg:width="{w}" svg:height="{h}" svg:x="{x}" svg:y="{y}">
        <text:p text:style-name="P1">{text}</text:p>
      </draw:rect>"""


def hex_proc(x: str, y: str, w: str, h: str, text: str) -> str:
    return f"""
      <draw:regular-polygon draw:style-name="gr2" text:style-name="P1" draw:corners="6" draw:sharpness="50%"
        svg:width="{w}" svg:height="{h}" svg:x="{x}" svg:y="{y}">
        <text:p text:style-name="P1">{text}</text:p>
      </draw:regular-polygon>"""


def arrow(x1: str, y1: str, x2: str, y2: str) -> str:
    return f"""
      <draw:line draw:style-name="gr3" svg:x1="{x1}" svg:y1="{y1}" svg:x2="{x2}" svg:y2="{y2}">
        <svg:desc>flow</svg:desc>
      </draw:line>"""


CONTENT = f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
  xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
  xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"
  office:version="1.3">
  <office:body>
    <office:presentation>
      <draw:page draw:name="Title" draw:style-name="dp1" draw:master-page-name="Standard">
        <draw:frame presentation:style-name="pr1" draw:layer="layout" svg:width="25cm" svg:height="3.5cm" svg:x="1.5cm" svg:y="6cm">
          <draw:text-box>
            <text:p text:style-name="T1">ServiceNow &amp; Dynatrace Model Enrichment and Cross Correlation</text:p>
            <text:p text:style-name="T2">Version-controlled CSDM intent, runtime workload labels, and cross-platform compare</text:p>
          </draw:text-box>
        </draw:frame>
      </draw:page>
      <draw:page draw:name="DataFlow" draw:style-name="dp1" draw:master-page-name="Standard">
        <draw:frame draw:layer="layout" svg:width="26cm" svg:height="1.2cm" svg:x="1cm" svg:y="0.4cm">
          <draw:text-box><text:p text:style-name="T2">Data flow — specifications, processing, and platform outputs</text:p></draw:text-box>
        </draw:frame>
        {box("0.8cm", "2.2cm", "3.6cm", "1.4cm", "*.csdm.yaml")}
        {box("0.8cm", "4.2cm", "3.6cm", "1.4cm", "region.yaml")}
        {box("0.8cm", "6.2cm", "3.6cm", "1.4cm", "docker-compose.yml")}
        {box("0.8cm", "8.2cm", "3.6cm", "1.4cm", "K8s / DynaKube specs")}
        {hex_proc("5.5cm", "3.2cm", "3.8cm", "2.2cm", "csdm/deploy.yml")}
        {hex_proc("5.5cm", "6.2cm", "3.8cm", "2.2cm", "discovery/* + sync_pod_labels")}
        {hex_proc("10.2cm", "4.8cm", "3.8cm", "2.2cm", "compare.yml")}
        {box("15.2cm", "2.0cm", "3.8cm", "1.4cm", "ServiceNow CSDM + CMDB")}
        {box("15.2cm", "4.2cm", "3.8cm", "1.4cm", "Docker runtime")}
        {box("15.2cm", "6.4cm", "3.8cm", "1.4cm", "Kubernetes runtime")}
        {box("15.2cm", "8.6cm", "3.8cm", "1.4cm", "Dynatrace tenant")}
        {box("20.5cm", "4.8cm", "4.5cm", "2.0cm", "DT_SN_Model_Comparison_Report.json")}
        {arrow("4.4cm", "2.9cm", "5.5cm", "4.0cm")}
        {arrow("4.4cm", "4.9cm", "5.5cm", "4.2cm")}
        {arrow("4.4cm", "6.9cm", "5.5cm", "7.0cm")}
        {arrow("4.4cm", "8.9cm", "5.5cm", "7.4cm")}
        {arrow("9.3cm", "4.3cm", "15.2cm", "2.7cm")}
        {arrow("9.3cm", "7.3cm", "15.2cm", "5.0cm")}
        {arrow("9.3cm", "7.3cm", "15.2cm", "7.1cm")}
        {arrow("14.0cm", "5.9cm", "10.2cm", "5.9cm")}
        {arrow("14.0cm", "7.1cm", "10.2cm", "6.2cm")}
        {arrow("14.0cm", "3.5cm", "10.2cm", "5.2cm")}
        {arrow("19.0cm", "5.7cm", "20.5cm", "5.7cm")}
        <draw:frame draw:layer="layout" svg:width="26cm" svg:height="1.5cm" svg:x="1cm" svg:y="10.5cm">
          <draw:text-box>
            <text:p text:style-name="P2">Square = version-controlled input or platform output. Hexagon = Ansible playbook / process. Compare defaults to full CMDB + full tenant; scope filters live in scope_applied.</text:p>
          </draw:text-box>
        </draw:frame>
      </draw:page>
    </office:presentation>
  </office:body>
</office:document-content>"""


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("mimetype", "application/vnd.oasis.opendocument.presentation", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/manifest.xml", MANIFEST)
        zf.writestr("styles.xml", STYLE)
        zf.writestr("meta.xml", META)
        zf.writestr("content.xml", CONTENT)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
