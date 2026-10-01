import json
import logging
import os
import tempfile
import time
from urllib.parse import unquote_plus

import boto3
import torch
from botocore.exceptions import ClientError
from ultralytics import YOLO


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

logger = logging.getLogger(__name__)


# --------------------------------------------------
# Environment variables
# --------------------------------------------------

SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]

MODEL_BUCKET = os.environ["MODEL_BUCKET"]
MODEL_PATH = os.environ["MODEL_PATH"]

RESULTS_BUCKET = os.environ["RESULTS_BUCKET"]

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

LOCAL_MODEL_PATH = "/tmp/model.pt"

# Inference config
IMG_SIZE = int(os.getenv("IMG_SIZE", "1280"))

# Batching config
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "8"))
BATCH_TIMEOUT_SECONDS = int(os.getenv("BATCH_TIMEOUT_SECONDS", "10"))
VISIBILITY_TIMEOUT = int(os.getenv("SQS_VISIBILITY_TIMEOUT", "300"))


# --------------------------------------------------
# AWS clients
# --------------------------------------------------

s3 = boto3.client(
    "s3",
    region_name=AWS_REGION,
)

sqs = boto3.client(
    "sqs",
    region_name=AWS_REGION,
)


# --------------------------------------------------
# AWS access checks
# --------------------------------------------------

def check_s3_access():
    """
    Verify that the worker can:

    1. Read the model from S3.
    2. Write results to the results bucket.
    """

    logger.info("Checking S3 access...")

    try:
        s3.head_object(
            Bucket=MODEL_BUCKET,
            Key=MODEL_PATH,
        )

        logger.info(
            "S3 model access OK: s3://%s/%s",
            MODEL_BUCKET,
            MODEL_PATH,
        )

        s3.get_bucket_location(
            Bucket=RESULTS_BUCKET,
        )

        logger.info(
            "S3 results bucket access OK: %s",
            RESULTS_BUCKET,
        )

    except ClientError as exc:
        logger.error(
            "S3 access check failed: %s",
            exc,
        )
        raise RuntimeError(
            "GPU worker does not have the required S3 permissions."
        ) from exc


def check_sqs_access():
    """
    Verify that the worker can access the SQS queue.
    """

    logger.info("Checking SQS access...")

    try:
        sqs.get_queue_attributes(
            QueueUrl=SQS_QUEUE_URL,
            AttributeNames=["QueueArn"],
        )

        logger.info(
            "SQS access OK: %s",
            SQS_QUEUE_URL,
        )

        sqs.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=1,
        )

        logger.info("SQS ReceiveMessage permission OK")

    except ClientError as exc:
        logger.error(
            "SQS access check failed: %s",
            exc,
        )
        raise RuntimeError(
            "GPU worker does not have the required SQS permissions."
        ) from exc


# --------------------------------------------------
# CUDA / GPU verification
# --------------------------------------------------

def check_gpu():
    """
    Verify that CUDA and an NVIDIA GPU are available.
    """

    logger.info("Checking CUDA/GPU...")

    if not torch.cuda.is_available():
        raise RuntimeError(
            "CUDA is not available. GPU worker cannot start."
        )

    device = torch.device("cuda:0")

    logger.info("CUDA available: %s", torch.cuda.is_available())
    logger.info("CUDA version: %s", torch.version.cuda)
    logger.info("GPU: %s", torch.cuda.get_device_name(0))

    return device


# --------------------------------------------------
# Model loading
# --------------------------------------------------

def load_model(device):
    """
    Download the model from S3 and load it onto the GPU.
    """

    logger.info(
        "Downloading model from s3://%s/%s",
        MODEL_BUCKET,
        MODEL_PATH,
    )

    try:
        s3.download_file(
            MODEL_BUCKET,
            MODEL_PATH,
            LOCAL_MODEL_PATH,
        )

    except ClientError as exc:
        logger.error(
            "Failed to download model from S3: %s",
            exc,
        )
        raise RuntimeError(
            "Could not download model from S3."
        ) from exc

    logger.info("Model downloaded to %s", LOCAL_MODEL_PATH)
    logger.info("Loading YOLO model onto GPU...")

    model = YOLO(LOCAL_MODEL_PATH)
    model.to(device)

    logger.info("YOLO model loaded successfully on %s", device)

    return model


# --------------------------------------------------
# Batch collection
# --------------------------------------------------

def collect_batch():
    """
    Collect up to BATCH_SIZE messages from SQS, or whatever
    arrives within BATCH_TIMEOUT_SECONDS, whichever comes first.

    Uses long polling on each individual receive_message call so
    we don't busy-loop while waiting for the first message.
    """

    batch = []
    deadline = time.time() + BATCH_TIMEOUT_SECONDS

    while len(batch) < BATCH_SIZE:

        remaining = deadline - time.time()

        if remaining <= 0:
            break

        response = sqs.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=min(10, BATCH_SIZE - len(batch)),
            WaitTimeSeconds=min(20, max(1, int(remaining))),
            VisibilityTimeout=VISIBILITY_TIMEOUT,
        )

        batch.extend(response.get("Messages", []))

    return batch


# --------------------------------------------------
# Download a single message's image
# --------------------------------------------------

def download_image(message):
    """
    Parses an S3 event notification message and downloads the
    referenced image to a local temp file.

    Returns (input_bucket, input_key, local_path) or raises.
    """

    body = json.loads(message["Body"])
    record = body["Records"][0]

    input_bucket = record["s3"]["bucket"]["name"]
    # S3 event notification keys are URL-encoded: spaces arrive as "+" and
    # anything non-alphanumeric is percent-encoded.
    input_key = unquote_plus(record["s3"]["object"]["key"])

    extension = os.path.splitext(input_key)[1]

    with tempfile.NamedTemporaryFile(
        suffix=extension,
        delete=False,
    ) as tmp:
        local_path = tmp.name

    s3.download_file(
        input_bucket,
        input_key,
        local_path,
    )

    return input_bucket, input_key, local_path


# --------------------------------------------------
# Upload a single result
# --------------------------------------------------

def upload_result(input_bucket, input_key, detections):

    output = {
        "input": {
            "bucket": input_bucket,
            "key": input_key,
        },
        "detections": detections,
    }

    # basename first -- input_key is "images/<uuid>.jpg", and without it the
    # result lands at "results/images/<uuid>.json".
    result_key = "results/" + os.path.splitext(os.path.basename(input_key))[0] + ".json"

    s3.put_object(
        Bucket=RESULTS_BUCKET,
        Key=result_key,
        Body=json.dumps(output),
        ContentType="application/json",
    )

    logger.info(
        "Results uploaded to s3://%s/%s",
        RESULTS_BUCKET,
        result_key,
    )


# --------------------------------------------------
# Process a batch of SQS messages
# --------------------------------------------------

def process_batch(messages, model):
    """
    Downloads every image in the batch, runs a single batched
    GPU forward pass, then uploads results and deletes messages
    individually so a failure on one image doesn't affect the
    others.
    """

    items = []  # list of dicts: message, bucket, key, local_path

    # --------------------------------------------------
    # Download phase (isolate failures per-message)
    # --------------------------------------------------

    for message in messages:

        try:
            input_bucket, input_key, local_path = download_image(message)

            items.append(
                {
                    "message": message,
                    "bucket": input_bucket,
                    "key": input_key,
                    "local_path": local_path,
                }
            )

        except Exception:
            logger.exception(
                "Failed to download image for message. "
                "Message will be retried."
            )
            # Not deleted -> becomes visible again after
            # VisibilityTimeout and gets retried.

    if not items:
        return

    logger.info("Running batched inference on %d image(s)", len(items))

    # --------------------------------------------------
    # Batched GPU inference
    # --------------------------------------------------

    sources = [item["local_path"] for item in items]

    # A failed batch is not retried per-image: messages stay undeleted, return
    # after VisibilityTimeout, and move to the DLQ after maxReceiveCount.
    try:
        # Without batch=, Ultralytics runs a list of sources one image at a time.
        results = model.predict(
            source=sources,
            device=0,
            imgsz=IMG_SIZE,
            batch=len(sources),
            verbose=False,
        )
    except Exception:
        for item in items:
            cleanup(item["local_path"])
        raise

    logger.info(
        "GPU memory peak reserved: %d MiB",
        torch.cuda.max_memory_reserved() // (1024 * 1024),
    )

    # --------------------------------------------------
    # Process each result
    # --------------------------------------------------

    for item, result in zip(items, results):

        try:
            detections = extract_detections(result)

            upload_result(item["bucket"], item["key"], detections)

            sqs.delete_message(
                QueueUrl=SQS_QUEUE_URL,
                ReceiptHandle=item["message"]["ReceiptHandle"],
            )

            logger.info("Message completed: s3://%s/%s", item["bucket"], item["key"])

        except Exception:
            logger.exception(
                "Failed to finalize result for s3://%s/%s. Message will be retried.",
                item["bucket"],
                item["key"],
            )

        finally:
            cleanup(item["local_path"])


def extract_detections(result):

    detections = []

    for box in result.boxes:
        detections.append(
            {
                "class_id": int(box.cls[0]),
                "confidence": float(box.conf[0]),
                "bbox": [float(x) for x in box.xyxy[0].tolist()],
            }
        )

    return detections


def cleanup(local_path):
    if local_path and os.path.exists(local_path):
        os.remove(local_path)


# --------------------------------------------------
# Worker loop
# --------------------------------------------------

def worker_loop(model):

    logger.info(
        "GPU worker started (batch_size=%d, batch_timeout=%ds, imgsz=%d)",
        BATCH_SIZE,
        BATCH_TIMEOUT_SECONDS,
        IMG_SIZE,
    )

    while True:

        batch = collect_batch()

        if not batch:
            continue

        logger.info("Collected batch of %d message(s)", len(batch))

        process_batch(batch, model)


# --------------------------------------------------
# Application startup
# --------------------------------------------------

def main():

    logger.info("Starting GPU worker...")

    check_s3_access()
    check_sqs_access()

    device = check_gpu()

    model = load_model(device)

    worker_loop(model)


if __name__ == "__main__":
    main()