# Handoff — estado al 2026-09-22

> Documento de retomada. Si vuelves al proyecto después de un tiempo, lee esto primero.
> El detalle histórico completo está en la bitácora del `README.md`.

## ✅ Dónde quedamos

**El bot funciona en producción.** Wilmar le escribe por WhatsApp y responde con precios
reales del catálogo. El piloto técnico está cerrado.

```
WhatsApp (número de prueba +1 555 165-6226)
      ↓ webhook
AWS Lambda  compureparo-bot      ← Function URL, us-east-1
      ↓                    ↘
Bedrock Claude Haiku 4.5    S3 compureparo-bot-catalogo/catalogo.xlsx
      ↓
respuesta por WhatsApp  (+ aviso a Wilmar si escala)
```

Todo lo crítico está resuelto: app publicada en Meta, app suscrita al WABA, **token
permanente de System User que no expira**, catálogo editable sin redesplegar, y logging
que sí reporta los errores de envío.

## 🔧 Lo siguiente, en orden de impacto

### 1. Memoria de conversación ← el más importante
**Problema:** `handler.py` le manda a Bedrock **solo el mensaje actual**, sin historial.
El bot no recuerda nada del turno anterior. Eso causa directamente las quejas de Wilmar:
se repite, vuelve a saludar y vuelve a preguntar datos que ya le dieron.

**Solución:** guardar el historial por número de teléfono (DynamoDB con TTL de ~24h) y
enviarlo en el arreglo `messages` de la llamada a Bedrock. Ajustar tono sin esto solo
tapa el síntoma.

### 2. Ajustar el tono del bot
Feedback textual de Wilmar: *"pide demasiada información, es muy redundante, hace
preguntas innecesarias"*. Ver `README.md` §3.2 para las ideas concretas
(respuestas más cortas, una sola pregunta por mensaje, responder antes de preguntar).
Se edita en `app/system_prompt.md`.

### 3. Completar el catálogo
En `catalogo.xlsx`, las filas en amarillo marcadas `PENDIENTE`: mantenimiento, redes,
cámaras, RAM, formateo y cambio de teclado con remaches. Mientras estén vacías el bot
escala esos casos a Wilmar (seguro, pero poco útil).

### 4. Migrar al número real de Compureparo
⚠️ Ojo con el riesgo de la §2 del README: conectar el número real a la API lo **saca de
la app de WhatsApp Business del celular**. Hacerlo solo cuando el bot esté afinado.

## 💰 Costos — nada que apagar

Arquitectura 100% serverless: sin uso, cuesta **$0**. Gasto acumulado a hoy: prácticamente
cero (Cost Explorer reporta `-0,0000000033 USD` para todo septiembre). Detalle y comandos
de verificación en `deploy/README-despliegue.md`.

## 📁 Mapa rápido

| Quiero… | Archivo |
|---|---|
| Cambiar un precio | `catalogo.xlsx` → subir a S3. **No requiere desplegar** |
| Cambiar el tono o las reglas | `app/system_prompt.md` → sí requiere desplegar |
| Cambiar la lógica | `app/handler.py` → sí requiere desplegar |
| Desplegar | `deploy/README-despliegue.md` + `deploy/build-cloudshell.sh` |
| Ver por qué falló algo | CloudWatch → `/aws/lambda/compureparo-bot` |

> Tras editar cualquier cosa en `app/`, regenera el script de despliegue con
> `python scripts/gen_deploy.py` antes de correrlo.

## ⚠️ Trampas ya pagadas — no repetirlas

1. **Configurar la Callback URL NO suscribe la app al WABA.** Son dos pasos distintos y el
   panel no lo dice. Verificar con `GET /<WABA_ID>/subscribed_apps`.
2. **Los tokens del panel "Pruébalo" mueren a una hora fija**, no a las 24h de creados.
   Por eso se usa el System User. Verificar con `debug_token`: debe decir `"expires_at":0`.
3. **El número de prueba solo envía a máximo 5 números pre-registrados.** Eso es exclusivo
   del sandbox; con el número real cualquier cliente escribe sin registrarse.
4. **Al generar el token**, el asistente dice *"No hay permisos disponibles"* si al system
   user no se le asignó **la app** como activo. Y tras asignar activos, la lista miente
   hasta que recargues la página.
