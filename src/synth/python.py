# -*- coding: utf-8 -*-
"""
Generate an interactive-style HTML dashboard of synthesis metrics vs clock period.

Uses only the Python 3 standard library (no plotly/pandas). Hover tooltips use
SVG <title> elements — they appear on mouseover in any browser.

Output: interactive_synthesis_plots.html (in this directory)
"""

from pathlib import Path
from xml.sax.saxutils import escape


def _bounds(xs, ys, pad_ratio=0.08):
    xmin, xmax = min(xs), max(xs)
    span_x = xmax - xmin or 1.0
    pad_x = span_x * pad_ratio or 0.5
    xmin -= pad_x
    xmax += pad_x
    ymin, ymax = min(ys), max(ys)
    span_y = ymax - ymin or 1.0
    pad_y = span_y * pad_ratio
    ymin -= pad_y
    ymax += pad_y
    return xmin, xmax, ymin, ymax


def _fmt(v):
    if abs(v) >= 1000:
        return "{:.0f}".format(v)
    if abs(v) >= 100:
        return "{:.1f}".format(v)
    if abs(v) >= 1:
        return "{:.2f}".format(v)
    return "{:.3f}".format(v)


def chart_svg(xs, ys, subtitle, y_unit, color, w=420, h=280):
    ml, mr, mt, mb = 50, 18, 36, 40
    pw, ph = w - ml - mr, h - mt - mb
    xmin, xmax, ymin, ymax = _bounds(xs, ys)

    def tx(x):
        return ml + (x - xmin) / (xmax - xmin) * pw

    def ty(y):
        return mt + ph - (y - ymin) / (ymax - ymin) * ph

    lines = []
    lines.append('<svg xmlns="http://www.w3.org/2000/svg" width="{}" height="{}">'.format(w, h))
    lines.append(
        '<text x="{}" y="{}" font-family="Segoe UI, Arial, sans-serif" font-size="13" font-weight="600" fill="#222">{}</text>'.format(
            ml, 20, escape(subtitle)
        )
    )
    for i in range(5):
        gx = ml + i * pw / 4.0
        lines.append(
            '<line x1="{:.1f}" y1="{}" x2="{:.1f}" y2="{}" stroke="#eee" stroke-width="1"/>'.format(
                gx, mt, gx, mt + ph
            )
        )
    for j in range(5):
        gy = mt + j * ph / 4.0
        lines.append(
            '<line x1="{}" y1="{:.1f}" x2="{}" y2="{:.1f}" stroke="#eee" stroke-width="1"/>'.format(
                ml, gy, ml + pw, gy
            )
        )
    pts = " ".join("{:.1f},{:.1f}".format(tx(x), ty(y)) for x, y in zip(xs, ys))
    lines.append(
        '<polyline fill="none" stroke="{}" stroke-width="2.5" points="{}"/>'.format(color, pts)
    )
    for x, y in zip(xs, ys):
        tip = "Tclk = {} ns, {} = {}".format(x, y_unit, _fmt(y))
        lines.append(
            '<circle cx="{:.1f}" cy="{:.1f}" r="6" fill="{}" stroke="white" stroke-width="1.5">'.format(
                tx(x), ty(y), color
            )
        )
        lines.append("<title>{}</title>".format(escape(tip)))
        lines.append("</circle>")
    lines.append(
        '<text x="{}" y="{}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="11" fill="#444">Clock period (ns)</text>'.format(
            ml + pw / 2, h - 10
        )
    )
    lines.append(
        '<text transform="rotate(-90 {:d} {:d})" x="{:d}" y="{:d}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="11" fill="#444">{}</text>'.format(
            14, h // 2, 14, h // 2, escape(y_unit)
        )
    )
    lines.append("</svg>")
    return "\n".join(lines)


def main():
    data = {
        "Tclk": [10, 11, 12, 13, 15, 20],
        "Dynamic": [832.8, 757.25, 693.54, 640.25, 554.97, 415.93],
        "Leakage": [54.25, 54.35, 53.9, 53.53, 52.34, 50.42],
        "Cells": [6913, 6929, 6820, 6747, 7008, 7928],
        "Area": [15304.58, 15317.08, 15265.74, 15221.58, 15182.75, 15087.25],
    }
    T = data["Tclk"]

    charts = [
        (data["Dynamic"], "Dynamic power", "Dynamic (µW)", "#1f77b4"),
        (data["Leakage"], "Cell leakage", "Leakage (µW)", "#ff7f0e"),
        (data["Cells"], "Total cell count", "Cells", "#2ca02c"),
        (data["Area"], "Total cell area", "Area (µm²)", "#d62728"),
    ]

    svgs = [chart_svg(T, ys, sub, ylab, c) for ys, sub, ylab, c in charts]

    html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>RV32I Pipeline Synthesis Characterization</title>
  <style>
    body {{ font-family: "Segoe UI", Arial, sans-serif; margin: 24px; background: #fafafa; color: #222; }}
    h1 {{ text-align: center; font-size: 1.5rem; font-weight: 600; margin-bottom: 8px; }}
    p.note {{ text-align: center; color: #555; font-size: 0.9rem; margin-bottom: 24px; }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(2, minmax(320px, 1fr));
      gap: 20px 24px;
      max-width: 1100px;
      margin: 0 auto;
    }}
    .panel {{
      background: #fff;
      border-radius: 8px;
      box-shadow: 0 1px 4px rgba(0,0,0,.08);
      padding: 12px;
      overflow: auto;
    }}
    .panel svg {{ display: block; margin: 0 auto; }}
  </style>
</head>
<body>
  <h1>RV32I Pipeline Synthesis Characterization</h1>
  <p class="note">Hover points for values. Generated without Plotly (stdlib only).</p>
  <div class="grid">
    <div class="panel">{s0}</div>
    <div class="panel">{s1}</div>
    <div class="panel">{s2}</div>
    <div class="panel">{s3}</div>
  </div>
</body>
</html>
""".format(
        s0=svgs[0], s1=svgs[1], s2=svgs[2], s3=svgs[3]
    )

    out = Path(__file__).resolve().parent / "interactive_synthesis_plots.html"
    out.write_text(html, encoding="utf-8")
    print("Wrote {}".format(out))


if __name__ == "__main__":
    main()
