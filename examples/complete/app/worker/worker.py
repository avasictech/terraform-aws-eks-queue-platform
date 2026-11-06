"""SQS consumer that shuts down cleanly when KEDA/HPA scales it down.

On SIGTERM it stops receiving new messages, finishes the message(s) it holds
(each message is deleted only after it is processed), and exits. Anything it
could not finish becomes visible again after the visibility timeout and is
picked up by another pod, so processing must be idempotent.
"""

import json
import logging
import os
import random
import signal
import time

import boto3

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("worker")

QUEUE_URL = os.environ["QUEUE_URL"]
MAX_PROCESSING_SECONDS = int(os.environ.get("MAX_PROCESSING_SECONDS", "45"))
# Messages held at once. Raise it only if the queue's visibility timeout and the
# pod's terminationGracePeriodSeconds both exceed BATCH_SIZE * MAX_PROCESSING_SECONDS.
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "1"))
DOWNSTREAM_API_TOKEN = os.environ["DOWNSTREAM_API_TOKEN"]  # from External Secrets

sqs = boto3.client("sqs")
stopping = False


def handle_sigterm(signum, frame) -> None:
    global stopping
    log.info("SIGTERM received, finishing current batch")
    stopping = True


def process(body: dict) -> None:
    # Stand-in for real work, e.g. calling a downstream API with DOWNSTREAM_API_TOKEN.
    # I/O-bound: the pod waits, CPU stays low, which is why CPU is a bad scaling signal.
    time.sleep(random.uniform(0.2, 1.0))


def main() -> None:
    signal.signal(signal.SIGTERM, handle_sigterm)
    log.info("consuming %s", QUEUE_URL)

    while not stopping:
        resp = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=BATCH_SIZE,
            WaitTimeSeconds=20,  # long polling: no busy loop on an empty queue
        )
        for msg in resp.get("Messages", []):
            started = time.monotonic()
            try:
                process(json.loads(msg["Body"]))
            except Exception:
                # Leave it on the queue; after maxReceiveCount it goes to the DLQ.
                log.exception("failed message %s", msg["MessageId"])
                continue
            sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
            log.info("done %s in %.2fs", msg["MessageId"], time.monotonic() - started)

    log.info("stopped cleanly")


if __name__ == "__main__":
    main()
