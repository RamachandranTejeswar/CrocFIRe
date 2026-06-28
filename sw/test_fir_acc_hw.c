#include <stdint.h>

#include "uart.h"
#include "print.h"
#include "util.h"
#include "config.h"

/* =========================================================
 * FIR Accelerator Test - Croc SoC
 * 32-tap FIR Filter with Hardware Accelerator
 * ========================================================= */

#define SIGNAL_BASE_ADDR    0x10001000  /* Bank 2 start */
#define SRAM_READ_ADDRESS   0x10001800  /* Bank 3 start */
#define USER_FIR_BASE_ADDR  0x20000400  /* FIR Accelerator MM Registers   */
#define NUM_TAPS            32		

/* =========================================================
 * Signal Samples
 * ========================================================= */

int8_t signal[] = {
     10,  20,  30,  40,  50,  60,  70,  80,
     90, 100, 110, 120, 127, 120, 110, 100,
     90,  80,  70,  60,  50,  40,  30,  20,
     10,   5, -10, -20, -30, -40, -50, -60,
    -70, -80, -90,-100,-110,-120,-127,-120,
   -110,-100, -90, -80, -70, -60, -50, -40,
    -30, -20, -10,   5,  10,  20,  30,  40,
     50,  60,  70,  80,  90, 100, 110, 120
};

/* =========================================================
 * FIR Filter Coefficients (integer, pre-normalization)
 * ========================================================= */

int8_t coeffs[32] = {
     1,  2,  3,  4,  5,  6,  7,  8,
     9, 10, 11, 12, 13, 14, 15, 16,
    16, 15, 14, 13, 12, 11, 10,  9,
     8,  7,  6,  5,  4,  3,  2,  1
};

/* =========================================================
 * Global Variables
 * ========================================================= */

int8_t coeffs_q07[32];
int32_t coeff_sum = 0;
volatile uint32_t val;

int main()
{
    uart_init();
	
    /* Print User ROM message */
    for(int i = 0; i < 27; i++) {
        val = *reg32(USER_ROM_BASE_ADDR, i*4);
        if (val == 0) break;  // stop at null terminator
        printf("%c", (char)val);
    }

    printf("\n");
    uart_write_flush();

    /* Signal metadata */
    uint32_t signal_len = sizeof(signal) / sizeof(signal[0]);
    printf("Number of Samples = %x", signal_len);
    uart_write_flush();

    uint32_t padded_len = (signal_len + 3) & ~3;
    
    printf("Stack pointer: 0x%x\n", (uint32_t)__builtin_frame_address(0));
    uart_write_flush();
	
    /* Cycle counters */
    uint32_t t0, t1, t2;

    t2 = get_mcycle();

    /* -------------------------------------------------------
     * Step 1: Normalize coefficients to Q0.7 fixed-point
     * ------------------------------------------------------- */
    for (int i = 0; i < NUM_TAPS; i++) 
    {
        coeff_sum += coeffs[i];
    }

    for (int i = 0; i < NUM_TAPS; i++)
    {
        coeffs_q07[i] = (int8_t)((coeffs[i] * 128 + coeff_sum/2) / coeff_sum);
    }
    
    /* -------------------------------------------------------
     * Step 2: Write signal samples to SRAM Bank 2
     * ------------------------------------------------------- */
    // Writing the Signal Samples into Croc
    for (int i = 0; i < padded_len; i += 4) {
        uint8_t b0 = (i   < signal_len) ? (uint8_t)signal[i]   : 0;
        uint8_t b1 = (i+1 < signal_len) ? (uint8_t)signal[i+1] : 0;
        uint8_t b2 = (i+2 < signal_len) ? (uint8_t)signal[i+2] : 0;
        uint8_t b3 = (i+3 < signal_len) ? (uint8_t)signal[i+3] : 0;
        uint32_t word = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
        *reg32(SIGNAL_BASE_ADDR, i) = word;
    }

    /* -------------------------------------------------------
     * Step 3: Write Q0.7 coefficients to MM registers
     * ------------------------------------------------------- */
    // Writing the Coefficients into Croc
    for (int i = 0; i < 32; i++) {
        *reg32(USER_FIR_BASE_ADDR, 0x10 + i*4) = (uint32_t)(int32_t)coeffs_q07[i];
    }

    /* -------------------------------------------------------
     * Step 4: Configure and start accelerator
     * ------------------------------------------------------- */
    // Writing Signal Length
    *reg32(USER_FIR_BASE_ADDR, 0x8) = signal_len;

    t0 = get_mcycle();
	
    // Sending Start Signal
    *reg32(USER_FIR_BASE_ADDR, 0x0) = 0x1;

    /* Check for invalid signal length */
    if (*reg32(USER_FIR_BASE_ADDR, 0xC) == 1) {
        printf("ERROR: signal length >= 36 and <=540!\n");
        uart_write_flush();
        return 1;   // Early exit
    }

    /* -------------------------------------------------------
     * Step 5: Poll done register
     * ------------------------------------------------------- */
    // Poll done register
    while (*reg32(USER_FIR_BASE_ADDR, 0x4) == 0);
    t1 = get_mcycle();

    printf("Accelerator completed!\n");
    uart_write_flush();
    
    /* -------------------------------------------------------
     * Step 6: Print last 5 results
     * ------------------------------------------------------- */
    int start = (signal_len - NUM_TAPS >= 5) ? (signal_len - NUM_TAPS - 5) : 0;

    if (signal_len >= NUM_TAPS) 
    {
        for(int i = start; i < (signal_len - NUM_TAPS + 1); i++) 
        {
                uint32_t result = *reg32(SRAM_READ_ADDRESS, i*4);
                printf("result[%x] = 0x%x\n", i, result);
                uart_write_flush();
        }
    }
    
    else 
    {
        printf("Signal too short for FIR computation\n");
        uart_write_flush();
    }

    printf("Hardware result: Start: 0x%x, Stop: 0x%x, total cycles: 0x%x\n", t2, t1, t1-t2);
    uart_write_flush();

    return 0;

}
