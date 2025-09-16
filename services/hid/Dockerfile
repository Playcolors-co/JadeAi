FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        pkg-config \
        libsdbus-c++-dev \
        libyaml-cpp-dev \
        libbluetooth-dev \
        bluez \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/jadeai/hid

COPY CMakeLists.txt ./
COPY include ./include
COPY src ./src

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --target jadeai-hid -- -j$(nproc) && \
    cmake --install build --prefix /opt/jadeai

RUN rm -rf build

WORKDIR /opt/jadeai

CMD ["/opt/jadeai/bin/jadeai-hid"]
