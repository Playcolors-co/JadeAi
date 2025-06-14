FROM debian:bullseye

# Install dependencies
RUN apt-get update && apt-get install -y \
  python3 python3-pip \
  libglib2.0-dev libbluetooth-dev \
  build-essential dbus bluez bluez-tools \
  && rm -rf /var/lib/apt/lists/*

# Copy code
WORKDIR /app
COPY . /app
RUN pip3 install -r requirements.txt

# Compile C GATT HID server
RUN gcc -o hid-bt main.c -lbluetooth -pthread

CMD ["python3", "api_server.py"]
