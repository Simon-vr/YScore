/*
 * 纯加减法实现的整数乘除/取余运算库
 * 目标架构为 RV32I（无 M 扩展），因此乘除法完全由移位 + 加减实现
 */

/* ==================== 基础工具 ==================== */

/* 无符号乘法：移位 + 加法（Booth 式累加） */
static unsigned int umul_core(unsigned int a, unsigned int b)
{
    unsigned int result = 0U;

    while (b != 0U) {
        if ((b & 1U) != 0U) {
            result += a;
        }
        a <<= 1;
        b >>= 1;
    }

    return result;
}

/* 无符号除法核心：恢复余数法（按位试商），同时得到商和余数 */
static unsigned int udivmod_core(unsigned int dividend,
                                 unsigned int divisor,
                                 unsigned int *remainder)
{
    unsigned int quotient = 0U;
    unsigned int rem = 0U;
    unsigned int i;

    *remainder = 0U;

    if (divisor == 0U) {
        return 0U;  /* 除零：商返回0，余数保持0 */
    }

    for (i = 32U; i > 0U; --i) {
        rem = (rem << 1) | ((dividend >> (i - 1U)) & 1U);
        if (rem >= divisor) {
            rem -= divisor;
            quotient |= (1U << (i - 1U));
        }
    }

    *remainder = rem;
    return quotient;
}

/* ==================== 公开 API ==================== */

unsigned int umul(unsigned int a, unsigned int b)
{
    return umul_core(a, b);
}

/* 有符号乘法：取绝对值相乘，再按符号修正 */
int imul(int a, int b)
{
    unsigned int ua = (a < 0) ? (unsigned int)(-(a + 1)) + 1U : (unsigned int)a;
    unsigned int ub = (b < 0) ? (unsigned int)(-(b + 1)) + 1U : (unsigned int)b;
    unsigned int product = umul_core(ua, ub);

    if ((a < 0) != (b < 0)) {
        return -(int)(product - 1U) - 1;
    }

    return (int)product;
}

/* 无符号除法：返回商 */
unsigned int udiv(unsigned int dividend, unsigned int divisor)
{
    unsigned int r;

    return udivmod_core(dividend, divisor, &r);
}

/* 无符号取余：返回余数 */
unsigned int umod(unsigned int dividend, unsigned int divisor)
{
    unsigned int r;

    udivmod_core(dividend, divisor, &r);
    return r;
}

/* 有符号除法：商向零取整 */
int idiv(int dividend, int divisor)
{
    unsigned int udividend = (dividend < 0) ? (unsigned int)(-(dividend + 1)) + 1U : (unsigned int)dividend;
    unsigned int udivisor  = (divisor < 0)  ? (unsigned int)(-(divisor + 1)) + 1U  : (unsigned int)divisor;
    unsigned int r;
    unsigned int quotient = udivmod_core(udividend, udivisor, &r);

    if ((dividend < 0) != (divisor < 0)) {
        return -(int)(quotient - 1U) - 1;
    }

    return (int)quotient;
}

/* 有符号取余：余数符号与被除数一致 */
int imod(int dividend, int divisor)
{
    unsigned int udividend = (dividend < 0) ? (unsigned int)(-(dividend + 1)) + 1U : (unsigned int)dividend;
    unsigned int udivisor  = (divisor < 0)  ? (unsigned int)(-(divisor + 1)) + 1U  : (unsigned int)divisor;
    unsigned int r;

    if (udivisor == 0U) {
        return 0;
    }

    udivmod_core(udividend, udivisor, &r);

    if (dividend < 0) {
        return -(int)(r - 1U) - 1;
    }

    return (int)r;
}