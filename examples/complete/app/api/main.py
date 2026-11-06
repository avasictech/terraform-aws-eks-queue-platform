"""Minimal HTTP producer: POST /jobs puts the request body on SQS."""

import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("api")

QUEUE_URL = os.environ["QUEUE_URL"]
PORT = int(os.environ.get("PORT", "8080"))
MAX_BODY = 256 * 1024  # SQS message size limit

sqs = boto3.client("sqs")


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self._reply(200, {"status": "ok"})
        else:
            self._reply(404, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/jobs":
            self._reply(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0 or length > MAX_BODY:
            self._reply(400, {"error": "body must be 1 byte to 256 KiB"})
            return
        body = self.rfile.read(length).decode()
        try:
            json.loads(body)
        except ValueError:
            self._reply(400, {"error": "body must be JSON"})
            return
        resp = sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=body)
        self._reply(202, {"id": resp["MessageId"]})

    def log_message(self, fmt: str, *args) -> None:
        log.info("%s %s", self.address_string(), fmt % args)


if __name__ == "__main__":
    log.info("listening on :%d", PORT)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
