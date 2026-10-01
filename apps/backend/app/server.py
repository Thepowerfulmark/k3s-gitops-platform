"""HTTP server and the migrate entry."""

import json
import os
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from app.queue import Publisher
from app.service import create_item, health, list_items, live
from app.store import Store


class Handler(BaseHTTPRequestHandler):
    store = None
    publisher = None
    health_path = "/health"
    live_path = "/healthz"

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def _send(self, status, payload):
        raw = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _path(self):
        return self.path.split("?", 1)[0]

    def do_GET(self):
        path = self._path()
        if path == self.live_path:
            status, body = live()
        elif path == self.health_path:
            status, body = health(self.store, self.publisher)
        elif path == "/api/items":
            status, body = list_items(self.store)
        else:
            status, body = 404, {"error": "not found"}
        self._send(status, body)

    def do_POST(self):
        if self._path() != "/api/items":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length > 4096:
            self._send(413, {"error": "body is too large"})
            return
        raw = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "expected json"})
            return
        status, body = create_item(self.store, self.publisher, payload)
        self._send(status, body)


def _retry(label, fn, attempts=60, delay=2):
    last = None
    for attempt in range(1, attempts + 1):
        try:
            fn()
            print(f"{label}: ready", flush=True)
            return True
        except Exception as exc:
            last = exc
            print(f"{label}: waiting ({attempt}/{attempts}): {exc}", flush=True)
            time.sleep(delay)
    print(f"{label}: failed: {last}", flush=True)
    return False


def migrate():
    store = Store.from_env()
    if _retry("migrate", store.migrate):
        return 0
    return 1


def serve():
    store = Store.from_env()
    publisher = Publisher.from_env()
    threading.Thread(target=_retry, args=("queue", publisher.declare), daemon=True).start()
    Handler.store = store
    Handler.publisher = publisher
    Handler.health_path = os.environ.get("HEALTH_PATH", "/health")
    Handler.live_path = os.environ.get("LIVE_PATH", "/healthz")
    port = int(os.environ.get("PORT", "8080"))
    httpd = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    httpd.daemon_threads = True

    def stop(signum, _frame):
        print(f"stopping on signal {signum}", flush=True)
        httpd.shutdown()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(f"listening on {port}", flush=True)
    httpd.serve_forever()
    return 0
