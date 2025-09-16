#include "hid_config.hpp"

#include <cstdlib>
#include <filesystem>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

#include <yaml-cpp/yaml.h>

namespace {

std::string resolveEnvTokens(std::string value)
{
    if (value.size() < 4 || value[0] != '$' || value[1] != '{' || value.back() != '}') {
        return value;
    }

    const auto inner = value.substr(2, value.size() - 3);
    const auto colonPos = inner.find(':');
    const auto key = inner.substr(0, colonPos);
    std::string defaultValue;
    if (colonPos != std::string::npos) {
        defaultValue = inner.substr(colonPos + 1);
    }

    if (const char* envValue = std::getenv(key.c_str()); envValue != nullptr) {
        return envValue;
    }

    return defaultValue;
}

std::string getString(const YAML::Node& node, std::string_view key, const std::string& fallback)
{
    if (!node || !node[key.data()]) {
        return fallback;
    }

    auto value = node[key.data()].as<std::string>();
    return resolveEnvTokens(value);
}

uint16_t getUInt16(const YAML::Node& node, std::string_view key, uint16_t fallback)
{
    if (!node || !node[key.data()]) {
        return fallback;
    }

    const auto raw = resolveEnvTokens(node[key.data()].as<std::string>());
    try {
        const auto parsed = static_cast<unsigned long>(std::stoul(raw, nullptr, 0));
        if (parsed > std::numeric_limits<uint16_t>::max()) {
            throw std::out_of_range("appearance out of range");
        }
        return static_cast<uint16_t>(parsed);
    } catch (const std::exception& ex) {
        throw std::runtime_error("Failed to parse numeric value for key '" + std::string(key) + "': " + ex.what());
    }
}

uint32_t getUInt32(const YAML::Node& node, std::string_view key, uint32_t fallback)
{
    if (!node || !node[key.data()]) {
        return fallback;
    }

    const auto raw = resolveEnvTokens(node[key.data()].as<std::string>());
    try {
        const auto parsed = static_cast<unsigned long>(std::stoul(raw, nullptr, 0));
        if (parsed > std::numeric_limits<uint32_t>::max()) {
            throw std::out_of_range("value out of range");
        }
        return static_cast<uint32_t>(parsed);
    } catch (const std::exception& ex) {
        throw std::runtime_error("Failed to parse numeric value for key '" + std::string(key) + "': " + ex.what());
    }
}

bool getBool(const YAML::Node& node, std::string_view key, bool fallback)
{
    if (!node || !node[key.data()]) {
        return fallback;
    }

    const auto valueStr = resolveEnvTokens(node[key.data()].as<std::string>());
    if (valueStr == "1" || valueStr == "true" || valueStr == "True" || valueStr == "yes") {
        return true;
    }
    if (valueStr == "0" || valueStr == "false" || valueStr == "False" || valueStr == "no") {
        return false;
    }
    throw std::runtime_error("Failed to parse boolean for key '" + std::string(key) + "'");
}

} // namespace

HIDConfig loadHIDConfig(const std::string& path)
{
    if (!std::filesystem::exists(path)) {
        throw std::runtime_error("HID configuration file not found: " + path);
    }

    const auto root = YAML::LoadFile(path);
    HIDConfig config;

    config.device.mode = getString(root, "mode", config.device.mode);
    if (config.device.mode != "bluetooth") {
        throw std::runtime_error("Unsupported HID mode '" + config.device.mode + "'. Only 'bluetooth' is implemented in the C++ service.");
    }

    config.device.deviceName = getString(root, "device_name", config.device.deviceName);
    config.device.adapter = getString(root, "ble_adapter", config.device.adapter);

    if (const auto deviceNode = root["hid"]; deviceNode) {
        config.device.manufacturer = getString(deviceNode, "manufacturer", config.device.manufacturer);
        config.device.appearance = getUInt16(deviceNode, "appearance", config.device.appearance);

        if (const auto keyboardNode = deviceNode["keyboard"]; keyboardNode) {
            config.keyboard.enabled = getBool(keyboardNode, "enabled", config.keyboard.enabled);
        }

        if (const auto mouseNode = deviceNode["mouse"]; mouseNode) {
            config.mouse.enabled = getBool(mouseNode, "enabled", config.mouse.enabled);
        }
    }

    if (const auto httpNode = root["http"]; httpNode) {
        config.http.bindAddress = getString(httpNode, "bind", config.http.bindAddress);
        config.http.port = getUInt16(httpNode, "port", config.http.port);
    }

    if (const auto safetyNode = root["safety"]; safetyNode) {
        config.safety.keypressDelayMs = getUInt32(safetyNode, "keypress_delay_ms", config.safety.keypressDelayMs);
        config.safety.mouseMoveDelayMs = getUInt32(safetyNode, "mouse_move_delay_ms", config.safety.mouseMoveDelayMs);
        config.safety.mouseStepLimit = getUInt32(safetyNode, "mouse_step_limit", config.safety.mouseStepLimit);
        if (config.safety.mouseStepLimit == 0) {
            config.safety.mouseStepLimit = 1;
        }
    }

    return config;
}
