# Bot IA — Asistente de WhatsApp para Compureparo

> Proyecto vivo. Nace de la Sesión 4 (Máquina de ingresos) de `Crecimiento_Personal_Wilmar_Mesa.md`. Piloto en el WhatsApp Business real de Compureparo. Capital inicial: $200.000 COP. Infraestructura: cuenta AWS con $100 USD de crédito gratuito.

---

## 0. Decisión de arquitectura — Claude vs. "API free tipo Codex"

**Recomendación: Amazon Bedrock con Claude 3.5 Haiku, no Codex ni otra API "gratis" suelta.** Razones concretas, no genéricas:

1. **Codex no es la herramienta correcta.** Es un modelo de OpenAI especializado en generar/editar código, no en sostener una conversación de atención al cliente. Tampoco existe una capa "gratis" real de Codex/OpenAI para producción — cualquier uso serio requiere facturación aparte con OpenAI (nueva cuenta, nueva forma de pago).
2. **Bedrock te deja pagar el LLM con el mismo crédito de $100 USD de AWS que ya tienes** — no necesitas abrir cuenta ni poner tarjeta en Anthropic por separado. Un solo lugar de facturación, un solo crédito que se estira para hosting + IA.
3. **Ya invertiste en esto y no lo has cobrado:** tienes *Curso de Claude AI* y *Curso de Claude Code para No Programadores* (Platzi) — tu prompting con Claude ya lo conoces. Usar Claude en Bedrock aprovecha ese conocimiento en vez de aprender la sintaxis de otro proveedor desde cero.
4. **Claude 3.5 Haiku** es el modelo más barato de la familia Claude en Bedrock — perfecto para respuestas cortas de WhatsApp (precios, horarios, agendar visita), no necesitas el modelo más caro para este caso de uso.

**Alternativas genuinamente gratis que sí existen (Groq, Gemini free tier)** quedan descartadas para el piloto: abren un proveedor nuevo, tienen límites de tasa pensados para pruebas — no para un negocio real — y no usan el crédito que ya tienes. Se mencionan aquí solo como plan B si el crédito de AWS se agota antes de generar ingreso con el bot.

## 1. Arquitectura elegida

```
WhatsApp Business (Meta Cloud API)
        │  webhook (HTTPS)
        ▼
AWS Lambda (contenedor Docker) ── Function URL (HTTPS gratis, sin certificados que gestionar)
        │
        ▼
Amazon Bedrock — Claude Haiku 4.5 (system prompt con precios/servicios de Compureparo)
```

> **Nota 2026-09-22:** Claude 3.5 Haiku llegó a su fin de vida en Bedrock (`ResourceNotFoundException`). Se migró a **Claude Haiku 4.5** (`us.anthropic.claude-haiku-4-5-20251001-v1:0`), invocado vía **perfil de inferencia cross-region** (no el ID base del modelo — Bedrock ya no permite invocación "on-demand" directa en modelos nuevos, exige el ARN del inference profile).

Diagrama visual completo (flujo de mensaje + pipeline de build/deploy): ver artifact publicado — enlace en la bitácora de abajo.

**Por qué Lambda con imagen de contenedor (y no EC2 ni ECS Fargate):**
- Sigue siendo un **contenedor Docker** (lo que pediste), solo que se ejecuta en Lambda en vez de un servidor fijo.
- **Costo casi $0 en reposo:** Lambda solo cobra cuando llega un mensaje. Un servidor EC2/ECS corre (y cobra, o consume horas de free tier) 24/7 aunque nadie escriba.
- **Function URL da HTTPS gratis automáticamente** — Meta exige que el webhook sea HTTPS con certificado válido; en EC2 tendrías que gestionar tú ese certificado (Let's Encrypt, dominio, etc.). Con Lambda no hace falta.
- Encaja mejor con tu tiempo real disponible (1–3h/día): menos piezas que mantener.

## 2. ⚠️ Riesgo operativo — probar sin arriesgar el número real

Pediste probar directo en el WhatsApp Business real de Compureparo. Un detalle importante antes de conectar:

**Conectar un número a la API de WhatsApp Cloud (Meta) generalmente lo saca de la app normal de WhatsApp Business del celular** — dejarías de poder chatear desde tu teléfono con la app de siempre, todo pasaría a manejarse por API. Si algo falla en el bot mientras pruebas, tus clientes reales quedan sin respuesta por ese canal.

**Recomendación (no cambia tu decisión, solo reduce el riesgo):** Meta da un **número de prueba gratuito** apenas creas la app de WhatsApp en Meta for Developers, sin necesidad de usar tu número real todavía. La secuencia segura es:

1. Desarrollar y probar todo el flujo con el número de prueba de Meta (tú mismo le escribes desde tu celular personal).
2. Cuando el bot responda bien de forma consistente, ahí sí migrar el número real de Compureparo.

Si prefieres saltarte el paso 1 e ir directo al número real, lo hacemos — pero quedó documentado el riesgo para que la decisión sea informada.

## 3. Plan por fases

- [x] **Fase 1 — Meta (WhatsApp Cloud API):** crear app en [developers.facebook.com](https://developers.facebook.com), producto "WhatsApp", obtener número de prueba, token temporal y `phone_number_id`. ✅ Hecho 2026-09-20 — app "Compureparo Bot" (App ID `1618141229945641`), datos en `app/.env`.
- [x] **Fase 2 — AWS Bedrock:** ✅ Hecho 2026-09-22 — formulario "Submit use case details" enviado a Anthropic (Compureparo, IT/computer repair, usuarios externos). Modelo activo: Claude Haiku 4.5 vía perfil de inferencia `us.anthropic.claude-haiku-4-5-20251001-v1:0`. El acceso queda sujeto a propagación (unos minutos tras enviar el formulario y tras cada cambio de permisos IAM).
- [x] **Fase 3 — Guardarraíl de costo:** crear una alarma de AWS Budgets en $20 y $50 USD (de tu crédito de $100) para que te avise por correo antes de gastarlo todo. ✅ Hecho 2026-09-20 — presupuesto "Compureparo Bot - Presupuesto piloto" ($100) con alertas en $20 y $50 a wilmarmesa94@gmail.com.
- [x] **Fase 4 — Contenedor:** ✅ Hecho 2026-09-22 — imagen construida en AWS CloudShell (sin Docker/AWS CLI locales) y subida a Amazon ECR, repo privado `compureparo-bot`.
- [x] **Fase 5 — Lambda:** ✅ Hecho 2026-09-22 — función `compureparo-bot` creada desde la imagen de ECR, rol `compureparo-bot-lambda-role` (logs + `bedrock:InvokeModel` acotado + `aws-marketplace:Subscribe`/`ViewSubscriptions`), timeout 30s, variables de entorno configuradas, Function URL con auth `NONE` activa.
- [x] **Fase 6 — Conectar webhook:** ✅ Hecho 2026-09-22 — Function URL registrada como webhook en Meta, verificación con `VERIFY_TOKEN` exitosa, suscrito al campo `messages`.
- [x] **Fase 7 — Piloto:** ✅ **Hecho 2026-09-22 — el bot respondió por WhatsApp de verdad.** Prueba real desde el celular de Wil al número de prueba: llegó el saludo de bienvenida generado por Claude Haiku 4.5. Pipeline completo verificado: WhatsApp → Function URL → Lambda → Bedrock → respuesta entregada. Requirió destrabar tres bloqueos (ver bitácora). ⏳ Siguiente: migrar al número real de Compureparo (Paso 2: Configuración de producción en Meta).

## 3.1 Deuda técnica — resuelta 2026-09-22

Las tres cosas detectadas durante la depuración de la Fase 7 ya están corregidas:

1. ~~El token de WhatsApp es temporal~~ → ✅ **Token permanente de System User**
   (`expires_at: 0`). Detalles y verificación en `deploy/README-despliegue.md`.
2. ~~`handler.py` no revisa la respuesta de la API de WhatsApp~~ → ✅ Ahora registra
   `status_code` y cuerpo del error cuando no es 200. Ese log fue justamente lo que
   permitió diagnosticar el token vencido en minutos en vez de horas.
3. ~~No hay log del mensaje entrante ni de la respuesta de Claude~~ → ✅ Ambos se registran.

**Lo que queda pendiente antes de usar el número real de Compureparo:**

- Completar en `catalogo.xlsx` los ítems marcados `PENDIENTE` (mantenimiento, redes,
  cámaras, RAM, formateo, cambio de teclado). Mientras estén vacíos el bot escala esos
  casos a Wilmar, que es el comportamiento seguro, pero no el más útil.
- **Ajustar el tono del bot** (ver §3.2).
- Migrar el número real (recordar el riesgo de la §2: sale de la app de WhatsApp Business
  del celular).

## 3.2 Ajustes de tono pendientes (feedback de Wilmar, 2026-09-22)

El bot ya responde con los precios correctos, pero el **estilo** de las respuestas necesita
trabajo. Observaciones de Wilmar tras probarlo en vivo:

1. **Pide demasiada información.** Arranca pidiendo datos que el cliente aún no necesita dar.
2. **Es redundante.** Repite lo que incluye el servicio, o vuelve a saludar en cada mensaje.
3. **Hace preguntas innecesarias.** Pregunta cosas que no hacen falta para responder lo que
   el cliente preguntó.

**Dónde se ajusta:** `app/system_prompt.md`, sección "Cómo hablas". Ideas concretas a probar:

- Endurecer el límite de longitud (hoy dice "máximo 4 o 5 líneas"; probar 2-3).
- Regla explícita: *responde primero lo que preguntaron; pide datos solo si sin ellos no
  puedes responder*.
- Regla explícita: *no repitas lo que ya dijiste en el mensaje anterior de la conversación*.
- Limitar a **una sola pregunta** por mensaje, y solo cuando sea indispensable.
- Recortar el detalle de "Incluye:" — que lo mencione corto, no como lista completa.

> **Ojo:** el bot **no tiene memoria de conversación.** `handler.py` manda a Bedrock solo el
> mensaje actual, sin historial. Por eso se repite y vuelve a preguntar cosas ya dichas —
> literalmente no recuerda el turno anterior. Arreglar la redundancia de fondo requiere
> guardar el historial por número de teléfono (por ejemplo en DynamoDB) y enviarlo en
> `messages`. Es el cambio de mayor impacto pendiente.

## 4. Estructura del proyecto

```
Bot IA/
├── README.md               ← este archivo (plan + decisiones)
├── catalogo.xlsx           ← ⭐ PRECIOS. Lo edita Wilmar y lo sube a S3. Fuente de verdad.
├── app/
│   ├── Dockerfile          ← imagen para Lambda (contenedor)
│   ├── requirements.txt
│   ├── handler.py          ← webhook de Meta + Bedrock + aviso de escalada
│   ├── catalogo.py         ← lee catalogo.xlsx desde S3 y lo vuelve texto para el prompt
│   ├── system_prompt.md    ← "cerebro" del bot: tono y reglas de escalada
│   ├── catalogo.xlsx       ← copia de respaldo que va dentro de la imagen
│   └── .env.example        ← variables necesarias (el .env real no se versiona)
├── deploy/
│   ├── README-despliegue.md  ← cómo desplegar y cómo renovar el token
│   └── build-cloudshell.sh   ← script para pegar en AWS CloudShell (autogenerado)
├── scripts/
│   ├── gen_catalogo.py     ← regenera catalogo.xlsx
│   └── gen_deploy.py       ← regenera build-cloudshell.sh desde app/
└── docs/                   ← política de privacidad y diagrama (GitHub Pages)
```

## 4.1 El catálogo de precios

**`catalogo.xlsx` es la fuente de verdad de los precios.** Tiene tres hojas:

| Hoja | Para qué |
|---|---|
| `Servicios` | Categoría, ítem, precio, qué incluye, y notas para el bot |
| `InfoNegocio` | Ubicación, cómo funciona el domicilio, soporte remoto, despedida |
| `Diagnosticos` | Pasos que el bot le dicta al cliente para averiguar disco/RAM/board |

**Para cambiar un precio:** editas el Excel y lo subes al bucket S3
`compureparo-bot-catalogo`. El bot lo toma en máximo 5 minutos — **no hay que
reconstruir el contenedor**. Las filas marcadas `PENDIENTE` (en amarillo) son
servicios sin precio confirmado: el bot escala esos casos a Wilmar en vez de inventar.

Los precios iniciales se extrajeron de las **respuestas rápidas reales** del WhatsApp
Business de Compureparo (leídas el 2026-09-22), no de estimaciones.

## 4.2 Cuándo escala el bot a Wilmar

El bot marca la respuesta internamente y `handler.py` le manda a Wilmar un WhatsApp con
el número del cliente, lo que preguntó y lo que el bot contestó. Escala cuando:

1. El precio no está en el catálogo o está en `PENDIENTE`.
2. El trabajo **combina varios ítems** (el total lo define Wilmar, nunca el bot).
3. Es algo complejo, raro o que requiere diagnóstico.
4. Piden cotización formal, factura, descuento o garantía.
5. Preguntan **cómo pagar** — el bot nunca entrega datos bancarios.
6. Hay que confirmar fecha u hora de visita.
7. El cliente está molesto o reclamando.
8. Ante cualquier duda.

## 5. Variables de entorno necesarias

| Variable | De dónde sale |
|---|---|
| `WHATSAPP_TOKEN` | Meta for Developers → tu app → WhatsApp → token temporal (o permanente tras verificar negocio) |
| `WHATSAPP_VERIFY_TOKEN` | Lo inventas tú (cualquier string) — se usa para verificar el webhook |
| `WHATSAPP_PHONE_NUMBER_ID` | Meta for Developers → tu app → WhatsApp → "From" number ID |
| `BEDROCK_MODEL_ID` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` — es un **perfil de inferencia** (ARN cross-region), no el ID base del modelo. Verificar vigencia en el catálogo de Bedrock antes de reusar este valor en el futuro, los modelos Anthropic van quedando EOL con el tiempo |
| `BEDROCK_REGION` | `us-east-1` (recomendado — ahí Bedrock/Claude suele estar disponible primero) |
| `CATALOGO_BUCKET` | `compureparo-bot-catalogo` — bucket S3 con el catálogo de precios |
| `CATALOGO_KEY` | `catalogo.xlsx` (opcional, es el valor por defecto) |
| `CATALOGO_TTL` | `300` segundos (opcional, es el valor por defecto) |
| `NUMERO_WILMAR` | `573008105537` — a dónde llegan los avisos cuando el bot escala |

## 6. Bitácora del proyecto

| Fecha | Avance | Notas |
|---|---|---|
| 2026-09-20 | Arquitectura definida (Bedrock + Claude Haiku + Lambda contenedor) y código base creado | Pendiente: Fase 1 (Meta) y Fase 2 (Bedrock) las ejecuta Wil en las consolas — aquí seguimos apenas tenga las credenciales |
| 2026-09-20 | **Pausa de sesión.** Wil va a ejecutar por su cuenta la Fase 1 (crear app WhatsApp en developers.facebook.com, guardar token + phone_number_id en `app/.env`) y la alarma de AWS Budgets ($20 y $50). Documentación y código quedan guardados tal cual en este folder | **Para retomar:** confirmar si ya tiene el token/phone_number_id guardados en `.env`, y si ya creó las alarmas de presupuesto. Siguiente paso técnico: habilitar acceso a Claude en Bedrock (Fase 2) y armar el webhook (Fase 5-6) |
| 2026-09-20 | **Fase 1 completada (asistida por Claude vía navegador).** Se creó la app "Compureparo Bot" en Meta for Developers (App ID `1618141229945641`), conectada al portfolio comercial "CompuReparoMedellín". Se generó un número de prueba gratuito de WhatsApp (+1 555 165-6226), su `Phone Number ID` y un token de acceso temporal. Todo quedó guardado en `app/.env` (no versionado) | El token generado es **temporal** (expira en ~24h) — antes de ir a producción hay que generar uno permanente vía System User en Meta Business Suite. Pendiente: Fase 2 (Bedrock) y Fase 3 (alarmas AWS Budgets) |
| 2026-09-20 | **Fase 3 completada (asistida por Claude vía navegador).** Se creó en AWS Budgets el presupuesto "Compureparo Bot - Presupuesto piloto" de $100 (mensual recurrente) con dos alertas por correo a wilmarmesa94@gmail.com: Alert #1 en $20.00 y Alert #2 en $50.00 de costo real | Ya existía además un "My Zero-Spend Budget" ($1) predeterminado de AWS. Pendiente: Fase 2 (habilitar acceso a Claude 3.5 Haiku en Bedrock, región us-east-1) |
| 2026-09-20 | **Fase 2 iniciada, pausada a mitad de camino.** AWS Bedrock ya no requiere activar modelos manualmente (la página "Model access" fue retirada) — los modelos serverless se habilitan automáticamente al invocarlos por primera vez. Sin embargo, Anthropic exige que la cuenta envíe un formulario de "Submit use case details" (nombre de empresa, sitio web, industria, tipo de usuarios, descripción del caso de uso) antes de la primera llamada a un modelo Claude. Claude (el asistente) llegó a abrir ese formulario en la consola de Bedrock (Model catalog → aviso amarillo → "Submit use case details") pero lo canceló sin enviarlo porque pide datos del negocio (sitio web de Compureparo, industria, descripción) que se comparten con Anthropic y debían confirmarse con Wil primero. **Pausa de sesión** a pedido de Wil | **Para retomar Fase 2:** ir a la consola de Bedrock (región us-east-1) → Model catalog → banner amarillo de Anthropic → "Submit use case details", y completar: nombre de empresa (Compureparo), sitio web (confirmar cuál usar), industria, usuarios (externos — son clientes por WhatsApp), y descripción breve del caso de uso (asistente de WhatsApp para responder precios/horarios/agendar visitas de un taller de reparación de computadores). Después de enviarlo, ya se puede invocar `anthropic.claude-3-5-haiku-20241022-v1:0` sin pasos adicionales. Luego siguen Fase 4 (Docker/ECR) y Fase 5-6 (Lambda + webhook) |
| 2026-09-22 | **Fases 4, 5 y 6 completadas (asistidas por Claude vía navegador, sesión completa de despliegue).** Sin Docker ni AWS CLI instalados localmente, se usó **AWS CloudShell** para todo el build: se recrearon los 4 archivos de `/app` ahí mismo, `docker build`, `docker tag`, `docker push` al repo ECR `compureparo-bot`. Se creó el rol IAM `compureparo-bot-lambda-role` (logs + `bedrock:InvokeModel`) y la función Lambda `compureparo-bot` desde la imagen de ECR, con Function URL (auth `NONE`, ya que Meta llama sin firma AWS — la seguridad real la da el `WHATSAPP_VERIFY_TOKEN` chequeado en el código) y timeout subido de 3s a 30s (el default no alcanza para Bedrock + WhatsApp). Se pegó la Function URL como webhook en Meta y quedó verificado y suscrito a `messages` | Todo el flujo quedó documentado visualmente en un artifact HTML (diagrama de secuencia del mensaje + pipeline de build) — pedir el enlace si se perdió, o regenerarlo con Claude |
| 2026-09-22 | **Descubierto en la primera prueba real: Claude 3.5 Haiku llegó a su fin de vida** (`ResourceNotFoundException: This model version has reached the end of its life`). Se migró a **Claude Haiku 4.5** (`us.anthropic.claude-haiku-4-5-20251001-v1:0`), que en Bedrock solo se puede invocar vía **perfil de inferencia** (ARN `inference-profile`, no el ID base del modelo — error: *"Invocation of model ID ... with on-demand throughput isn't supported"*). Se actualizó la política IAM del rol de Lambda y la variable `BEDROCK_MODEL_ID`. Luego apareció un tercer error: `AccessDeniedException` porque el modelo se distribuye vía **AWS Marketplace** y el rol necesita `aws-marketplace:ViewSubscriptions` + `aws-marketplace:Subscribe` para autosuscribirse en la primera invocación — se agregó ese statement a la política. También se envió (con tu confirmación) el formulario "Submit use case details" de Anthropic: Compureparo, industria "Other: IT/computer repair support services", usuarios externos, sitio usado: `https://www.instagram.com/compureparo/` (Compureparo no tiene sitio web propio) | Después de cada cambio de permisos IAM hubo que esperar 1-2 min a que propagara |
| 2026-09-22 | **Pipeline confirmado funcionando de punta a punta.** Un `POST` a la Function URL con un payload de WhatsApp simulado devolvió `200 ok` sin ningún error nuevo en CloudWatch Logs — Lambda recibe el mensaje, invoca Claude Haiku 4.5 en Bedrock, obtiene respuesta, e intenta enviarla por la API de WhatsApp | **Para retomar Fase 7:** falta la prueba real — escribirle al número de prueba de Meta desde un celular y confirmar visualmente que la respuesta llega. El número usado en la prueba simulada (`573000000000`) no es un destinatario real de WhatsApp, así que ese envío específico probablemente no llegó a ningún lado (esperado, no es un bug) |
| 2026-09-22 | **Prueba real desde el celular de Wil: el bot no respondió.** Se escribió "HOLA" al número de prueba desde WhatsApp Web (vinculado al celular real). Se revisó CloudWatch Logs (`/aws/lambda/compureparo-bot`) en ventanas de 15 min y 1 h: **cero invocaciones de Lambda** — el webhook nunca se disparó. Causa raíz encontrada en el panel de Meta ("Publicar" → requisitos): mientras la app de WhatsApp esté **"En desarrollo" (sin publicar)**, Meta solo entrega webhooks de mensajes de **prueba enviados desde el panel**, no mensajes reales — ni siquiera los que le escribe el propio developer/admin. Para publicar la app, Meta exige una **URL de política de privacidad**, que Compureparo no tenía | **Para retomar:** completar la publicación de la app (ver bitácora siguiente) |
| 2026-09-22 | **Repositorio Git creado y código subido.** Se creó `https://github.com/wymesgav/Bot-IA-Compureparo`, se inicializó el repo local (`git init`, `.gitignore` excluyendo `app/.env` con los secretos reales), se hizo merge con el commit inicial trivial que ya traía el repo en GitHub, y se hizo push a `main`. Se redactó una política de privacidad real y breve (qué datos procesa el bot, para qué, con quién se comparte, cómo pedir que se elimine) en `docs/privacy.html`, y se copió el diagrama de arquitectura (el mismo del artifact publicado) a `docs/arquitectura.html` — ambos ya están en el repo, pendientes de publicar vía GitHub Pages | **Handoff — para retomar la Fase 7 en la próxima sesión, en este orden:** <br>1. En GitHub → repo `Bot-IA-Compureparo` → **Settings → Pages** → Source: branch `main`, carpeta `/docs` → Save. Copiar la URL pública que genera (algo como `https://wymesgav.github.io/Bot-IA-Compureparo/privacy.html`).<br>2. En [developers.facebook.com](https://developers.facebook.com) → app "Compureparo Bot" → **Configuración de la app → Básica** → pegar esa URL en "URL de la política de privacidad" → Guardar cambios.<br>3. Ir a **Panel → "Asegúrate de que se cumplan todos los requisitos y luego publica la app"** (o `/apps/1618141229945641/go_live/`) → botón **Publicar**.<br>4. Volver a escribirle "Hola" al número de prueba (+1 555 165-6226) desde WhatsApp.<br>5. Verificar en CloudWatch Logs (`/aws/lambda/compureparo-bot`, filtrar por `ERROR` o mirar los `REPORT RequestId`) que sí llegó una invocación nueva, y confirmar que la respuesta de Claude aparece en WhatsApp.<br>Si el mensaje real sigue sin llegar tras publicar, revisar también "Paso 3: Verificación del negocio" en Casos de uso → Conectar en WhatsApp, por si Meta pide ese paso adicional para tráfico real |
| 2026-09-22 | **🎉 EL BOT RESPONDE EN PRODUCCIÓN.** Con el token permanente instalado, Wilmar probó desde su celular y el bot contestó correctamente. **Cierre del piloto técnico.** Feedback de Wilmar sobre la calidad de las respuestas: pide demasiada información, es redundante y hace preguntas innecesarias — se documentó en la §3.2 con los ajustes propuestos. Se identificó la causa de fondo de la redundancia: **el bot no tiene memoria de conversación** (`handler.py` envía a Bedrock solo el mensaje actual, sin historial), así que literalmente no recuerda el turno anterior | **Próximo trabajo, en orden de impacto:** (1) memoria de conversación por número (DynamoDB) — resuelve la redundancia de raíz; (2) ajustar tono en `system_prompt.md` (más corto, una sola pregunta, no repetir); (3) completar los `PENDIENTE` del catálogo; (4) migrar al número real |
| 2026-09-22 | **Despliegue a producción + token permanente.** Se ejecutó `deploy/build-cloudshell.sh` en CloudShell (el script se subió a S3 y se bajó desde ahí, porque CloudShell corre en un iframe aislado al que no se le puede inyectar un archivo): build, push a ECR y `update-function-code`, todo OK. **Verificado en logs reales:** el catálogo carga desde S3 (`4790 caracteres`) y Claude cotiza con los precios correctos — ante *"¿cuánto vale un SSD de 512?"* respondió SATA $390.000 y M.2 NVMe $310.000 distinguiendo los dos tipos, y ante *"SSD de 1 TB"* respondió $650.000 con todo lo que incluye. El envío por WhatsApp fallaba con `403 (#131005)` y luego `401 código 190`: **el token del panel de pruebas había expirado a las 16:00 PDT** (`"Session has expired... subcode 463"`) — estos tokens no duran 24h desde que se generan, mueren a una hora fija. Se creó el **System User `compureparo-bot`** (ID `61594720229001`, rol Admin) con la app *Compureparo Bot* (rol "Desarrollar app") y la cuenta de WhatsApp (permiso "Mensajes") como activos, y se generó un token con caducidad **Nunca** y scopes `whatsapp_business_messaging` + `whatsapp_business_management`. `debug_token` confirma `"type":"SYSTEM_USER"`, `"is_valid":true`, **`"expires_at":0`** | **Dos trampas del asistente de Meta, documentadas en `deploy/README-despliegue.md`:** (1) dice *"No hay permisos disponibles"* si al system user no se le asignó la **app** como activo — no basta la cuenta de WhatsApp; (2) tras asignar activos la lista sigue diciendo "No hay activos asignados" hasta recargar la página. También se descartó prompt caching: a ~2.130 tokens de system prompt el costo es de centavos por millar de mensajes |
| 2026-09-22 | **Catálogo de precios + escalada a Wilmar + arreglo del logging.** Se leyeron las **18 respuestas rápidas reales** del WhatsApp Business de Compureparo y se descubrió que el `system_prompt.md` que existía tenía **precios inventados** (mantenimientos, redes, cámaras, planes mensuales) que no correspondían a la operación real — el bot habría cotizado mal. Se reemplazó por: (a) **`catalogo.xlsx`** con los precios reales (SSD SATA/Mac/M.2, Office, pantallas, domicilio) y las filas sin precio marcadas `PENDIENTE` para que el bot escale en vez de inventar; (b) **`app/catalogo.py`**, que lee ese Excel **desde S3** con caché de 5 min y respaldo local — así cambiar un precio no requiere reconstruir el contenedor; (c) **system prompt nuevo** con 8 reglas explícitas de escalada (precio ausente, trabajos combinados, casos complejos, pagos, agendamiento, reclamos, dudas); (d) **`handler.py` reescrito**: ahora registra el mensaje entrante, la respuesta de Claude y — lo crítico — **el código y cuerpo de error cuando WhatsApp rechaza un envío**, que era la causa de que los fallos anteriores fueran invisibles. Además, cuando el bot escala, le manda a Wilmar un WhatsApp con el número del cliente y el resumen. Infra creada: bucket S3 `compureparo-bot-catalogo` (acceso público bloqueado), política IAM `LeerCatalogoS3` acotada a ese único objeto, y variables `CATALOGO_BUCKET` y `NUMERO_WILMAR` en Lambda. Se verificó localmente que el Excel renderiza bien y que el prompt ensambla (~2.130 tokens) | Se evaluó **prompt caching** (disponible en Bedrock) y se descartó: a ese tamaño de prompt el costo es de centavos por millar de mensajes, no justifica la complejidad. **Pendiente para que esto entre en producción:** correr `deploy/build-cloudshell.sh` en CloudShell y generar el **token permanente de System User** (ver `deploy/README-despliegue.md`) |
| 2026-09-22 | **🎉 FASE 7 COMPLETADA — el bot respondió por WhatsApp de verdad.** Tras publicar la app, el mensaje real seguía sin obtener respuesta. La depuración encontró **tres bloqueos encadenados**, todos resueltos en esta sesión: **(1) La app nunca estuvo suscrita al WABA.** `GET /1848414516325768/subscribed_apps` devolvía solo la app interna de Meta ("WA DevX Webhook Events 1P App"), no "Compureparo Bot" — por eso Meta registraba el mensaje en "webhooks de prueba" pero jamás lo entregaba al Function URL. Se corrigió con un `POST /subscribed_apps` desde el Explorador de la API Graph (`{"success": true}`). Ojo: **configurar la Callback URL en el panel NO suscribe la app al WABA**; son dos pasos distintos y el panel no lo advierte. **(2) El token de WhatsApp había expirado** el 2026-09-20 22:00 PDT (`OAuthException` código 190, subcódigo 463). Se generó uno nuevo en "Paso 1. Pruébalo" y se actualizó la variable `WHATSAPP_TOKEN` en Lambda. **(3) El número de Wil no estaba en la lista de destinatarios permitidos.** El número de prueba de Meta es un sandbox: *recibe* de cualquiera, pero solo *envía* a un máximo de 5 números pre-registrados y verificados por código. La lista estaba vacía. Se agregó +57 300 810 5537 y se verificó con el código enviado por WhatsApp. Con los tres arreglos, el "Hola" obtuvo respuesta real de Claude: *"¡Hola! 👋 Bienvenido a Compureparo. ¿En qué te podemos ayudar?..."* | **Aprendizaje clave para producción:** la limitación de lista blanca es **exclusiva del número de prueba** — con el número real de Compureparo cualquier cliente escribe y el bot responde sin registrar a nadie. Ver §3.1 "Deuda técnica conocida" para lo que falta antes de migrar |
| 2026-09-22 | **GitHub Pages activado y app de Meta publicada (asistido por Claude vía navegador).** En Settings → Pages del repo se configuró Source = "Deploy from a branch", branch `main`, carpeta `/docs`. El deployment de GitHub Actions ("pages build and deployment") tardó ~2 min en pasar a `Success`; se confirmó con un fetch que `https://wymesgav.github.io/Bot-IA-Compureparo/privacy.html` ya servía el contenido real de la política. Se pegó esa URL en Meta for Developers → Configuración de la app → Básica → "URL de la política de privacidad" (guardado exitoso). Con la URL ya en vivo, se fue a Panel → "Asegúrate de que se cumplan todos los requisitos y luego publica la app" → confirmó "Se completó toda la configuración obligatoria" → botón **Publicar** → modal de confirmación: **"Tu app se publicó correctamente. Tu app está disponible para el público."** | **Para retomar:** escribir "Hola" al número de prueba (+1 555 165-6226) desde WhatsApp y revisar CloudWatch Logs (`/aws/lambda/compureparo-bot`) para confirmar que llega una invocación real y que la respuesta de Claude aparece en el chat. Si no llega, revisar "Verificación del negocio" en Casos de uso → Conectar en WhatsApp |
