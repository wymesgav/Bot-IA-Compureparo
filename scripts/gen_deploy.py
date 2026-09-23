"""Genera deploy/build-cloudshell.sh a partir de los archivos reales de app/.

Asi el script de despliegue nunca queda desincronizado del codigo.
"""

from pathlib import Path

RAIZ = Path(
    r"C:\Users\Will\OneDrive - INSTITUTO TECNOLOGICO METROPOLITANO - ITM"
    r"\Desktop\Claude\Proyectos\Perfil\Bot IA"
)
APP = RAIZ / "app"

ARCHIVOS = ["requirements.txt", "Dockerfile", "system_prompt.md", "catalogo.py", "handler.py"]

CABECERA = """#!/bin/bash
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
"""

PIE = """
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

aws ecr describe-repositories --repository-names "$REPO" --region "$REGION" >/dev/null 2>&1 \\
  || aws ecr create-repository --repository-name "$REPO" --region "$REGION" >/dev/null

echo ">> Construyendo imagen"
docker build -t "$REPO" .
docker tag "$REPO:latest" "$ECR/$REPO:latest"

echo ">> Subiendo imagen a ECR"
docker push "$ECR/$REPO:latest"

echo ">> Actualizando la funcion Lambda"
aws lambda update-function-code \\
  --function-name "$FUNCION" \\
  --image-uri "$ECR/$REPO:latest" \\
  --region "$REGION" >/dev/null

aws lambda wait function-updated --function-name "$FUNCION" --region "$REGION"

echo ""
echo "LISTO - la Lambda ya corre el codigo nuevo."
echo "Recuerda que las variables de entorno se configuran en la consola de Lambda."
"""


def bloque(nombre: str, contenido: str) -> str:
    delim = "EOF_" + nombre.replace(".", "_").replace("-", "_").upper()
    # Delimitador entre comillas: evita que bash expanda $ o backticks del contenido.
    return f"cat > {nombre} <<'{delim}'\n{contenido.rstrip()}\n{delim}\n\n"


partes = [CABECERA]
for nombre in ARCHIVOS:
    texto = (APP / nombre).read_text(encoding="utf-8")
    delim = "EOF_" + nombre.replace(".", "_").replace("-", "_").upper()
    if any(linea.strip() == delim for linea in texto.splitlines()):
        raise SystemExit(f"El delimitador {delim} choca con el contenido de {nombre}")
    partes.append(bloque(nombre, texto))
partes.append(PIE)

destino = RAIZ / "deploy" / "build-cloudshell.sh"
destino.parent.mkdir(exist_ok=True)
# newline="\n": CloudShell es Linux; con CRLF bash falla con "bad interpreter".
destino.write_text("".join(partes), encoding="utf-8", newline="\n")
print("OK ->", destino)
print("Tamano:", destino.stat().st_size, "bytes")
