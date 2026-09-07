#!/usr/bin/env python3
"""Refresh the readable runtime snapshot after source changes."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
files=[root/'shell.qml']
for directory in ('desktop','bar','launcher','launcher/audio','notifications','shared','Daevox/Notifications'):
    files.extend(sorted(p for p in (root/directory).iterdir() if p.suffix in ('.qml','.js') or p.name=='qmldir'))
files.extend(root/p for p in ('docs/examples/daevox-shell.service','docs/examples/hyprland-launcher.lua'))
parts=['# Исходники runtime Daevox Shell\n\nСнимок создаётся командой `python3 scripts/update-source-snapshot.py`.\n']
for p in files:
    language={'qml':'qml','js':'javascript','lua':'lua'}.get(p.suffix[1:],'ini')
    parts.append(f'\n## {p.relative_to(root)}\n\n```{language}\n{p.read_text().rstrip()}\n```\n')
(root/'docs/launcher-source.md').write_text(''.join(parts))
