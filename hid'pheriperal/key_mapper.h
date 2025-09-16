#ifndef KEY_MAPPER_H
#define KEY_MAPPER_H

#include <cstdint>
#include <optional>
#include <string>

struct KeyInfo {
    uint8_t keycode;
    bool requires_shift;
};

std::optional<KeyInfo> map_character(char ch);

#endif // KEY_MAPPER_H
