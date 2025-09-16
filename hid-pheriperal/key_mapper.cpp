#include "key_mapper.h"

std::optional<KeyInfo> map_character(char ch) {
    if (ch >= 'a' && ch <= 'z') {
        return KeyInfo{static_cast<uint8_t>(0x04 + (ch - 'a')), false};
    }
    if (ch >= 'A' && ch <= 'Z') {
        return KeyInfo{static_cast<uint8_t>(0x04 + (ch - 'A')), true};
    }
    if (ch >= '1' && ch <= '9') {
        return KeyInfo{static_cast<uint8_t>(0x1E + (ch - '1')), false};
    }
    switch (ch) {
        case '0':
            return KeyInfo{0x27, false};
        case '!':
            return KeyInfo{0x1E, true};
        case '@':
            return KeyInfo{0x1F, true};
        case '#':
            return KeyInfo{0x20, true};
        case '$':
            return KeyInfo{0x21, true};
        case '%':
            return KeyInfo{0x22, true};
        case '^':
            return KeyInfo{0x23, true};
        case '&':
            return KeyInfo{0x24, true};
        case '*':
            return KeyInfo{0x25, true};
        case '(':
            return KeyInfo{0x26, true};
        case ')':
            return KeyInfo{0x27, true};
        case '\n':
        case '\r':
            return KeyInfo{0x28, false};
        case '\t':
            return KeyInfo{0x2B, false};
        case '\b':
            return KeyInfo{0x2A, false};
        case '\x1b':
            return KeyInfo{0x29, false};
        case ' ':
            return KeyInfo{0x2C, false};
        case '-':
            return KeyInfo{0x2D, false};
        case '_':
            return KeyInfo{0x2D, true};
        case '=':
            return KeyInfo{0x2E, false};
        case '+':
            return KeyInfo{0x2E, true};
        case '[':
            return KeyInfo{0x2F, false};
        case '{':
            return KeyInfo{0x2F, true};
        case ']':
            return KeyInfo{0x30, false};
        case '}':
            return KeyInfo{0x30, true};
        case '\\':
            return KeyInfo{0x31, false};
        case '|':
            return KeyInfo{0x31, true};
        case ';':
            return KeyInfo{0x33, false};
        case ':':
            return KeyInfo{0x33, true};
        case '\'':
            return KeyInfo{0x34, false};
        case '"':
            return KeyInfo{0x34, true};
        case '`':
            return KeyInfo{0x35, false};
        case '~':
            return KeyInfo{0x35, true};
        case ',':
            return KeyInfo{0x36, false};
        case '<':
            return KeyInfo{0x36, true};
        case '.':
            return KeyInfo{0x37, false};
        case '>':
            return KeyInfo{0x37, true};
        case '/':
            return KeyInfo{0x38, false};
        case '?':
            return KeyInfo{0x38, true};
        default:
            return std::nullopt;
    }
}
