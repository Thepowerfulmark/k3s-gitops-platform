"""Publish JSON through the broker HTTP API."""

import base64
import json
import os
import urllib.error
import urllib.request
from urllib.parse import quote


def _required(name):
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"missing {name}")
    return value


class Publisher:
    def __init__(self, host, http_port, user, password, vhost, queue_name):
        self.host = host
        self.http_port = http_port
        self.user = user
        self.password = password
        self.vhost = vhost
        self.queue_name = queue_name

    @classmethod
    def from_env(cls):
        return cls(
            host=_required("RABBITMQ_HOST"),
            http_port=os.environ.get("RABBITMQ_HTTP_PORT", "15672"),
            user=_required("RABBITMQ_USER"),
            password=_required("RABBITMQ_PASSWORD"),
            vhost=_required("RABBITMQ_VHOST"),
            queue_name=os.environ.get("QUEUE_NAME", "items"),
        )

    def _url(self, path):
        return f"http://{self.host}:{self.http_port}{path}"

    def _call(self, method, path, payload=None):
        data = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(self._url(path), data=data, method=method)
        token = base64.b64encode(f"{self.user}:{self.password}".encode()).decode()
        req.add_header("Authorization", f"Basic {token}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:180]
            raise RuntimeError(f"broker http {exc.code}: {detail}") from exc
        if not raw:
            return {}
        return json.loads(raw.decode())

    def _vhost(self):
        return quote(self.vhost, safe="")

    def declare(self):
        path = f"/api/queues/{self._vhost()}/{quote(self.queue_name, safe='')}"
        self._call("PUT", path, {"durable": True, "auto_delete": False})

    def publish(self, item):
        path = f"/api/exchanges/{self._vhost()}/amq.default/publish"
        body = self._call(
            "POST",
            path,
            {
                "properties": {"content_type": "application/json", "delivery_mode": 2},
                "routing_key": self.queue_name,
                "payload": json.dumps(item),
                "payload_encoding": "string",
            },
        )
        if not body.get("routed"):
            raise RuntimeError("broker did not route the item")

    def ping(self):
        self._call("GET", "/api/overview")
