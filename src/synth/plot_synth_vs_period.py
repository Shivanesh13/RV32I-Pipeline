#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Parse cpu_synth_*_{period}.rpt files and plot metrics vs clock period (ns).

Uses only the Python 3 standard library — writes SVG (no matplotlib/numpy).
Open .svg in a browser or import into your paper.
"""

import re
from pathlib import Path
from xml.sax.saxutils import escape

SYNTH_DIR = Path(__file__).resolve().parent


def parse_timing(path):
    text = path.read_text()
    m = re.search(r"slack \((?:MET|VIOLATED)\)\s+(-?\d+\.\d+)", text)
    return float(m.group(1)) if m else None


def parse_area(path):
    text = path.read_text()
    cells_m = re.search(r"Number of cells:\s+(\d+)", text)
    area_m = re.search(r"Total cell area:\s+([\d.]+)", text)
    cells = int(cells_m.group(1)) if cells_m else None
    area = float(area_m.group(1)) if area_m else None
    return cells, area


def parse_power(path):
    text = path.read_text()
    dyn_m = re.search(r"Total Dynamic Power\s+=\s+([\d.]+)\s+uW", text)
    leak_m = re.search(r"Cell Leakage Power\s+=\s+([\d.]+)\s+uW", text)
    return (
        float(dyn_m.group(1)) if dyn_m else None,
        float(leak_m.group(1)) if leak_m else None,
    )


def load_series():
    timing_files = sorted(SYNTH_DIR.glob("cpu_synth_timing_*.rpt"))
    periods = []
    for p in timing_files:
        m = re.search(r"cpu_synth_timing_(\d+)\.rpt$", p.name)
        if not m:
            continue
        periods.append(int(m.group(1)))
    periods.sort()

    slack = []
    cells = []
    area = []
    dynamic = []
    leakage = []
    period_used = []

    for T in periods:
        tpath = SYNTH_DIR / "cpu_synth_timing_{}.rpt".format(T)
        apath = SYNTH_DIR / "cpu_synth_area_{}.rpt".format(T)
        ppath = SYNTH_DIR / "cpu_synth_power_{}.rpt".format(T)
        if not (tpath.is_file() and apath.is_file() and ppath.is_file()):
            continue
        s = parse_timing(tpath)
        c, a = parse_area(apath)
        d, l = parse_power(ppath)
        if s is None or c is None or a is None or d is None or l is None:
            continue
        slack.append(s)
        cells.append(c)
        area.append(a)
        dynamic.append(d)
        leakage.append(l)
        period_used.append(T)

    return {
        "period_ns": period_used,
        "slack_ns": slack,
        "cells": cells,
        "area_um2": area,
        "dynamic_uw": dynamic,
        "leakage_uw": leakage,
    }


def _nice_y_bounds(ys, pad_ratio=0.08, include_zero=False):
    lo = min(ys)
    hi = max(ys)
    if include_zero:
        lo = min(lo, 0.0)
        hi = max(hi, 0.0)
    span = hi - lo
    if span <= 0:
        span = abs(hi) * 0.1 or 1.0
    pad = span * pad_ratio
    return lo - pad, hi + pad


def _fmt_tick(v):
    if abs(v) >= 1000:
        return "{:.0f}".format(v)
    if abs(v) >= 10:
        return "{:.1f}".format(v)
    if abs(v) >= 1:
        return "{:.2f}".format(v)
    return "{:.3f}".format(v)


def svg_line_chart(
    xs,
    ys,
    title,
    x_label,
    y_label,
    path,
    stroke="#1f77b4",
    point_fill=None,
    hline_y=None,
    neg_color="#c0392b",
    pos_color="#27ae60",
):
    """Single-panel line + markers chart; writes SVG."""
    w, h = 640, 400
    ml, mr, mt, mb = 72, 28, 48, 52
    pw, ph = w - ml - mr, h - mt - mb

    xmin, xmax = float(min(xs)), float(max(xs))
    if xmax == xmin:
        xmax = xmin + 1.0
    xpad = (xmax - xmin) * 0.06 or 0.5
    xmin -= xpad
    xmax += xpad

    ymin, ymax = _nice_y_bounds(ys, include_zero=hline_y is not None)
    if ymax == ymin:
        ymax = ymin + 1.0

    def tx(x):
        return ml + (x - xmin) / (xmax - xmin) * pw

    def ty(y):
        return mt + ph - (y - ymin) / (ymax - ymin) * ph

    parts = []
    parts.append('<?xml version="1.0" encoding="UTF-8"?>')
    parts.append(
        '<svg xmlns="http://www.w3.org/2000/svg" width="{}" height="{}">'.format(w, h)
    )
    parts.append(
        '<rect x="0" y="0" width="{}" height="{}" fill="white"/>'.format(w, h)
    )
    parts.append(
        '<text x="{}" y="{}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="14" font-weight="bold">{}</text>'.format(
            w // 2, 22, escape(title)
        )
    )

    # Grid (vertical)
    for i in range(5):
        gx = ml + i * pw / 4.0
        parts.append(
            '<line x1="{gx:.1f}" y1="{mt}" x2="{gx:.1f}" y2="{mt2}" stroke="#e0e0e0" stroke-width="1"/>'.format(
                gx=gx, mt=mt, mt2=mt + ph
            )
        )
    # Grid (horizontal)
    for j in range(5):
        gy = mt + j * ph / 4.0
        parts.append(
            '<line x1="{ml}" y1="{gy:.1f}" x2="{ml2}" y2="{gy:.1f}" stroke="#e0e0e0" stroke-width="1"/>'.format(
                ml=ml, ml2=ml + pw, gy=gy
            )
        )

    # Axes
    parts.append(
        '<line x1="{}" y1="{}" x2="{}" y2="{}" stroke="#333" stroke-width="1.5"/>'.format(
            ml, mt + ph, ml + pw, mt + ph
        )
    )
    parts.append(
        '<line x1="{}" y1="{}" x2="{}" y2="{}" stroke="#333" stroke-width="1.5"/>'.format(
            ml, mt, ml, mt + ph
        )
    )

    # X ticks
    for i in range(5):
        xv = xmin + i * (xmax - xmin) / 4.0
        gx = tx(xv)
        parts.append(
            '<text x="{:.1f}" y="{}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="10" fill="#333">{}</text>'.format(
                gx, h - 18, _fmt_tick(xv)
            )
        )

    # Y ticks
    for j in range(5):
        yv = ymin + j * (ymax - ymin) / 4.0
        gy = ty(yv)
        parts.append(
            '<text x="{}" y="{:.1f}" text-anchor="end" dominant-baseline="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="10" fill="#333">{}</text>'.format(
                ml - 8, gy, _fmt_tick(yv)
            )
        )

    parts.append(
        '<text x="{}" y="{}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="11" fill="#333">{}</text>'.format(
            ml + pw / 2, h - 4, escape(x_label)
        )
    )
    parts.append(
        '<text transform="rotate(-90 {:f} {:f})" x="{}" y="{}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="11" fill="#333">{}</text>'.format(
            18, h / 2, 18, h / 2, escape(y_label)
        )
    )

    if hline_y is not None and ymin <= hline_y <= ymax:
        hy = ty(hline_y)
        parts.append(
            '<line x1="{}" y1="{:.1f}" x2="{}" y2="{:.1f}" stroke="#000" stroke-width="1" stroke-dasharray="4,3" opacity="0.7"/>'.format(
                ml, hy, ml + pw, hy
            )
        )

    # Polyline
    pts = " ".join("{:.2f},{:.2f}".format(tx(x), ty(y)) for x, y in zip(xs, ys))
    parts.append(
        '<polyline fill="none" stroke="{}" stroke-width="2" points="{}"/>'.format(
            stroke, pts
        )
    )

    # Points
    pf = point_fill
    for x, y in zip(xs, ys):
        color = stroke
        if pf == "slack_sign":
            color = neg_color if y < 0 else pos_color
        elif pf:
            color = pf
        parts.append(
            '<circle cx="{:.2f}" cy="{:.2f}" r="5" fill="{}" stroke="white" stroke-width="1.2"/>'.format(
                tx(x), ty(y), color
            )
        )

    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")


def svg_four_panel(data, path):
    """2x2 grid of charts in one SVG."""
    T = data["period_ns"]
    w, h = 880, 640
    parts = []
    parts.append('<?xml version="1.0" encoding="UTF-8"?>')
    parts.append(
        '<svg xmlns="http://www.w3.org/2000/svg" width="{}" height="{}">'.format(w, h)
    )
    parts.append(
        '<rect x="0" y="0" width="{}" height="{}" fill="white"/>'.format(w, h)
    )
    parts.append(
        '<text x="{}" y="{}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="15" font-weight="bold">{}</text>'.format(
            w // 2,
            26,
            escape(
                "RV32I pipeline (top) — synthesis vs clock period (Nangate slow corner)"
            ),
        )
    )

    panels = [
        (data["dynamic_uw"], "Dynamic power (µW)", "#1f77b4", "Default SA power report"),
        (data["leakage_uw"], "Leakage (µW)", "#ff7f0e", "Cell leakage"),
        (data["cells"], "Cell count", "#2ca02c", "Total instances"),
        (data["area_um2"], "Area (µm²)", "#d62728", "Total cell area"),
    ]

    def mini_chart(x0, y0, pw, ph, ys, ylab, color, sub):
        xmin, xmax = float(min(T)), float(max(T))
        xpad = (xmax - xmin) * 0.08 or 0.5
        xmin -= xpad
        xmax += xpad
        ymin, ymax = _nice_y_bounds(ys)
        if ymax == ymin:
            ymax = ymin + 1.0

        def tx(x):
            return x0 + (x - xmin) / (xmax - xmin) * pw

        def ty(y):
            return y0 + ph - (y - ymin) / (ymax - ymin) * ph

        g = []
        g.append(
            '<g transform="translate(0,0)"><text x="{}" y="{}" font-family="DejaVu Sans, Arial, sans-serif" font-size="12" font-weight="bold" fill="#222">{}</text></g>'.format(
                x0, y0 - 6, escape(sub)
            )
        )
        pts = " ".join("{:.2f},{:.2f}".format(tx(x), ty(y)) for x, y in zip(T, ys))
        g.append(
            '<polyline fill="none" stroke="{}" stroke-width="2" points="{}"/>'.format(
                color, pts
            )
        )
        for x, y in zip(T, ys):
            g.append(
                '<circle cx="{:.2f}" cy="{:.2f}" r="4" fill="{}" stroke="white" stroke-width="1"/>'.format(
                    tx(x), ty(y), color
                )
            )
        g.append(
            '<text x="{}" y="{}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="10" fill="#555">Clock period (ns)</text>'.format(
                x0 + pw / 2, y0 + ph + 28
            )
        )
        g.append(
            '<text transform="rotate(-90 {:.1f} {:.1f})" x="{:.1f}" y="{:.1f}" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="10" fill="#555">{}</text>'.format(
                x0 - 28, y0 + ph / 2, x0 - 28, y0 + ph / 2, escape(ylab)
            )
        )
        return "\n".join(g)

    col_w, row_h = 400, 260
    ox, oy = 40, 48
    positions = [(ox, oy), (ox + col_w + 40, oy), (ox, oy + row_h + 50), (ox + col_w + 40, oy + row_h + 50)]
    for (ys, ylab, color, sub), (px, py) in zip(panels, positions):
        parts.append(mini_chart(px + 40, py + 16, col_w - 40, row_h - 40, ys, ylab, color, sub))

    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")


def main():
    data = load_series()
    T = data["period_ns"]
    if not T:
        raise SystemExit("No complete timing/area/power triplets found.")

    out_dir = SYNTH_DIR / "figures"
    out_dir.mkdir(exist_ok=True)

    svg_line_chart(
        T,
        data["dynamic_uw"],
        "Dynamic power vs clock period",
        "Clock period (ns)",
        "Dynamic power (µW)",
        out_dir / "synth_dynamic_vs_period.svg",
        stroke="#1f77b4",
    )
    svg_line_chart(
        T,
        data["leakage_uw"],
        "Cell leakage vs clock period",
        "Clock period (ns)",
        "Leakage (µW)",
        out_dir / "synth_leakage_vs_period.svg",
        stroke="#ff7f0e",
    )
    svg_line_chart(
        T,
        data["cells"],
        "Total cell count vs clock period",
        "Clock period (ns)",
        "Cells",
        out_dir / "synth_cells_vs_period.svg",
        stroke="#2ca02c",
    )
    svg_line_chart(
        T,
        data["area_um2"],
        "Total cell area vs clock period",
        "Clock period (ns)",
        "Total cell area (µm²)",
        out_dir / "synth_area_vs_period.svg",
        stroke="#d62728",
    )
    svg_line_chart(
        T,
        data["slack_ns"],
        "Worst setup slack vs clock period (slow corner)",
        "Clock period (ns)",
        "Setup slack (ns)",
        out_dir / "synth_worst_slack_vs_period.svg",
        stroke="#34495e",
        point_fill="slack_sign",
        hline_y=0.0,
    )
    svg_four_panel(data, out_dir / "synth_metrics_vs_period_grid.svg")

    print("Wrote SVG figures to {} (no extra packages required):".format(out_dir))
    for p in sorted(out_dir.glob("*.svg")):
        print("  {}".format(p.name))


if __name__ == "__main__":
    main()
