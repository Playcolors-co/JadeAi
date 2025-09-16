#include "hid_reports.hpp"

#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <unordered_map>

namespace {

constexpr uint8_t kLeftShift = 0x02;

std::optional<HIDKeyboardStroke> lookupFromTable(char ch)
{
    static const std::unordered_map<char, HIDKeyboardStroke> table = {
        {'1', {0x1E, 0x00}}, {'2', {0x1F, 0x00}}, {'3', {0x20, 0x00}}, {'4', {0x21, 0x00}},
        {'5', {0x22, 0x00}}, {'6', {0x23, 0x00}}, {'7', {0x24, 0x00}}, {'8', {0x25, 0x00}},
        {'9', {0x26, 0x00}}, {'0', {0x27, 0x00}},
        {'-', {0x2D, 0x00}}, {'=', {0x2E, 0x00}}, {'[', {0x2F, 0x00}}, {']', {0x30, 0x00}},
        {'\\', {0x31, 0x00}}, {';', {0x33, 0x00}}, {'\'', {0x34, 0x00}}, {'`', {0x35, 0x00}},
        {',', {0x36, 0x00}}, {'.', {0x37, 0x00}}, {'/', {0x38, 0x00}},
        {'!', {0x1E, kLeftShift}}, {'@', {0x1F, kLeftShift}}, {'#', {0x20, kLeftShift}},
        {'$', {0x21, kLeftShift}}, {'%', {0x22, kLeftShift}}, {'^', {0x23, kLeftShift}},
        {'&', {0x24, kLeftShift}}, {'*', {0x25, kLeftShift}}, {'(', {0x26, kLeftShift}},
        {')', {0x27, kLeftShift}}, {'_', {0x2D, kLeftShift}}, {'+', {0x2E, kLeftShift}},
        {'{', {0x2F, kLeftShift}}, {'}', {0x30, kLeftShift}}, {'|', {0x31, kLeftShift}},
        {':', {0x33, kLeftShift}}, {'"', {0x34, kLeftShift}}, {'~', {0x35, kLeftShift}},
        {'<', {0x36, kLeftShift}}, {'>', {0x37, kLeftShift}}, {'?', {0x38, kLeftShift}},
        {' ', {0x2C, 0x00}}, {'\t', {0x2B, 0x00}}, {'\n', {0x28, 0x00}}, {'\r', {0x28, 0x00}},
        {'\b', {0x2A, 0x00}},
    };

    if (auto it = table.find(ch); it != table.end()) {
        return it->second;
    }
    return std::nullopt;
}

} // namespace

std::optional<HIDKeyboardStroke> lookupKeyboardStroke(char ch)
{
    if ('a' <= ch && ch <= 'z') {
        return HIDKeyboardStroke{static_cast<uint8_t>(0x04 + (ch - 'a')), 0x00};
    }
    if ('A' <= ch && ch <= 'Z') {
        return HIDKeyboardStroke{static_cast<uint8_t>(0x04 + (ch - 'A')), kLeftShift};
    }

    if (auto stroke = lookupFromTable(ch); stroke.has_value()) {
        return stroke;
    }

    return std::nullopt;
}

std::array<uint8_t, 9> makeKeyboardReport(uint8_t modifiers, uint8_t keycode)
{
    std::array<uint8_t, 9> report{};
    report[0] = 0x01; // report id
    report[1] = modifiers;
    report[2] = 0x00; // reserved
    report[3] = keycode;
    // remaining bytes default zero
    return report;
}

const std::array<uint8_t, 9>& makeKeyboardReleaseReport()
{
    static const std::array<uint8_t, 9> report{0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    return report;
}

std::array<uint8_t, 5> makeMouseReport(uint8_t buttons, int8_t dx, int8_t dy, int8_t wheel)
{
    std::array<uint8_t, 5> report{};
    report[0] = 0x02; // report id for mouse
    report[1] = buttons;
    report[2] = static_cast<uint8_t>(dx);
    report[3] = static_cast<uint8_t>(dy);
    report[4] = static_cast<uint8_t>(wheel);
    return report;
}

uint8_t mouseButtonMask(MouseButton button)
{
    switch (button) {
    case MouseButton::Left:
        return 0x01;
    case MouseButton::Right:
        return 0x02;
    case MouseButton::Middle:
        return 0x04;
    }
    return 0x00;
}

MouseButton mouseButtonFromString(const std::string& name)
{
    std::string lower = name;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (lower == "left") {
        return MouseButton::Left;
    }
    if (lower == "right") {
        return MouseButton::Right;
    }
    if (lower == "middle" || lower == "mid") {
        return MouseButton::Middle;
    }
    throw std::invalid_argument("Unsupported mouse button: " + name);
}
