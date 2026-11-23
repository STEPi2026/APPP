import http.client
from contextlib import closing
import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from mobile_preview import make_server


class Backend(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.reply()

    do_POST = do_PATCH = do_GET

    def reply(self):
        if self.path.endswith(("/offline", "/offline-plain")):
            self.send_response(404)
            self.send_header("Content-Type", "text/plain" if self.path.endswith("/offline-plain") else "text/html")
            self.end_headers()
            self.wfile.write(b"ERR_NGROK_3200")
        elif self.path.endswith("/redirect"):
            self.send_response(302)
            self.send_header("Content-Type", "application/json")
            self.send_header("Location", "http://example.invalid/secret")
            self.end_headers()
            self.wfile.write(b"{}")
        elif self.path.endswith("/image"):
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.end_headers()
            self.wfile.write(bytes([137, 80, 78, 71]))
        else:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else b""
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "path": self.path, "body": body.decode(),
                "authorization": self.headers.get("Authorization"),
                "skip": self.headers.get("ngrok-skip-browser-warning"),
                "cookie": self.headers.get("Cookie"),
            }).encode())


class MobilePreviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        Path(cls.temp.name, "index.html").write_text("STEPi mobile preview", encoding="utf-8")
        Path(cls.temp.name, "folder").mkdir()
        cls.backend = ThreadingHTTPServer(("127.0.0.1", 0), Backend)
        cls.frontend = make_server(cls.temp.name, f"http://127.0.0.1:{cls.backend.server_port}", "127.0.0.1", 0)
        for server in (cls.backend, cls.frontend):
            threading.Thread(target=server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        for server in (cls.frontend, cls.backend):
            server.shutdown()
            server.server_close()
        cls.temp.cleanup()

    def call(self, path, method="GET", body=None, headers=None, chunked=False):
        with closing(http.client.HTTPConnection("127.0.0.1", self.frontend.server_port, timeout=5)) as client:
            client.request(method, path, body=body, headers=headers or {}, encode_chunked=chunked)
            response = client.getresponse()
            return response.status, response.read(), response.getheader("Content-Type")

    def test_compiled_app_is_served(self):
        status, body, kind = self.call("/")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"STEPi mobile preview")

    def test_query_and_auth_forward_without_cookies(self):
        status, body, _ = self.call("/api/v1/me/xp-history?page=2", headers={"Authorization": "Bearer test-only", "Cookie": "unrelated=test"})
        data = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(data["path"], "/api/v1/me/xp-history?page=2")
        self.assertEqual(data["authorization"], "Bearer test-only")
        self.assertEqual(data["skip"], "true")
        self.assertIsNone(data["cookie"])

    def test_photo_body_and_json_pass_unchanged(self):
        _, body, _ = self.call("/api/v1/captured-problems", "POST", b"test-photo-body", {"Content-Type": "multipart/form-data; boundary=test"})
        self.assertEqual(json.loads(body)["body"], "test-photo-body")
        _, body, _ = self.call("/api/v1/captured-problems/1/ocr", "PATCH", b'{"problem_text":"2+3"}', {"Content-Type": "application/json"})
        self.assertEqual(json.loads(body)["body"], '{"problem_text":"2+3"}')

    def test_chunked_photo_body(self):
        _, body, _ = self.call("/api/v1/captured-problems", "POST", iter([b"one", b"two"]), {"Content-Type": "multipart/form-data; boundary=test"}, chunked=True)
        self.assertEqual(json.loads(body)["body"], "onetwo")

    def test_binary_image(self):
        status, body, kind = self.call("/api/v1/captured-problems/1/image")
        self.assertEqual((status, body, kind), (200, bytes([137, 80, 78, 71]), "image/png"))

    def test_ngrok_offline_is_not_reported_as_json_success(self):
        status, body, _ = self.call("/api/v1/offline")
        self.assertEqual(status, 503)
        self.assertEqual(json.loads(body)["code"], "PREVIEW_BACKEND_OFFLINE")
        self.assertEqual(self.call("/api/v1/offline-plain")[0], 503)

    def test_cross_site_origin_and_host_are_rejected(self):
        status, _, _ = self.call("/api/v1/auth/login", "POST", b"{}", {"Origin": "https://example.invalid"})
        self.assertEqual(status, 403)
        status, _, _ = self.call("/api/v1/me", headers={"Host": "example.invalid"})
        self.assertEqual(status, 403)

    def test_traversal_and_directory_listing_rejected(self):
        self.assertEqual(self.call("/api/v1/%2e%2e/admin")[0], 400)
        self.assertEqual(self.call("/folder/")[0], 404)

    def test_redirect_does_not_forward_auth_to_another_host(self):
        status, _, _ = self.call("/api/v1/redirect", headers={"Authorization": "Bearer test-only"})
        self.assertEqual(status, 502)


if __name__ == "__main__":
    unittest.main()
