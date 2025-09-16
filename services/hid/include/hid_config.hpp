#pragma once

#include <cstdint>
#include <string>

struct HTTPConfig {
    std::string bindAddress{"0.0.0.0"};
    uint16_t port{8003};
};

struct HIDInputConfig {
    bool enabled{true};
};

struct HIDDeviceIdentity {
    std::string mode{"bluetooth"};
    std::string deviceName{"JadeAI HID"};
    std::string adapter{"hci0"};
    std::string manufacturer{"JadeAI"};
    uint16_t appearance{961};
};

struct HIDSafetyConfig {
    uint32_t keypressDelayMs{20};
    uint32_t mouseMoveDelayMs{5};
    uint32_t mouseStepLimit{50};
};

struct HIDConfig {
    HIDDeviceIdentity device;
    HTTPConfig http;
    HIDInputConfig keyboard;
    HIDInputConfig mouse;
    HIDSafetyConfig safety;

    [[nodiscard]] std::string adapterPath() const { return "/org/bluez/" + device.adapter; }
};

HIDConfig loadHIDConfig(const std::string& path);
