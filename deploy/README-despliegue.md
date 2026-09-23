# Cómo desplegar un cambio del bot

El proyecto no necesita Docker ni AWS CLI en el PC de Wilmar: todo el build se hace en
**AWS CloudShell** (la terminal que viene dentro de la consola de AWS).

---

## ⚡ Cambiar solo un PRECIO — no requiere desplegar nada

Si lo único que cambió es el catálogo (`catalogo.xlsx`):

1. Edita `catalogo.xlsx` en tu PC.
2. Ve a la consola de AWS → **S3** → bucket `compureparo-bot-catalogo`.
3. Arrastra el archivo nuevo encima (sobrescribe el anterior).
4. Listo. El bot toma los precios nuevos en máximo 5 minutos.

**No hace falta reconstruir el contenedor.** Esa fue la razón de poner el catálogo en S3.

---

## 🔁 Cambiar CÓDIGO (handler.py, catalogo.py, system_prompt.md)

Eso sí requiere reconstruir la imagen. Abre **CloudShell** (ícono `>_` arriba a la
derecha en la consola de AWS, región *N. Virginia / us-east-1*) y pega el bloque
completo de `build-cloudshell.sh`.

Toma unos 3-5 minutos. Al final imprime `LISTO`.

---

## 🔑 El token de WhatsApp

✅ **Ya está resuelto (2026-09-22).** El bot usa un **token permanente de System User**
que no expira. No hay que renovarlo.

- System user: `compureparo-bot` (ID `61594720229001`), rol Admin del portfolio
- Activos asignados: app *Compureparo Bot* (rol "Desarrollar app") y la cuenta de WhatsApp
  (permiso "Mensajes")
- Permisos del token: `whatsapp_business_messaging` + `whatsapp_business_management`
- Caducidad: **Nunca**

### Verificar el token en cualquier momento

```bash
TOKEN=$(aws lambda get-function-configuration --function-name compureparo-bot \
  --query 'Environment.Variables.WHATSAPP_TOKEN' --output text)
curl -s "https://graph.facebook.com/v21.0/debug_token?input_token=$TOKEN&access_token=$TOKEN"
```

Lo que debes ver: `"type":"SYSTEM_USER"`, `"is_valid":true` y **`"expires_at":0`**
(cero = no expira nunca). Si algún día `is_valid` fuera `false`, hay que regenerarlo.

### Si alguna vez toca regenerarlo

[business.facebook.com](https://business.facebook.com) → Configuración → **Usuarios del
sistema** → `compureparo-bot` → **Generar token** → app *Compureparo Bot* → caducidad
**Nunca** → marcar `whatsapp_business_messaging` y `whatsapp_business_management` →
copiar y pegar en Lambda → Environment variables → `WHATSAPP_TOKEN`.

> **Ojo con dos trampas que ya nos costaron tiempo:**
> 1. El asistente dirá *"No hay permisos disponibles"* si el system user no tiene la
>    **app** asignada como activo (no basta con la cuenta de WhatsApp).
> 2. Tras asignar activos, la lista puede seguir diciendo "No hay activos asignados"
>    hasta que **recargues la página**. Los activos sí quedaron.

### Por qué NO sirven los tokens del panel de pruebas

Los tokens de "Paso 1. Pruébalo" **no duran 24h desde que los generas**: expiran a una
hora fija (vimos uno morir a las 16:00 PDT el mismo día que se creó). Cuando eso pasa,
el envío falla con `OAuthException` código 190, subcódigo 463.

---

## Variables de entorno que usa la Lambda

| Variable | Valor | Para qué |
|---|---|---|
| `WHATSAPP_TOKEN` | token de Meta | Enviar mensajes. **Usar el permanente de System User.** |
| `WHATSAPP_VERIFY_TOKEN` | `3fe24ad94ecb48d2b4d5f847b2b668d4` | Verificar el webhook |
| `WHATSAPP_PHONE_NUMBER_ID` | `1259324300605222` | Número desde el que se responde |
| `BEDROCK_MODEL_ID` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Modelo de Claude |
| `BEDROCK_REGION` | `us-east-1` | Región de Bedrock |
| `CATALOGO_BUCKET` | `compureparo-bot-catalogo` | Bucket S3 del catálogo |
| `CATALOGO_KEY` | `catalogo.xlsx` | Nombre del archivo en el bucket |
| `CATALOGO_TTL` | `300` | Segundos que cachea el catálogo (5 min) |
| `NUMERO_WILMAR` | `573008105537` | A dónde llegan los avisos de escalada |

---

## 💰 Costos — ¿hay que apagar algo?

**No. No hay nada que apagar.** Toda la arquitectura es *serverless*: no hay ningún
servidor encendido cobrando por hora. Si nadie escribe al bot, el costo es **cero**.

| Recurso | Cobra cuando… | Costo real |
|---|---|---|
| **Lambda** | llega un mensaje | 51 invocaciones el 22–23/09. Free tier: 1.000.000/mes → **$0** |
| **Bedrock** (Claude) | se invoca el modelo | ~2.130 tokens de entrada por mensaje → **centavos** |
| **S3** | almacenar el catálogo | 8 KB → **$0** |
| **CloudWatch Logs** | escribir logs | Free tier: 5 GB/mes → **$0** |
| **ECR** | guardar la imagen Docker | 367 MB en 2 imágenes. Free tier: 500 MB/mes → **$0** |

**El único costo que corre sin que nadie use el bot es ECR** (guardar la imagen), y hoy
está por debajo del free tier. Si algún día se pasa, son centavos: ~$0,10 por GB al mes.

> Hay **2 imágenes** en ECR: la actual y la del build anterior. Se puede borrar la vieja
> para liberar ~180 MB, pero conviene conservarla como punto de rollback. No cuesta nada.

**Verificar el gasto en cualquier momento:**

```bash
MAN=$(date -u -d "+1 day" +%Y-%m-%d)
aws ce get-cost-and-usage --time-period Start=2026-09-01,End=$MAN \
  --granularity DAILY --metrics UnblendedCost \
  --query 'ResultsByTime[*].[TimePeriod.Start,Total.UnblendedCost.Amount]' --output table
```

> Cost Explorer tiene hasta **24 horas de retraso**: el consumo de hoy puede aparecer mañana.
> El aviso automático ya está cubierto por el presupuesto de AWS Budgets (alertas en $20 y
> $50 al correo).

**Lo único que sí conviene vigilar** es Bedrock si el bot recibe mucho tráfico, porque es
el único costo que crece con el uso. A $100 de crédito y ~2.130 tokens por mensaje, hay
margen para decenas de miles de mensajes.

---

## Cómo saber si algo falló

Consola → **CloudWatch** → Log groups → `/aws/lambda/compureparo-bot`.

Ahora el código sí registra los errores. Busca:

- `WhatsApp rechazo el envio` → problema de token o de destinatario no permitido
  (el log incluye el error exacto que devolvió Meta).
- `Fallo al leer el catalogo desde S3` → revisar el bucket o los permisos IAM.
- `Error al invocar Bedrock` → problema con el modelo o los permisos de Bedrock.
