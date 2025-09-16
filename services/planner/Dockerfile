FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY planner.py ./planner.py

CMD ["python", "-m", "http.server", "8002"]
