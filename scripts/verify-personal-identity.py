#!/usr/bin/env python3
"""Verify the cross-language identities needed for an isolated personal install."""
from pathlib import Path
import base64
import hashlib
import json
import re

root = Path(__file__).resolve().parent.parent
project = json.loads((root / 'project.json').read_text())
manifest = json.loads((root / 'ChromeExtension/manifest.json').read_text())
digest = hashlib.sha256(base64.b64decode(manifest['key'], validate=True)).hexdigest()[:32]
actual_id = ''.join(chr(97 + int(nibble, 16)) for nibble in digest)
assert actual_id == project['extension_id'], 'Manifest public key changed the extension ID'
assert manifest['name'] == project['name']
assert manifest['version'] == project['version']
assert re.fullmatch(r'[a-z0-9_]+(?:\.[a-z0-9_]+)*', project['native_host_name'])
identity = (root / 'Sources/HangLaterCore/AppIdentity.swift').read_text()
for key in ['bundle_identifier', 'data_directory', 'native_host_name', 'extension_id']:
    assert f'"{project[key]}"' in identity, f'Swift identity differs for {key}'
for path in ['ChromeExtension/popup.js', 'ChromeExtension/background.js']:
    assert f'"{project["native_host_name"]}"' in (root / path).read_text(), path
assert f'EXTENSION_ID = "{actual_id}"' in (root / 'NativeHost/capture-host.py').read_text()
build = (root / 'scripts/build-app.sh').read_text()
assert f'<string>{project["bundle_identifier"]}</string>' in build
assert f'<string>{project["version"]}</string>' in build
assert 'build/Qizhi.app' in build
for path in ['Sources/HangLater/AppDelegate.swift', 'Sources/HangLater/main.swift']:
    source = (root / path).read_text()
    assert 'appendingPathComponent(AppIdentity.dataDirectoryName,' in source
    assert 'appendingPathComponent("HangLater",' not in source
assert 'Copyright (c) 2026 Yuxuan Fu' in (root / 'LICENSE').read_text()
assert 'Copyright (c) 2026 Alejandro Buján' in (root / 'THIRD_PARTY_NOTICES.md').read_text()
print(f'PASS: personal app, storage, host and extension identities agree ({actual_id})')
