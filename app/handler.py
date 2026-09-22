import json
import os

import boto3
import requests

VERIFY_TOKEN = os.environ.get("WHATSAPP_VERIFY_TOKEN", "")
WHATSAPP_TOKEN = os.environ.get("WHATSAPP_TOKEN", "")
PHONE_NUMBER_ID = os.environ.get("WHATSAPP_PHONE_NUMBER_ID", "")
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")

bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)

_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "system_prompt.md")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    SYSTEM_PROMPT = f.read()


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    if method == "GET":
        return _handle_verification(event)

    if method == "POST":
        return _handle_incoming_message(event)

    return {"statusCode": 405, "body": "method not allowed"}


def _handle_verification(event):
    params = event.get("queryStringParameters") or {}
    if params.get("hub.mode") == "subscribe" and params.get("hub.verify_token") == VERIFY_TOKEN:
        return {"statusCode": 200, "body": params.get("hub.challenge", "")}
    return {"statusCode": 403, "body": "Verificacion fallida"}


def _handle_incoming_message(event):
    body = json.loads(event.get("body") or "{}")

    try:
        value = body["entry"][0]["changes"][0]["value"]
        messages = value.get("messages")
        if not messages:
            # Probablemente es un "status" (entregado/leido), no un mensaje nuevo.
            return {"statusCode": 200, "body": "sin mensajes"}
        msg = messages[0]
        from_number = msg["from"]
        text = msg.get("text", {}).get("body", "")
    except (KeyError, IndexError):
        return {"statusCode": 200, "body": "evento ignorado"}

    if not text:
        text = "(mensaje sin texto — el cliente envio audio/imagen, avisale que por ahora solo lees texto)"

    reply = ask_claude(text)
    send_whatsapp_message(from_number, reply)
    return {"statusCode": 200, "body": "ok"}


def ask_claude(user_text):
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 400,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": user_text}],
    }
    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        body=json.dumps(payload),
    )
    result = json.loads(response["body"].read())
    return result["content"][0]["text"]


def send_whatsapp_message(to_number, text):
    url = f"https://graph.facebook.com/v21.0/{PHONE_NUMBER_ID}/messages"
    headers = {
        "Authorization": f"Bearer {WHATSAPP_TOKEN}",
        "Content-Type": "application/json",
    }
    payload = {
        "messaging_product": "whatsapp",
        "to": to_number,
        "type": "text",
        "text": {"body": text},
    }
    requests.post(url, headers=headers, json=payload, timeout=10)
