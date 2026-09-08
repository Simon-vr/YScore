typedef unsigned int uint32_t;

static uint32_t data[33] =
{
    0x12345678, 0xABCDEF01, 0x13572468, 0xDEADBEEF,
    1,2,3,4,
    5,6,7,8,
    0xffffffff,0x80000000,0x7fffffff,
    0x11111111,0x22222222,0x33333333,0x44444444,
    0x55555555,0xaaaaaaaa,0x87654321,0x10203040,
    10,20,30,40,
    50,60,70,80,
    0x1234,0x5678
};

static uint32_t checksum(const uint32_t *p, int n)
{
    uint32_t s = 0;

    for(int i=0;i<n;i++)
        s ^= p[i] + (uint32_t)i;

    return s;
}

static uint32_t logic_mix(uint32_t x)
{
    x ^= x << 7;
    x ^= x >> 9;
    x ^= x << 8;

    x ^= 0x13579BDF;
    x += 0x2468ACE0;
    x -= 0x10203040;

    return x;
}

int test(void)
{
    volatile uint32_t mem[64];

    uint32_t state = 0x13579BDF;

    /*
     * 30000 rounds is intended to give roughly
     * a few seconds on the current FPGA CPU.
     *
     * Adjust this number according to measured time.
     */
    for(int round=0; round<30000; round++)
    {
        /* --------------------------------------------
         * Static .data access
         * -------------------------------------------- */

        state ^= checksum(data,33);


        /* --------------------------------------------
         * Memory write
         * -------------------------------------------- */

        uint32_t base = state;

        for(int i=0;i<64;i++)
        {
            mem[i] = base + (uint32_t)i * 17;
        }


        /* --------------------------------------------
         * Memory read + verify
         * -------------------------------------------- */

        for(int i=0;i<64;i++)
        {
            uint32_t expected =
                base + (uint32_t)i * 17;

            uint32_t value = mem[i];

            if(value != expected)
                return 2;

            state ^= value;
        }


        /* --------------------------------------------
         * Logic / shift
         * -------------------------------------------- */

        state = logic_mix(state);


        /* --------------------------------------------
         * Signed comparison / branch
         * -------------------------------------------- */

        {
            int a = (int)state;
            int b = -123456789;

            if(a < b)
                state += 5;
            else
                state += 7;
        }


        /* --------------------------------------------
         * Unsigned comparison / branch
         * -------------------------------------------- */

        {
            uint32_t a = state;
            uint32_t b = 0x87654321;

            if(a > b)
                state ^= 0x55555555;
            else
                state ^= 0xAAAAAAAA;
        }


        /* --------------------------------------------
         * Arithmetic
         * -------------------------------------------- */

        state += 12345;
        state -= 6789;
    }


    /*
     * Final deterministic check.
     *
     * First run on the host / simulator:
     *
     *     return state;
     *
     * Record the result.
     *
     * Then replace this section with:
     *
     *     if(state != 0xXXXXXXXX)
     *         return 4;
     */

    return 1;
}