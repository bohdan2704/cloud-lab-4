import base64
import json
import logging
import os
import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

import boto3
from botocore.exceptions import ClientError


LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

TABLE_NAME = os.environ["TABLE_NAME"]
AUDIT_BUCKET = os.environ["AUDIT_BUCKET"]
AUDIT_PREFIX = os.environ.get("AUDIT_PREFIX", "audit").strip("/") or "audit"
COMPREHEND_LANGUAGE_CODE = "en"

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
s3_client = boto3.client("s3")
comprehend_client = boto3.client("comprehend")


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            if obj % 1 == 0:
                return int(obj)
            return float(obj)
        return super().default(obj)


def build_response(
    status_code: int,
    body: dict[str, Any] | list[dict[str, Any]] | None = None,
    extra_headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    }
    if extra_headers:
        headers.update(extra_headers)

    response: dict[str, Any] = {
        "statusCode": status_code,
        "headers": headers,
        "body": "",
    }
    if body is not None:
        response["body"] = json.dumps(body, cls=DecimalEncoder)
    return response


def get_http_method(event: dict[str, Any]) -> str:
    request_context = event.get("requestContext") or {}
    http_context = request_context.get("http") or {}
    return (
        http_context.get("method")
        or request_context.get("httpMethod")
        or event.get("httpMethod")
        or ""
    ).upper()


def get_request_path(event: dict[str, Any]) -> str:
    return event.get("rawPath") or event.get("path") or "/"


def parse_body(event: dict[str, Any]) -> dict[str, Any]:
    raw_body = event.get("body")
    if raw_body in (None, ""):
        return {}

    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode("utf-8")

    payload = json.loads(raw_body)
    if not isinstance(payload, dict):
        raise ValueError("Request body must be a JSON object.")
    return payload


def put_audit_log(
    *,
    event: dict[str, Any],
    context: Any,
    response: dict[str, Any] | None,
    error_message: str | None,
) -> None:
    request_context = event.get("requestContext") or {}
    path_parameters = event.get("pathParameters") or {}
    now = datetime.now(UTC)
    request_id = request_context.get("requestId") or getattr(
        context, "aws_request_id", str(uuid.uuid4())
    )

    record = {
        "request_id": request_id,
        "timestamp": now.isoformat(),
        "method": get_http_method(event),
        "path": get_request_path(event),
        "path_parameters": path_parameters,
        "query_parameters": event.get("queryStringParameters") or {},
        "status_code": response.get("statusCode") if response else None,
        "error": error_message,
    }

    if response and response.get("body"):
        try:
            record["response_body"] = json.loads(response["body"])
        except json.JSONDecodeError:
            record["response_body"] = response["body"]

    key = f"{AUDIT_PREFIX}/{now:%Y/%m/%d}/{request_id}.json"

    try:
        s3_client.put_object(
            Bucket=AUDIT_BUCKET,
            Key=key,
            Body=json.dumps(record, cls=DecimalEncoder).encode("utf-8"),
            ContentType="application/json",
        )
    except Exception:
        LOGGER.exception("Failed to write audit log to S3.")


def create_note(event: dict[str, Any]) -> dict[str, Any]:
    body = parse_body(event)
    text = (body.get("text") or body.get("content") or "").strip()
    if not text:
        raise ValueError("Field 'text' is required.")

    note = {
        "id": str(uuid.uuid4()),
        "text": text,
        "created_at": datetime.now(UTC).isoformat(),
    }
    table.put_item(Item=note)

    return build_response(
        201,
        note,
        extra_headers={"Location": f"/notes/{note['id']}"},
    )


def list_notes() -> dict[str, Any]:
    response = table.scan()
    items = response.get("Items", [])
    items.sort(key=lambda item: item.get("created_at", ""), reverse=True)
    return build_response(200, {"items": items})


def get_note(note_id: str) -> dict[str, Any]:
    response = table.get_item(Key={"id": note_id})
    item = response.get("Item")
    if not item:
        return build_response(404, {"message": "Note not found."})
    return build_response(200, item)


def delete_note(note_id: str) -> dict[str, Any]:
    response = table.delete_item(Key={"id": note_id}, ReturnValues="ALL_OLD")
    if "Attributes" not in response:
        return build_response(404, {"message": "Note not found."})
    return build_response(204)


def update_note(event: dict[str, Any], note_id: str) -> dict[str, Any]:
    body = parse_body(event)
    text = (body.get("text") or body.get("content") or "").strip()
    if not text:
        raise ValueError("Field 'text' is required.")

    existing_note = table.get_item(Key={"id": note_id}).get("Item")
    if not existing_note:
        return build_response(404, {"message": "Note not found."})

    updated_note = {
        "id": note_id,
        "text": text,
        "created_at": existing_note["created_at"],
        "updated_at": datetime.now(UTC).isoformat(),
    }
    table.put_item(Item=updated_note)
    return build_response(200, updated_note)


def get_note_phrases(note_id: str) -> dict[str, Any]:
    note = table.get_item(Key={"id": note_id}).get("Item")
    if not note:
        return build_response(404, {"message": "Note not found."})

    text = (note.get("text") or "").strip()
    if not text:
        return build_response(400, {"message": "Note text is empty."})

    comprehend_response = comprehend_client.detect_key_phrases(
        Text=text,
        LanguageCode=COMPREHEND_LANGUAGE_CODE,
    )

    key_phrases: list[str] = []
    for phrase in comprehend_response.get("KeyPhrases", []):
        phrase_text = phrase.get("Text", "").strip()
        if phrase_text and phrase_text not in key_phrases:
            key_phrases.append(phrase_text)

    note["key_phrases"] = key_phrases
    note["phrases_extracted_at"] = datetime.now(UTC).isoformat()
    note["phrases_language_code"] = COMPREHEND_LANGUAGE_CODE
    table.put_item(Item=note)

    return build_response(
        200,
        {
            "id": note_id,
            "key_phrases": key_phrases,
            "language_code": COMPREHEND_LANGUAGE_CODE,
            "phrases_extracted_at": note["phrases_extracted_at"],
        },
    )


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    method = get_http_method(event)
    path = get_request_path(event)
    note_id = (event.get("pathParameters") or {}).get("id")

    result: dict[str, Any] | None = None
    error_message: str | None = None

    try:
        if method == "OPTIONS":
            result = build_response(200)
        elif method == "POST" and path == "/notes":
            result = create_note(event)
        elif method == "GET" and path == "/notes":
            result = list_notes()
        elif method == "GET" and path.endswith("/phrases") and path.startswith("/notes/") and note_id:
            result = get_note_phrases(note_id)
        elif method == "GET" and path.startswith("/notes/") and note_id:
            result = get_note(note_id)
        elif method == "PUT" and path.startswith("/notes/") and note_id:
            result = update_note(event, note_id)
        elif method == "DELETE" and path.startswith("/notes/") and note_id:
            result = delete_note(note_id)
        else:
            result = build_response(
                405,
                {
                    "message": (
                        "Supported routes: POST /notes, GET /notes, "
                        "GET /notes/{id}, GET /notes/{id}/phrases, "
                        "PUT /notes/{id}, DELETE /notes/{id}."
                    )
                },
            )
    except ValueError as exc:
        error_message = str(exc)
        result = build_response(400, {"message": error_message})
    except ClientError as exc:
        LOGGER.exception("AWS SDK request failed.")
        error = exc.response.get("Error", {})
        error_code = error.get("Code", "ClientError")
        error_message = error.get("Message", "AWS request failed.")
        status_code = 400 if error_code in {
            "InvalidRequestException",
            "TextSizeLimitExceededException",
            "UnsupportedLanguageException",
        } else 500
        result = build_response(status_code, {"message": error_message, "error_code": error_code})
    except Exception:
        LOGGER.exception("Unexpected server error.")
        error_message = "Internal server error."
        result = build_response(500, {"message": error_message})
    finally:
        put_audit_log(
            event=event,
            context=context,
            response=result,
            error_message=error_message,
        )

    return result
