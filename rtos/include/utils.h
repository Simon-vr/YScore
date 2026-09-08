#ifndef UTILS_H
#define UTILS_H
#include "portmacro.h"
const char *utils_skip_spaces(const char *text);
int utils_streq(const char *left, const char *right);
uint32_t utils_parse_hex(const char *str);

#endif // UTILS_H