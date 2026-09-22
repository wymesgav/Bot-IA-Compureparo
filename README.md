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
- [ ] **Fase 7 — Piloto:** ✅ Pipeline técnico confirmado (webhook → Bedrock → intento de envío por WhatsApp, sin errores) con un payload simulado. ⏳ Falta la prueba real: escribirle al número de prueba de Meta desde un celular y confirmar que la respuesta llega a WhatsApp. Cuando esté estable, migrar al número real de Compureparo.

## 4. Estructura del proyecto

```
Bot IA/
├── README.md              ← este archivo (plan + decisiones)
└── app/
    ├── Dockerfile          ← imagen para Lambda (contenedor)
    ├── requirements.txt
    ├── handler.py          ← webhook de Meta + llamada a Bedrock
    ├── system_prompt.md    ← "cerebro" del bot: quién es, servicios y precios de Compureparo
    └── .env.example        ← variables de entorno necesarias (no subir el .env real a ningún lado)
```

## 5. Variables de entorno necesarias

| Variable | De dónde sale |
|---|---|
| `WHATSAPP_TOKEN` | Meta for Developers → tu app → WhatsApp → token temporal (o permanente tras verificar negocio) |
| `WHATSAPP_VERIFY_TOKEN` | Lo inventas tú (cualquier string) — se usa para verificar el webhook |
| `WHATSAPP_PHONE_NUMBER_ID` | Meta for Developers → tu app → WhatsApp → "From" number ID |
| `BEDROCK_MODEL_ID` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` — es un **perfil de inferencia** (ARN cross-region), no el ID base del modelo. Verificar vigencia en el catálogo de Bedrock antes de reusar este valor en el futuro, los modelos Anthropic van quedando EOL con el tiempo |
| `BEDROCK_REGION` | `us-east-1` (recomendado — ahí Bedrock/Claude suele estar disponible primero) |

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
