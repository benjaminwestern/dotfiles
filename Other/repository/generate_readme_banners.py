#!/usr/bin/env python3
"""Generate SVG banner assets for the repository READMEs.

The output is intentionally pure SVG and dependency-free so the assets can be
rebuilt on any machine that already has Python available through mise.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from textwrap import wrap
from typing import Iterable
from xml.sax.saxutils import escape


REPO_ROOT = Path(__file__).resolve().parents[2]
ASSETS_DIR = REPO_ROOT / "assets" / "readme"

PALETTE = {
    "bg": "#F5F0E6",
    "surface": "#FFF9F0",
    "ink": "#172033",
    "muted": "#5C667A",
    "line": "#263A63",
    "blue": "#3F63DD",
    "teal": "#177A67",
    "ember": "#C55A38",
    "gold": "#CFA14A",
    "lavender": "#6956CE",
}

ACCENTS = {
    "blue": PALETTE["blue"],
    "teal": PALETTE["teal"],
    "ember": PALETTE["ember"],
    "gold": PALETTE["gold"],
    "lavender": PALETTE["lavender"],
}

CHIP_SIDE_PADDING = 18
CHIP_CHAR_WIDTH = 10
CHIP_HEIGHT = 32
CHIP_RADIUS = 16


@dataclass(frozen=True)
class Banner:
    filename: str
    title: str
    eyebrow: str
    subtitle: str = ""
    chips: tuple[str, ...] = field(default_factory=tuple)
    variant: str = "section"
    accent: str = "blue"
    index: str = ""


def split_lines(text: str, width: int) -> list[str]:
    if "\n" in text:
        return [line.strip() for line in text.splitlines() if line.strip()]
    return wrap(text, width=width) or [text]


def text_block(
    lines: Iterable[str],
    *,
    x: int,
    y: int,
    size: int,
    fill: str,
    weight: int = 700,
    family: str = "IBM Plex Sans, Avenir Next, Segoe UI, Helvetica Neue, Arial, sans-serif",
    line_height: float = 1.08,
    letter_spacing: str = "-0.04em",
) -> str:
    rendered: list[str] = []
    dy = 0
    for line in lines:
        rendered.append(
            f'<text x="{x}" y="{y + dy}" fill="{fill}" font-size="{size}" '
            f'font-weight="{weight}" letter-spacing="{letter_spacing}" '
            f'font-family="{family}">{escape(line)}</text>'
        )
        dy += int(size * line_height)
    return "".join(rendered)


def chip(
    label: str,
    *,
    x: int,
    y: int,
    fill: str,
    stroke: str,
    text_fill: str,
) -> str:
    width = chip_width(label)
    return (
        f'<g transform="translate({x},{y})">'
        f'<rect width="{width}" height="{CHIP_HEIGHT}" rx="{CHIP_RADIUS}" fill="{fill}" '
        f'stroke="{stroke}" stroke-width="1.5"/>'
        f'<text x="{width / 2}" y="21" text-anchor="middle" fill="{text_fill}" '
        f'font-size="13" font-weight="700" letter-spacing="0.08em" '
        f'font-family="IBM Plex Sans, Avenir Next, Segoe UI, Helvetica Neue, Arial, sans-serif">'
        f"{escape(label.upper())}</text></g>"
    )


def chip_width(label: str) -> int:
    return (CHIP_SIDE_PADDING * 2) + (len(label) * CHIP_CHAR_WIDTH)


def stacked_chips(
    labels: tuple[str, ...],
    *,
    x: int,
    y: int,
    fill: str,
    stroke: str,
    text_fill: str,
    gap: int = 10,
) -> str:
    chunks: list[str] = []
    for index, label in enumerate(labels):
        chunks.append(
            chip(
                label,
                x=x,
                y=y + (index * (CHIP_HEIGHT + gap)),
                fill=fill,
                stroke=stroke,
                text_fill=text_fill,
            )
        )
    return "".join(chunks)


def grid_pattern(pattern_id: str) -> str:
    return (
        f'<defs><pattern id="{pattern_id}" width="64" height="64" '
        f'patternUnits="userSpaceOnUse">'
        f'<path d="M 64 0 L 0 0 0 64" fill="none" stroke="{PALETTE["line"]}" '
        f'stroke-opacity="0.07" stroke-width="1"/>'
        f"</pattern></defs>"
    )


def hero_banner(banner: Banner) -> str:
    width = 1600
    height = 320
    accent = ACCENTS[banner.accent]
    pattern_id = f"grid-{banner.filename.replace('.', '-')}"
    title_lines = split_lines(banner.title, 18)
    subtitle_lines = split_lines(banner.subtitle, 56) if banner.subtitle else []
    eyebrow_lines = split_lines(banner.eyebrow.upper(), 12)
    title_size = 70 if len(title_lines) == 1 else 58
    title_y = 110 if len(title_lines) == 1 else 98
    subtitle_size = 22 if len(subtitle_lines) <= 1 else 20
    subtitle_y = 202 if len(title_lines) == 1 else 192
    chip_start_x = width - max((chip_width(label) for label in banner.chips), default=0) - 72
    chip_markup = stacked_chips(
        banner.chips,
        x=chip_start_x,
        y=46,
        fill=PALETTE["surface"],
        stroke=accent,
        text_fill=PALETTE["ink"],
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" fill="none" role="img" aria-label="{escape(banner.title)}">
{grid_pattern(pattern_id)}
<rect width="{width}" height="{height}" rx="30" fill="{PALETTE["bg"]}"/>
<rect x="10" y="10" width="{width - 20}" height="{height - 20}" rx="24" fill="url(#{pattern_id})" stroke="{PALETTE["line"]}" stroke-width="2"/>
<rect x="26" y="26" width="250" height="{height - 52}" rx="20" fill="{accent}"/>
<path d="M 66 252 H 210" stroke="{PALETTE["surface"]}" stroke-width="4" stroke-linecap="round"/>
<path d="M 66 274 H 178" stroke="{PALETTE["surface"]}" stroke-opacity="0.72" stroke-width="4" stroke-linecap="round"/>
<text x="58" y="82" fill="{PALETTE["surface"]}" font-size="18" font-weight="700" letter-spacing="0.30em" font-family="IBM Plex Mono, SFMono-Regular, Menlo, Consolas, monospace">{escape(banner.index or "00")}</text>
{text_block(eyebrow_lines, x=58, y=122, size=14, fill=PALETTE["surface"], weight=700, family="IBM Plex Mono, SFMono-Regular, Menlo, Consolas, monospace", line_height=1.42, letter_spacing="0.05em")}
{text_block(title_lines, x=324, y=title_y, size=title_size, fill=PALETTE["ink"], weight=760, line_height=1.16)}
{text_block(subtitle_lines, x=328, y=subtitle_y, size=subtitle_size, fill=PALETTE["muted"], weight=600, family="IBM Plex Sans, Avenir Next, Segoe UI, Helvetica Neue, Arial, sans-serif", line_height=1.34, letter_spacing="-0.01em")}
{chip_markup}
</svg>
"""


def section_banner(banner: Banner) -> str:
    width = 1400
    height = 170
    accent = ACCENTS[banner.accent]
    pattern_id = f"grid-{banner.filename.replace('.', '-')}"
    title_lines = split_lines(banner.title, 26)
    subtitle_lines = split_lines(banner.subtitle, 64) if banner.subtitle else []
    eyebrow_lines = split_lines(banner.eyebrow.upper(), 13)
    title_size = 40 if len(title_lines) == 1 else 34
    title_y = 72 if len(title_lines) == 1 else 64
    subtitle_size = 17 if len(subtitle_lines) <= 1 else 16
    subtitle_y = 120 if len(title_lines) == 1 else 118
    chip_start_x = width - max((chip_width(label) for label in banner.chips[:2]), default=0) - 48
    chip_markup = stacked_chips(
        banner.chips[:2],
        x=chip_start_x,
        y=28,
        fill=PALETTE["surface"],
        stroke=accent,
        text_fill=PALETTE["ink"],
        gap=8,
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" fill="none" role="img" aria-label="{escape(banner.title)}">
{grid_pattern(pattern_id)}
<rect width="{width}" height="{height}" rx="24" fill="{PALETTE["bg"]}"/>
<rect x="8" y="8" width="{width - 16}" height="{height - 16}" rx="18" fill="url(#{pattern_id})" stroke="{PALETTE["line"]}" stroke-width="2"/>
<rect x="24" y="24" width="148" height="{height - 48}" rx="18" fill="{accent}"/>
<text x="50" y="68" fill="{PALETTE["surface"]}" font-size="18" font-weight="700" letter-spacing="0.28em" font-family="IBM Plex Mono, SFMono-Regular, Menlo, Consolas, monospace">{escape((banner.index or "00").zfill(2))}</text>
{text_block(eyebrow_lines, x=50, y=100, size=13, fill=PALETTE["surface"], weight=700, family="IBM Plex Mono, SFMono-Regular, Menlo, Consolas, monospace", line_height=1.4, letter_spacing="0.06em")}
{text_block(title_lines, x=206, y=title_y, size=title_size, fill=PALETTE["ink"], weight=760, line_height=1.16)}
{text_block(subtitle_lines, x=210, y=subtitle_y, size=subtitle_size, fill=PALETTE["muted"], weight=600, family="IBM Plex Sans, Avenir Next, Segoe UI, Helvetica Neue, Arial, sans-serif", line_height=1.34, letter_spacing="-0.01em")}
{chip_markup}
</svg>
"""


def render_banner(banner: Banner) -> str:
    if banner.variant == "hero":
        return hero_banner(banner)
    return section_banner(banner)


BANNERS: tuple[Banner, ...] = (
    Banner(
        filename="root-hero.svg",
        title="Dotfiles",
        eyebrow="cross-platform bootstrap",
        subtitle="macOS and Windows setup, config, audit, and repair surfaces",
        chips=("brew + scoop", "mise + dotfiles"),
        variant="hero",
        accent="blue",
        index="00",
    ),
    Banner(
        filename="root-quick-start.svg",
        title="Quick start",
        eyebrow="root readme",
        subtitle="Use the public loaders first, then let the repo-local flow take over.",
        chips=("macOS", "Windows"),
        accent="ember",
        index="01",
    ),
    Banner(
        filename="root-bootstrap-overview.svg",
        title="How the bootstrap works",
        eyebrow="execution model",
        subtitle="One public entry surface, one shared foundation layer, and one optional personal layer.",
        chips=("diagram", "workflow"),
        accent="blue",
        index="02",
    ),
    Banner(
        filename="root-managed-surfaces.svg",
        title="What this repo manages",
        eyebrow="repo map",
        subtitle="Bootstrap logic, managed configuration, generated docs assets, and platform repair paths.",
        chips=("configs", "scripts"),
        accent="teal",
        index="03",
    ),
    Banner(
        filename="root-installation-layers.svg",
        title="Installation layers",
        eyebrow="tool split",
        subtitle="Immediate shell tooling lands first. Language runtimes and personal config follow.",
        chips=("homebrew", "mise"),
        accent="gold",
        index="04",
    ),
    Banner(
        filename="root-daily-operations.svg",
        title="Daily operations",
        eyebrow="steady state",
        subtitle="Keep normal maintenance on the same public ensure, update, audit, and repair surfaces.",
        chips=("ensure", "update"),
        accent="teal",
        index="05",
    ),
    Banner(
        filename="root-troubleshooting.svg",
        title="Troubleshooting",
        eyebrow="repair paths",
        subtitle="Start with idempotent reruns, then use the explicit recovery paths before manual edits.",
        chips=("ensure", "re-sign"),
        accent="ember",
        index="06",
    ),
    Banner(
        filename="root-unmanaged-tools.svg",
        title="Unmanaged tools",
        eyebrow="state boundary",
        subtitle="Keep stable config in git and leave runtime logs, sessions, caches, and tokens machine-local.",
        chips=("claude", "codex"),
        accent="lavender",
        index="07",
    ),
    Banner(
        filename="root-references.svg",
        title="References",
        eyebrow="external tools",
        subtitle="The bootstrap stands on Homebrew, Scoop, mise, Tuckr, and the rest of the toolchain.",
        chips=("tooling", "links"),
        accent="blue",
        index="08",
    ),
    Banner(
        filename="scripts-hero.svg",
        title="Bootstrap scripts",
        eyebrow="repo-local execution",
        subtitle="The detailed operator contract for setup, ensure, update, audit, and repair across macOS and Windows.",
        chips=("entrypoints", "flows"),
        variant="hero",
        accent="ember",
        index="10",
    ),
    Banner(
        filename="scripts-start-here.svg",
        title="Start here",
        eyebrow="operator path",
        subtitle="Choose the public loader first, then drop to repo-local wrappers only when you need tighter control.",
        chips=("install.sh", "install.cmd"),
        accent="blue",
        index="11",
    ),
    Banner(
        filename="scripts-mental-model.svg",
        title="Mental model",
        eyebrow="shared contract",
        subtitle="Both platforms keep the same operator model even when the execution plumbing differs.",
        chips=("foundation", "personal"),
        accent="teal",
        index="12",
    ),
    Banner(
        filename="scripts-bootstrap-flow.svg",
        title="Bootstrap flow",
        eyebrow="launch path",
        subtitle="Which file runs first, what it dispatches next, and where Windows inserts its signing guard.",
        chips=("router", "signing"),
        accent="ember",
        index="13",
    ),
    Banner(
        filename="scripts-foundation-flow.svg",
        title="Foundation flow",
        eyebrow="setup | ensure | update",
        subtitle="The shared install and repair sequence that prepares the machine before optional personal handoff.",
        chips=("tooling", "validation"),
        accent="gold",
        index="14",
    ),
    Banner(
        filename="scripts-audit-flow.svg",
        title="Audit flow",
        eyebrow="read-only state",
        subtitle="Inspect machine state without changing it, or persist discovered state on Windows when you ask for it.",
        chips=("json", "populate"),
        accent="lavender",
        index="15",
    ),
    Banner(
        filename="scripts-ownership-map.svg",
        title="Script ownership map",
        eyebrow="file roles",
        subtitle="Map the public loaders, repo-local routers, implementation files, and helper libraries by responsibility.",
        chips=("macOS", "Windows"),
        accent="blue",
        index="16",
    ),
    Banner(
        filename="scripts-shared-contract.svg",
        title="Shared contract",
        eyebrow="stable defaults",
        subtitle="Profiles, modes, state resolution, and dry-run behaviour stay legible across both platforms.",
        chips=("profiles", "flags"),
        accent="teal",
        index="17",
    ),
    Banner(
        filename="scripts-profiles-flags.svg",
        title="Profiles and flags",
        eyebrow="operator controls",
        subtitle="Keep the common path short with profiles, then override only the flags that need to change on a specific machine.",
        chips=("profiles", "feature flags"),
        accent="gold",
        index="18",
    ),
    Banner(
        filename="scripts-recommended-commands.svg",
        title="Recommended commands",
        eyebrow="normal operations",
        subtitle="The shortest command set for setup, repair, audit, and focused local debugging.",
        chips=("public", "local"),
        accent="ember",
        index="19",
    ),
    Banner(
        filename="scripts-direct-help.svg",
        title="Direct help and debugging",
        eyebrow="inspection path",
        subtitle="Use wrapper help for operators and direct implementation help only when you are debugging internals.",
        chips=("help", "get-help"),
        accent="gold",
        index="20",
    ),
    Banner(
        filename="scripts-manual-recovery.svg",
        title="Manual recovery reference",
        eyebrow="temporary fallback",
        subtitle="A temporary macOS-only escape hatch that should disappear once the overhaul closes the automation gap.",
        chips=("temporary", "macOS"),
        accent="lavender",
        index="21",
    ),
    Banner(
        filename="scripts-faq.svg",
        title="FAQ",
        eyebrow="windows edge cases",
        subtitle="Why the `.cmd` wrapper layer exists and how to call it safely from PowerShell or Windows PowerShell 5.1.",
        chips=("cmd", "ps1"),
        accent="blue",
        index="22",
    ),
    Banner(
        filename="scripts-validation-roadmap.svg",
        title="Validation roadmap",
        eyebrow="next proof points",
        subtitle="Focus the remaining work on machine validation, CI coverage, and removing fallback paths rather than changing the model again.",
        chips=("ci", "bare metal"),
        accent="teal",
        index="23",
    ),
    Banner(
        filename="configs-hero.svg",
        title="Config groups",
        eyebrow="managed surfaces",
        subtitle="The map of what gets symlinked on macOS, copied on Windows, and kept out of the repo.",
        chips=("tuckr", "copy rules"),
        variant="hero",
        accent="teal",
        index="30",
    ),
    Banner(
        filename="configs-platform-model.svg",
        title="How config management works",
        eyebrow="platform behaviour",
        subtitle="macOS symlinks managed files into place. Windows copies selected config with explicit ownership and drift checks.",
        chips=("macOS", "Windows"),
        accent="blue",
        index="31",
    ),
    Banner(
        filename="configs-group-reference.svg",
        title="Config group reference",
        eyebrow="inventory",
        subtitle="Every managed group, where it lands in HOME, and which platform owns it.",
        chips=("paths", "ownership"),
        accent="gold",
        index="32",
    ),
    Banner(
        filename="configs-add-group.svg",
        title="Adding a new config group",
        eyebrow="extension path",
        subtitle="Mirror the target path, then wire the group into Tuckr or the Windows copy layer only when needed.",
        chips=("authoring", "onboarding"),
        accent="ember",
        index="33",
    ),
    Banner(
        filename="configs-remove-group.svg",
        title="Removing a config group",
        eyebrow="cleanup path",
        subtitle="Remove the symlink or copy path first, then delete the group once no platform flow still owns it.",
        chips=("cleanup", "safety"),
        accent="lavender",
        index="34",
    ),
)


def main() -> None:
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    for banner in BANNERS:
        output_path = ASSETS_DIR / banner.filename
        output_path.write_text(render_banner(banner), encoding="utf-8")
    print(f"Generated {len(BANNERS)} README banner assets in {ASSETS_DIR}")


if __name__ == "__main__":
    main()
