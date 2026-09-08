#include "portmacro.h"
#include "utils.h"

const char *utils_skip_spaces(const char *text)
{
    while (*text == ' ' || *text == '\t') {
        ++text;
    }

    return text;
}

int utils_streq(const char *left, const char *right)
{
    while (*left != '\0' && *right != '\0') {
        if (*left != *right) {
            return 0;
        }

        ++left;
        ++right;
    }

    return (*left == '\0' && *right == '\0');
}

uint32_t utils_parse_hex(const char *str)
{
    uint32_t value = 0U;
    char c;

    if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
        str += 2;
    }

    while ((c = *str) != '\0') {
        value <<= 4U;
        if (c >= '0' && c <= '9') {
            value |= (uint32_t)(c - '0');
        } else if (c >= 'a' && c <= 'f') {
            value |= (uint32_t)(c - 'a' + 10);
        } else if (c >= 'A' && c <= 'F') {
            value |= (uint32_t)(c - 'A' + 10);
        } else {
            break;
        }
        ++str;
    }

    return value;
}