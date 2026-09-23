import json
import logging
import os

import boto3
import requests

from catalogo import obtener_catalogo

logging.getLogger().setLevel(logging.INFO)
log = logging.getLogger()

VERIFY_TOKEN = os.environ.get("WHATSAPP_VERIFY_TOKEN", "")
WHATSAPP_TOKEN = os.environ.get("WHATSAPP_TOKEN", "")
PHONE_NUMBER_ID = os.environ.get("WHATSAPP_PHONE_NUMBER_ID", "")
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "us-east-1")

# Numero de Wilmar para recibir los avisos de escalada (formato 573001234567).
# Si queda vacio, simplemente no se envia el aviso.
NUMERO_WILMAR = os.environ.get("NUMERO_WILMAR", "")

# Marca que el modelo escribe cuando decide escalar. Se le quita al cliente
# antes de enviar el mensaje; solo sirve para disparar el aviso a Wilmar.
MARCA_ESCALADA = "[ESCALAR]"

bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)

_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "system_prompt.md")
with open(_PROMPT_PATH, "r", encoding="utf-8") as f:
    PLANTILLA_PROMPT = f.read()

INSTRUCCION_ESCALADA = f"""

## Formato obligatorio de salida

Cuando decidas escalar a Wilmar (segun las reglas de arriba), empieza tu respuesta
con la marca exacta {MARCA_ESCALADA} seguida de tu mensaje normal al cliente.
El cliente nunca ve esa marca: solo sirve para avisarle a Wilmar.

Si NO estas escalando, responde normal, sin ninguna marca.
"""


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
        log.info("Verificacion de webhook exitosa")
        return {"statusCode": 200, "body": params.get("hub.challenge", "")}
    log.warning("Verificacion de webhook fallida: %s", params)
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
        log.warning("Evento ignorado, estructura inesperada: %s", json.dumps(body)[:500])
        return {"statusCode": 200, "body": "evento ignorado"}

    nombre_cliente = _nombre_del_contacto(value)
    log.info("Mensaje entrante de %s (%s): %r", from_number, nombre_cliente or "sin nombre", text)

    if not text:
        text = "(mensaje sin texto - el cliente envio audio/imagen, avisale que por ahora solo lees texto)"

    try:
        respuesta = ask_claude(text)
    except Exception:
        log.exception("Error al invocar Bedrock")
        send_whatsapp_message(
            from_number,
            "Disculpa, tuve un problema tecnico. Ya le aviso a Wilmar para que te escriba 🤝",
        )
        _avisar_a_wilmar(from_number, nombre_cliente, text, "Fallo tecnico del bot")
        return {"statusCode": 200, "body": "error bedrock"}

    escala = respuesta.startswith(MARCA_ESCALADA)
    if escala:
        respuesta = respuesta[len(MARCA_ESCALADA):].lstrip()

    log.info("Respuesta de Claude (escala=%s): %r", escala, respuesta)

    send_whatsapp_message(from_number, respuesta)

    if escala:
        _avisar_a_wilmar(from_number, nombre_cliente, text, respuesta)

    return {"statusCode": 200, "body": "ok"}


def _nombre_del_contacto(value):
    try:
        return value["contacts"][0]["profile"]["name"]
    except (KeyError, IndexError, TypeError):
        return ""


def ask_claude(user_text):
    system_prompt = PLANTILLA_PROMPT.replace("{CATALOGO}", obtener_catalogo()) + INSTRUCCION_ESCALADA

    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 400,
        "system": system_prompt,
        "messages": [{"role": "user", "content": user_text}],
    }
    response = bedrock.invoke_model(modelId=BEDROCK_MODEL_ID, body=json.dumps(payload))
    result = json.loads(response["body"].read())
    return result["content"][0]["text"].strip()


def _avisar_a_wilmar(numero_cliente, nombre_cliente, pregunta, respuesta_bot):
    """Le manda a Wilmar un resumen del cliente que el bot no pudo resolver."""
    if not NUMERO_WILMAR:
        log.info("NUMERO_WILMAR no configurado: no se envia aviso de escalada")
        return

    quien = f"{nombre_cliente} ({numero_cliente})" if nombre_cliente else numero_cliente
    aviso = (
        "🔔 *Cliente para atender*\n\n"
        f"*De:* {quien}\n"
        f"*Escribio:* {pregunta}\n\n"
        f"*El bot le respondio:* {respuesta_bot}\n\n"
        f"Escribele a wa.me/{numero_cliente}"
    )
    send_whatsapp_message(NUMERO_WILMAR, aviso)


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

    try:
        r = requests.post(url, headers=headers, json=payload, timeout=10)
    except requests.RequestException:
        log.exception("No se pudo contactar la API de WhatsApp para enviar a %s", to_number)
        return False

    if r.status_code != 200:
        # Este log es el que faltaba: sin el, un token vencido o un destinatario
        # no permitido hacen que el bot falle en silencio.
        log.error(
            "WhatsApp rechazo el envio a %s | HTTP %s | %s",
            to_number, r.status_code, r.text[:800],
        )
        return False

    log.info("Mensaje enviado a %s", to_number)
    return True
