FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY handler.py system_prompt.md ./

CMD ["handler.lambda_handler"]
