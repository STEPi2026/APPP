"""Serve a compiled STEPi web preview and its fixed backend on one LAN origin.

No credentials are stored, no API responses are cached, and the upstream cannot
be selected by a browser request. Production/native API settings are unchanged.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib import error, parse, request

MAX_BODY = 11 * 1024 * 1024


class SameBackendRedirect(request.HTTPRedirectHandler):
    def __init__(self, origin: str):
        self.origin = parse.urlsplit(origin).netloc

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if parse.urlsplit(newurl).netloc != self.origin:
            raise error.HTTPError(newurl, 502, "Upstream redirect rejected", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, directory, backend, bind_host, port, **kwargs):
        self.backend = backend.rstrip("/").removesuffix("/api/v1")
        self.allowed_hosts = {bind_host, "localhost", "127.0.0.1"}
        self.port = port
        self.root = Path(directory).resolve()
        self.upstream = request.build_opener(SameBackendRedirect(self.backend))
        super().__init__(*args, directory=str(self.root), **kwargs)

    def log_message(self, fmt, *args):
        # Neither query strings, headers, tokens nor request bodies go to logs.
        pass

    def _json(self, status, code, message):
        body = json.dumps({"code": code, "message": message}, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _valid_origin(self):
        try:
            host = parse.urlsplit("http://" + self.headers.get("Host", ""))
            if host.hostname not in self.allowed_hosts or host.port != self.port:
                return False
            origin = self.headers.get("Origin")
            if origin:
                source = parse.urlsplit(origin)
                if source.scheme != "http" or source.hostname not in self.allowed_hosts or source.port != self.port:
                    return False
            return True
        except ValueError:
            return False

    def _route(self):
        if not self._valid_origin():
            self._json(403, "PREVIEW_ORIGIN_REJECTED", "이 접속 주소는 사용할 수 없어요.")
            return
        path = parse.urlsplit(self.path).path
        if path.startswith("/api/v1/"):
            self._proxy()
        elif path == "/__preview/status" and self.command == "GET":
            body = json.dumps({"app": "stepi-mobile-preview", "api_mode": "same-origin", "pid": os.getpid()}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.command in {"GET", "HEAD"}:
            if self.command == "HEAD":
                super().do_HEAD()
            else:
                super().do_GET()
        else:
            self._json(405, "PREVIEW_METHOD_NOT_ALLOWED", "이 요청은 사용할 수 없어요.")

    do_GET = do_HEAD = do_POST = do_PATCH = do_PUT = do_DELETE = do_OPTIONS = _route

    def list_directory(self, path):
        self._json(404, "PREVIEW_NOT_FOUND", "페이지를 찾지 못했어요.")
        return None

    def send_head(self):
        # Serve compiled assets only; reject traversal and symlinks outside root.
        target = Path(self.translate_path(self.path)).resolve()
        if not target.is_relative_to(self.root):
            self._json(403, "PREVIEW_PATH_REJECTED", "파일을 열 수 없어요.")
            return None
        return super().send_head()

    def end_headers(self):
        if not self.path.startswith("/api/v1/"):
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Frame-Options", "DENY")
        super().end_headers()

    def _body(self):
        transfer = self.headers.get("Transfer-Encoding", "").lower()
        if transfer:
            if transfer != "chunked":
                raise ValueError("Unsupported transfer")
            body = bytearray()
            while True:
                line = self.rfile.readline(128)
                size = int(line.split(b";", 1)[0].strip(), 16)
                if size < 0 or len(body) + size > MAX_BODY:
                    raise OverflowError()
                if size == 0:
                    # Consume a bounded trailer, without forwarding it.
                    for _ in range(50):
                        if self.rfile.readline(8192) in (b"\r\n", b"\n", b""):
                            return bytes(body)
                    raise ValueError("Too many trailers")
                part = self.rfile.read(size)
                if len(part) != size or self.rfile.read(2) != b"\r\n":
                    raise ValueError("Incomplete body")
                body.extend(part)
        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > MAX_BODY:
            raise OverflowError()
        body = self.rfile.read(length)
        if len(body) != length:
            raise ValueError("Incomplete body")
        return body if length else None

    def _proxy(self):
        decoded = parse.unquote(parse.urlsplit(self.path).path)
        if ".." in decoded.split("/") or "\\" in decoded:
            self._json(400, "PREVIEW_PATH_REJECTED", "올바르지 않은 요청 주소예요.")
            return
        try:
            body = self._body()
        except OverflowError:
            self._json(413, "IMAGE_TOO_LARGE", "사진은 10MB 이하로 선택해 주세요.")
            return
        except (ValueError, OSError):
            self._json(400, "PREVIEW_INVALID_BODY", "요청 내용을 확인해 주세요.")
            return
        headers = {"ngrok-skip-browser-warning": "true"}
        for name in ("Authorization", "Content-Type", "Accept"):
            if self.headers.get(name):
                headers[name] = self.headers[name]
        req = request.Request(self.backend + self.path, data=body, headers=headers, method=self.command)
        try:
            try:
                response = self.upstream.open(req, timeout=60)
            except error.HTTPError as e:
                response = e
            with response:
                payload = response.read()
                content_type = response.headers.get("Content-Type", "application/json")
                if "text/html" in content_type or b"ERR_NGROK_3200" in payload[:2048]:
                    self._json(503, "PREVIEW_BACKEND_OFFLINE", "학습 서버가 아직 열리지 않았어요. 서버가 준비된 뒤 다시 시도해 주세요.")
                    return
                self.send_response(response.code)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(payload)
        except (error.URLError, TimeoutError, OSError):
            self._json(503, "PREVIEW_BACKEND_OFFLINE", "학습 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")


def make_server(root, backend, bind_host, port):
    server = ThreadingHTTPServer((bind_host, port), PreviewHandler)
    server.RequestHandlerClass = partial(PreviewHandler, directory=root, backend=backend, bind_host=bind_host, port=server.server_port)
    return server


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--bind", required=True)
    args.add_argument("--port", type=int, default=8090)
    args.add_argument("--backend", required=True)
    args.add_argument("--root", required=True)
    config = args.parse_args()
    backend = parse.urlsplit(config.backend)
    if backend.scheme != "https" or not backend.hostname or backend.username or backend.password or backend.path not in ("", "/", "/api/v1") or backend.query or backend.fragment:
        args.error("Backend must be an HTTPS origin (optionally /api/v1).")
    root = Path(config.root).resolve()
    if not (root / "index.html").is_file():
        args.error("Build the mobile web preview first.")
    mimetypes.add_type("application/wasm", ".wasm")
    print(f"STEPi preview: http://{config.bind}:{config.port}/", flush=True)
    with make_server(str(root), config.backend, config.bind, config.port) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
