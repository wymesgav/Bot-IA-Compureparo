FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt ./
RUN pip install -r requirements.txt

# catalogo.xlsx va incluido como respaldo: si S3 falla, el bot sigue cotizando.
# La fuente real de precios es el catalogo en S3 (ver app/catalogo.py).
COPY handler.py catalogo.py system_prompt.md catalogo.xlsx ./

CMD ["handler.lambda_handler"]
