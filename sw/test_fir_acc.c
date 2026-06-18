#include <stdint.h>

#include "uart.h"
#include "print.h"
#include "util.h"
#include "config.h"

#define SIGNAL_BASE_ADDR 0x10001100
#define SRAM_READ_ADDRESS 0x10001900
#define USER_FIR_BASE_ADDR 0x20000400
#define NUM_TAPS     32

// ******************************** SIGNAL SAMPLES BEGIN ********************************

int8_t signal[] = {
     -71, -116,   12,   -3,  -14,  -57,  -76,  -84,
      88, -112, -113,  -81,  -17,   -9, -115,  -27,
      86,  -16,  101,   14, -125,  -47,   88,   46,
      14,  -49,  -18,   44,  -76,  -81,   66,  -79,
      55,   48,    7, -106,  107,  -65,   65,  -88,
      22,   57,  -30,  -93, -105,  -12,   20,  -88,
      -9,  -77,   66,   14,  104,   58,  -45,   61,
      53,  -21,    8,  -92,  -41,   -3,  -45,  108,
      66,   10,  -16,   38, -100,  -11, -112,   33,
      77,    9,  -95,  -20,   33,  -20,  127,   74,
     106,  -55,    7,  -57,   -2,    6,   91,   76,
      57,  -16,  -58,  124,  -82, -104,  -72,  -50,
     -47,   88,  -96,   69,   67,  111,    0, -123,
     -70,    8,   46,  -71,   22,   94,  -48,  104,
    -127,    6,  -37,  -74,   24,  -27,  -50,   63,
     -46, -128,   37,  122, -119,  -71,   57,   29,
      -6,  -99,   -5,  -88,  -85,  120,  -93,  -64,
     -63,  115,  -44,    7,   88,  -20,  -26,   31,
      76,   63,   96,  103,  -67,   -2,  -13,  -96,
      45, -118,  -11,  -16, -125,  -92,  -98,  -11,
     -94, -112,   41,  -92,   -7,   14,  120,  -19,
     -61,  114,   -4,  114,   80,  -31,  -80,  -79,
      92,   53,   88,   82,  111, -101,  -78,  -97,
      78,   45,  -73,   -1,  -30,  -31,  101,  -57,
      88,  -35,   14,  108,   -1,  -90,   98,  -78,
    -103, -121,  -81,   -7,  -43,   80,  120,  118,
     -19,   77,  -98,  -44,   66, -127,   71,    7,
     104,   18,   88,  121,  -49,  -31,   23,  -17,
     -99,  -97,   32,  -99, -103,  116,  -48,  -99,
     -87,  -33,  -93,  -94,   -8,   78,  -67,   -2,
    -108,  -87,   86,   33,    5,  -24,   32,   -6,
       7,   74,  -61,   25,  106,   33,  -91, -124,
     106,  -77,  -91,  -19,    7,  -61,   50,  -93,
      -3,   61,   17,  -48,   96,   26, -124,   25,
     -75,  -60,    7,  -69,  -74,  -49,   11,   16,
     -21,   47,  -24,    7,  122,    0, -102,  -81,
      88,   13, -106, -127,   42,  -62,    6,  -46,
      98,   90, -124,  -71,  -90,  -52, -110,   61,
     -53,   92,  -63, -107,   29,   58, -108,   55,
     -21,   -1,  -76,   53,   80,  -49,   -7,  -45,
     -38,   83, -116,  -37,   42,   82,   -1,    8,
     -47,  -73,   67, -109,  112,  -15,  -26,  107,
      51,   28,  -12,  -14, -116,  -30,   76,   40,
      14,  -93,   14,   51,   76,   41, -114,  -69,
       5,  -37,    7, -109,  -73,   94,   48,   32,
      95,  -69,   69,  -31,    2, -106,   95, -128,
     -28,   58,   92, -102,    9,  -84,   80,    8,
     -73, -109,   66,   42,   46, -102,  -47,  -59,
      44,   42,   -3,  -45, -128,   95,  -84,   65,
     -93, -125,   33,  101,  -76, -106,  -81,  -56,
     -64, -118,   21,   92,  116,    7,  112, -110,
      28,   47,  119,  -23,   33, -122,   75,   94,
     120,   86,   63, -112,  -36,  -86,  121,    6,
     -41,   43,   44,   72,  -91,  105,   70,   44,
    -120,  -32,  -83,   58, -122,   52,  -11,   79,
     -98,   19,  125,   -9,  119,  -38,  -50,   99,
      65,  108, -106, -123,  -60,  105,  -30, -118,
       3,   52,   11,   94,   87, -128,  -73,  -96,
      53,  -83,  -86,   93, -124,   65,  -91,   78,
    -114,   37,    6,  113, -112,   43,   84,   50,
    -116,  -45,   86,  -96,  -55,   62,   -8,  -88,
     -99,   70,   28,  -54,   21,   71,   60,  -64,
      44,  -67,  -43,   69,   93,  -97,  -59,  104,
    -118,   50,  102,  102,   27,   91, -114,  -47
};


// ******************************** SIGNAL SAMPLES END ********************************

int8_t coeffs[32] = {
     1,  2,  3,  4,  5,  6,  7,  8,
     9, 10, 11, 12, 13, 14, 15, 16,
    16, 15, 14, 13, 12, 11, 10,  9,
     8,  7,  6,  5,  4,  3,  2,  1
};

volatile int fir_done_flag = 0;
int8_t coeffs_q07[32];
volatile uint32_t val;
int32_t coeff_sum = 0;

void croc_interrupt_handler(uint32_t mcause) {
     fir_done_flag = 1;  // set regardless of mcause for now
}

void delay(uint32_t cycles) {
    volatile uint32_t i;
    for (i = 0; i < cycles; i++);
}

int main()
{
    uart_init();

    for(int i = 0; i < 27; i++) {
        val = *reg32(USER_ROM_BASE_ADDR, i*4);
        if (val == 0) break;  // stop at null terminator
        printf("%c", (char)val);
    }

    printf("\n");
    uart_write_flush();

    uint32_t signal_len = sizeof(signal) / sizeof(signal[0]);
    printf("Number of Samples = %x", signal_len);
    uart_write_flush();

    uint32_t padded_len = (signal_len + 3) & ~3;
    
    printf("Stack pointer: 0x%x\n", (uint32_t)__builtin_frame_address(0));
    uart_write_flush();

    uint32_t t0, t1, t2;

    t2 = get_mcycle();
    
    // **************** Normalization ****************
    
    for (int i = 0; i < NUM_TAPS; i++)
    {
        coeff_sum += coeffs[i];
    }

    for (int i = 0; i < NUM_TAPS; i++)
    {
        coeffs_q07[i] = (int8_t)((coeffs[i] * 128 + coeff_sum/2) / coeff_sum);
    }
    
    // Writing the Signal Samples into Croc
    for (int i = 0; i < padded_len; i += 4) {
        uint8_t b0 = (i   < signal_len) ? (uint8_t)signal[i]   : 0;
        uint8_t b1 = (i+1 < signal_len) ? (uint8_t)signal[i+1] : 0;
        uint8_t b2 = (i+2 < signal_len) ? (uint8_t)signal[i+2] : 0;
        uint8_t b3 = (i+3 < signal_len) ? (uint8_t)signal[i+3] : 0;
        uint32_t word = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
        *reg32(SIGNAL_BASE_ADDR, i) = word;
    }

    // Writing the Coefficients into Croc
    for (int i = 0; i < 32; i++) {
        *reg32(USER_FIR_BASE_ADDR, 0x10 + i*4) = (uint32_t)(int32_t)coeffs_q07[i];
    }

    // set_interrupt_enable(1, IRQ_EXTERNAL);
    // set_interrupt_enable(1, 20);
    // set_global_irq_enable(1);

    *reg32(USER_FIR_BASE_ADDR, 0x8) = signal_len;

    t0 = get_mcycle();

    // printf("Writing start signal...\n");
    // uart_write_flush();
    *reg32(USER_FIR_BASE_ADDR, 0x0) = 0x1;
    // printf("Start signal written\n");
    // uart_write_flush();

    if (*reg32(USER_FIR_BASE_ADDR, 0xC) == 1) {
        // printf("ERROR: signal length >= 36 and <=512!\n");
        // uart_write_flush();
        return 1;   // Early exit
    }

    // while (!fir_done_flag) {
    //     wfi();
    // }

    // Poll done register
    while (*reg32(USER_FIR_BASE_ADDR, 0x4) == 0);
    t1 = get_mcycle();

    printf("Accelerator completed!\n");
    uart_write_flush();
    
    int start = (signal_len - NUM_TAPS >= 5) ? (signal_len - NUM_TAPS - 5) : 0;

    if (signal_len >= NUM_TAPS) 
    {
        for(int i = start; i < (signal_len - NUM_TAPS + 1); i++) 
        {
                uint32_t result = *reg32(0x10001900, i*4);
                printf("result[%x] = 0x%x\n", i, result);
                uart_write_flush();
        }
    }
    
    else 
    {
        printf("Invalid signal size\n");
        uart_write_flush();
    }

    printf("Hardware result: (0x%x cycles)\n", t1-t2);

    uart_write_flush();

    return 0;

}
