FROM python:3.10-slim

WORKDIR /app

COPY lab1/requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY lab1/ ./lab1/

CMD ["python", "--version"]