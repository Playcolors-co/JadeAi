FROM python:3.11-slim

# Install system and build dependencies
RUN apt-get update && apt-get install -y \
    bluetooth \
    bluez \
    bluez-tools \
    usbutils \
    network-manager \
    wireless-tools \
    iw \
    v4l-utils \
    ffmpeg \
    build-essential \
    gcc \
    pkg-config \
    python3-dev \
    libdbus-1-dev \
    libglib2.0-dev \
    python3-dbus \
    python3-netifaces \
    python3-bluez \
    libbluetooth-dev \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY . .

# Create necessary directories with proper permissions
RUN mkdir -p /app/logs /app/data /app/scripts && \
    chmod -R 777 /app/logs /app/data /app/scripts

# Expose port
EXPOSE 5000

# Run the application with proper environment
CMD ["python", "-u", "app.py"]
