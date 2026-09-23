#!/bin/bash
# =============================================================================
#  Compureparo Bot - build y despliegue desde AWS CloudShell
#
#  GENERADO AUTOMATICAMENTE desde app/ - no editar a mano.
#  Para regenerarlo: python scripts/gen_deploy.py
#
#  Uso: abre CloudShell en us-east-1 y pega este archivo completo.
# =============================================================================
set -euo pipefail

CUENTA=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
REPO=compureparo-bot
FUNCION=compureparo-bot
BUCKET=compureparo-bot-catalogo
ECR="$CUENTA.dkr.ecr.$REGION.amazonaws.com"

echo ">> Cuenta $CUENTA / region $REGION"

rm -rf ~/bot-build && mkdir -p ~/bot-build && cd ~/bot-build

# --- archivos de la aplicacion ------------------------------------------------
cat > requirements.txt <<'EOF_REQUIREMENTS_TXT'
boto3>=1.34
requests>=2.31
openpyxl>=3.1
EOF_REQUIREMENTS_TXT

cat > Dockerfile <<'EOF_DOCKERFILE'
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt ./
RUN pip install -r requirements.txt

# catalogo.xlsx va incluido como respaldo: si S3 falla, el bot sigue cotizando.
# La fuente real de precios es el catalogo en S3 (ver app/catalogo.py).
COPY handler.py catalogo.py system_prompt.md catalogo.xlsx ./

CMD ["handler.lambda_handler"]
EOF_DOCKERFILE

cat > system_prompt.md <<'EOF_SYSTEM_PROMPT_MD'
Eres el asistente virtual de WhatsApp de **Compureparo**, negocio de soporte técnico de computadores, redes y cámaras de seguridad, ubicado en Itagüí (Medellín) y atendido por **Wilmar Mesa** (técnico e Ingeniero de Telecomunicaciones).

## Cómo hablas

- Tono cercano y servicial, como habla Wilmar. Es WhatsApp: frases cortas, sin formalismos de correo.
- Español de Colombia. Trata al cliente de "tú" salvo que él use "usted".
- Usa emojis con moderación (uno o dos por mensaje, no más).
- Respuestas breves: máximo 4 o 5 líneas salvo que te pidan una lista de precios.
- Negritas de WhatsApp con un solo asterisco: *así*.

## Regla de oro sobre los precios

Abajo tienes el catálogo con los precios reales. **Esa es tu única fuente de precios.**

- Cotiza **únicamente** ítems que aparezcan en el catálogo, con el precio exacto que ahí figura.
- **Nunca** inventes, estimes, redondees ni "calcules aproximadamente" un precio.
- **Nunca** sumes varios ítems para dar un total, ni apliques descuentos, ni armes combos o paquetes.
- Si un ítem aparece con precio **SIN PRECIO** o **PENDIENTE**, trátalo como si no tuviera precio: escala a Wilmar.
- Si el cliente pide algo parecido pero no idéntico a lo del catálogo (otro tamaño, otra marca, otro modelo), **no adaptes el precio**: escala a Wilmar.

## Cuándo escalar a Wilmar (IMPORTANTE)

Escala **siempre** que se dé cualquiera de estos casos:

1. Piden un precio que **no está en el catálogo**, o está marcado SIN PRECIO / PENDIENTE.
2. El trabajo **combina varias cosas** a la vez (por ejemplo: cambiar disco *y* pantalla, o un mantenimiento *más* una ampliación de RAM). Aunque cada parte esté en el catálogo, el total lo define Wilmar.
3. Es algo **complejo, raro o fuera de lo habitual**: un equipo que no reconoces, una falla que requiere diagnóstico, un modelo poco común, servidores, equipos empresariales.
4. Piden **cotización formal, factura, descuento, negociación o garantía de un trabajo ya hecho**.
5. Preguntan **cómo pagar o por datos bancarios**. Nunca entregues números de cuenta, Nequi ni datos de pago: eso lo maneja Wilmar directamente.
6. Quieren **confirmar una fecha u hora de visita**. Tú puedes recoger los datos, pero quien confirma el horario es Wilmar.
7. El cliente está **molesto, reclamando o insatisfecho**.
8. Cualquier cosa sobre la que tengas **dudas**. Ante la duda, escala. Es mucho mejor escalar de más que dar un precio equivocado.

**Cómo escalar:** dile al cliente, con naturalidad, que eso lo revisa Wilmar personalmente y que él le escribe en seguida. Ejemplo:

> "Para ese caso prefiero que te responda Wilmar directamente, porque depende del equipo. Ya le paso tu mensaje y él te escribe 🤝"

Antes de escalar, si no los tienes todavía, pide **nombre** y **qué le pasa al equipo** (y el sector, si se trata de una visita). Así Wilmar llega con contexto.

## Lo que sí puedes hacer sin escalar

- Dar un precio del catálogo, tal cual está, con lo que incluye.
- Explicar cómo funciona el servicio a domicilio y la recogida de equipos.
- Explicar dónde están ubicados y cómo funciona el soporte remoto.
- Guiar al cliente para que averigüe datos de su equipo (tipo de disco, RAM, board) usando las guías de diagnóstico, y pedirle que envíe la foto.
- Pedir nombre y descripción de la falla.
- Saludar, despedirse y responder dudas generales del negocio.

## Cosas que nunca haces

- Inventar precios, plazos de entrega o disponibilidad.
- Prometer que algo "queda listo hoy" o dar tiempos de reparación: eso lo define Wilmar.
- Entregar datos de pago.
- Decir que eres una inteligencia artificial salvo que te lo pregunten directamente. Si te lo preguntan, respóndelo con naturalidad y ofrece pasar la conversación a Wilmar.

---

{CATALOGO}
EOF_SYSTEM_PROMPT_MD

cat > catalogo.py <<'EOF_CATALOGO_PY'
"""Carga el catalogo de precios de Compureparo desde el catalogo.xlsx en S3.

Wilmar edita el Excel y lo vuelve a subir al bucket; no hace falta reconstruir
la imagen del contenedor para cambiar un precio.

Si S3 falla (bucket sin configurar, sin permisos, archivo corrupto), se usa la
copia incluida en la imagen como respaldo, para que el bot nunca quede mudo.
"""

import io
import logging
import os
import time

from openpyxl import load_workbook

log = logging.getLogger()

CATALOGO_BUCKET = os.environ.get("CATALOGO_BUCKET", "")
CATALOGO_KEY = os.environ.get("CATALOGO_KEY", "catalogo.xlsx")
CATALOGO_LOCAL = os.path.join(os.path.dirname(__file__), "catalogo.xlsx")

# Cuanto tiempo reusar el catalogo ya cargado antes de volver a pedirlo a S3.
# Con esto un cambio de precio se refleja en <=5 min sin leer S3 en cada mensaje.
TTL_SEGUNDOS = int(os.environ.get("CATALOGO_TTL", "300"))

_cache = {"texto": None, "cargado_en": 0.0, "origen": None}

_s3 = None


def _cliente_s3():
    """Crea el cliente S3 solo si de verdad se va a usar."""
    global _s3
    if _s3 is None:
        import boto3

        _s3 = boto3.client("s3")
    return _s3


def obtener_catalogo():
    """Devuelve el catalogo como texto listo para inyectar en el system prompt."""
    ahora = time.time()
    if _cache["texto"] and (ahora - _cache["cargado_en"]) < TTL_SEGUNDOS:
        return _cache["texto"]

    texto, origen = _cargar()
    if texto:
        _cache.update(texto=texto, cargado_en=ahora, origen=origen)
        log.info("Catalogo cargado desde %s (%d caracteres)", origen, len(texto))
        return texto

    # Ultimo recurso: conservar lo que ya teniamos en cache aunque este vencido.
    if _cache["texto"]:
        log.warning("No se pudo recargar el catalogo; se reusa la copia en cache")
        return _cache["texto"]

    log.error("No se pudo cargar el catalogo por ningun medio")
    return ""


def _cargar():
    if CATALOGO_BUCKET:
        try:
            obj = _cliente_s3().get_object(Bucket=CATALOGO_BUCKET, Key=CATALOGO_KEY)
            return _xlsx_a_texto(io.BytesIO(obj["Body"].read())), f"s3://{CATALOGO_BUCKET}/{CATALOGO_KEY}"
        except Exception:
            log.exception("Fallo al leer el catalogo desde S3; se intenta la copia local")

    try:
        with open(CATALOGO_LOCAL, "rb") as f:
            return _xlsx_a_texto(io.BytesIO(f.read())), "copia local de la imagen"
    except Exception:
        log.exception("Fallo al leer la copia local del catalogo")
        return None, None


def _precio(valor):
    """Formatea el precio como lo escribiria Wilmar: $250.000"""
    if valor is None or valor == "":
        return "SIN PRECIO"
    if isinstance(valor, (int, float)):
        return f"${valor:,.0f}".replace(",", ".")
    return str(valor).strip()


def _xlsx_a_texto(binario):
    wb = load_workbook(binario, data_only=True)
    partes = []

    if "Servicios" in wb.sheetnames:
        partes.append("### Catalogo de precios\n")
        categoria_actual = None
        for fila in wb["Servicios"].iter_rows(min_row=2, values_only=True):
            categoria, item, precio, incluye, notas = (list(fila) + [None] * 5)[:5]
            if not item:
                continue
            if categoria != categoria_actual:
                categoria_actual = categoria
                partes.append(f"\n**{categoria}**")

            precio_txt = _precio(precio)
            linea = f"- {item}: {precio_txt}"
            if incluye:
                linea += f"\n  - Incluye: {incluye}"
            if notas:
                linea += f"\n  - Nota: {notas}"
            partes.append(linea)

    if "InfoNegocio" in wb.sheetnames:
        partes.append("\n\n### Informacion del negocio\n")
        for tema, contenido in wb["InfoNegocio"].iter_rows(min_row=2, values_only=True):
            if tema:
                partes.append(f"- **{tema}:** {contenido or ''}")

    if "Diagnosticos" in wb.sheetnames:
        partes.append("\n\n### Guias de diagnostico que puedes dar al cliente\n")
        for necesita, pasos in wb["Diagnosticos"].iter_rows(min_row=2, values_only=True):
            if necesita:
                partes.append(f"- **{necesita}:** {pasos or ''}")

    return "\n".join(partes)
EOF_CATALOGO_PY

cat > handler.py <<'EOF_HANDLER_PY'
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
EOF_HANDLER_PY


# --- el catalogo se baja de S3, no se pega aqui (es binario) ------------------
echo ">> Descargando catalogo.xlsx desde S3 (copia de respaldo dentro de la imagen)"
if ! aws s3 cp "s3://$BUCKET/catalogo.xlsx" ./catalogo.xlsx 2>/dev/null; then
  echo "!! No se encontro s3://$BUCKET/catalogo.xlsx"
  echo "!! Sube primero el catalogo al bucket. Abortando."
  exit 1
fi

# --- build y push -------------------------------------------------------------
echo ">> Iniciando sesion en ECR"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR"

aws ecr describe-repositories --repository-names "$REPO" --region "$REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$REPO" --region "$REGION" >/dev/null

echo ">> Construyendo imagen"
docker build -t "$REPO" .
docker tag "$REPO:latest" "$ECR/$REPO:latest"

echo ">> Subiendo imagen a ECR"
docker push "$ECR/$REPO:latest"

echo ">> Actualizando la funcion Lambda"
aws lambda update-function-code \
  --function-name "$FUNCION" \
  --image-uri "$ECR/$REPO:latest" \
  --region "$REGION" >/dev/null

aws lambda wait function-updated --function-name "$FUNCION" --region "$REGION"

echo ""
echo "LISTO - la Lambda ya corre el codigo nuevo."
echo "Recuerda que las variables de entorno se configuran en la consola de Lambda."
