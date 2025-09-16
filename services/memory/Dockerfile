FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN if [ -s requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

COPY memory.py ./memory.py

CMD ["python", "-m", "http.server", "8004"]
