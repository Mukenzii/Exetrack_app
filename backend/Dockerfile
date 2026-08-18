FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Data directory for SQLite DB and Telegram session (mounted as volume)
RUN mkdir -p /data

ENV DB_PATH=/data/exetrack.db
ENV TELEGRAM_SESSION=/data/exetrack_session

EXPOSE 8000

CMD ["python3", "main.py"]
