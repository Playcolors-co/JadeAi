#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string>

enum class MouseButton {
    Left,
    Right,
    Middle
};

struct HIDKeyboardStroke {
    uint8_t usage{0};
    uint8_t modifiers{0};
};

std::optional<HIDKeyboardStroke> lookupKeyboardStroke(char ch);

std::array<uint8_t, 9> makeKeyboardReport(uint8_t modifiers, uint8_t keycode);
const std::array<uint8_t, 9>& makeKeyboardReleaseReport();

std::array<uint8_t, 5> makeMouseReport(uint8_t buttons, int8_t dx, int8_t dy, int8_t wheel = 0);
uint8_t mouseButtonMask(MouseButton button);
MouseButton mouseButtonFromString(const std::string& name);
