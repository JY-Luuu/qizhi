import importlib.util
import io
import json
from pathlib import Path
import struct
import base64
import hashlib
import shutil
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("capture_host", Path(__file__).with_name("capture-host.py"))
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


class CaptureHostTests(unittest.TestCase):
    def test_extension_public_key_matches_allowed_origin(self):
        manifest = json.loads((Path(__file__).resolve().parent.parent / 'ChromeExtension/manifest.json').read_text())
        digest = hashlib.sha256(base64.b64decode(manifest['key'], validate=True)).hexdigest()[:32]
        extension_id = ''.join(chr(97 + int(nibble, 16)) for nibble in digest)
        self.assertEqual(extension_id, host.EXTENSION_ID)

    def test_native_process_capture_and_origin_isolation(self):
        capture = {'title': 'Personal capture', 'url': 'https://example.com/personal'}
        payload = json.dumps(capture).encode()
        frame = struct.pack('=I', len(payload)) + payload
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Qizhi'
            bridge = app / 'BrowserBridge'
            bridge.mkdir(parents=True)
            script = bridge / 'capture-host.py'
            shutil.copyfile(Path(__file__).with_name('capture-host.py'), script)
            def invoke(origin):
                result = subprocess.run([sys.executable, str(script), origin], input=frame,
                                        capture_output=True, check=True, timeout=5)
                return host.receive(io.BytesIO(result.stdout))
            denied = invoke('chrome-extension://ahkgcekpbdbdkgmkfefnlpacglodpiji/')
            self.assertFalse(denied['ok'])
            self.assertFalse((app / 'Inbox').exists())
            accepted = invoke(f'chrome-extension://{host.EXTENSION_ID}/')
            self.assertTrue(accepted['ok'])
            captures = list((app / 'Inbox').glob('*.json'))
            self.assertEqual(len(captures), 1)
            self.assertEqual(json.loads(captures[0].read_text()), capture)

    def test_native_frame_and_atomic_inbox_delivery(self):
        capture = {"title": "视频学习", "url": "https://example.com/watch?t=123"}
        payload = json.dumps(capture).encode()
        message = host.receive(io.BytesIO(struct.pack("=I", len(payload)) + payload))
        with tempfile.TemporaryDirectory() as directory:
            inbox = Path(directory) / "Inbox"
            host.save_capture(message, inbox)
            files = list(inbox.iterdir())
            self.assertEqual(len(files), 1)
            self.assertEqual(files[0].suffix, ".json")
            self.assertEqual(json.loads(files[0].read_text()), capture)

    def test_invalid_input_never_reaches_inbox(self):
        with tempfile.TemporaryDirectory() as directory:
            inbox = Path(directory) / "Inbox"
            for capture in [
                {"title": "bad", "url": "javascript:alert(1)"},
                {"title": "bad", "url": "https://user:pass@example.com"},
                {"title": "bad", "url": "https://example.com", "screenshot": "ZmFrZQ=="},
                {"title": 123, "url": "https://example.com"},
            ]:
                with self.assertRaises(ValueError):
                    host.save_capture(capture, inbox)
            self.assertFalse(inbox.exists())

    def test_short_or_oversized_frame_is_rejected(self):
        for frame in [b"", struct.pack("=I", 100) + b"{}", struct.pack("=I", host.MAX_MESSAGE_BYTES + 1)]:
            with self.assertRaises(ValueError):
                host.receive(io.BytesIO(frame))


if __name__ == "__main__":
    unittest.main()
