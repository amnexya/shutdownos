#include <stdint.h>
#include "platform.h"
#include "splash.h"

// the kernel is the same for bios and uefi now, all the hardware stuff
// (vga memory, io ports, uefi calls) lives in platform_bios.c / platform_efi.c

static void print_at(const char *s, int row, uint8_t colour) {
	volatile uint16_t *cell = text_buffer + row * TEXT_COLS; // start of the row
	while (*s)								// until null terminator
		*cell++ = (uint16_t)((colour << 8) | (uint8_t)*s++);
}

static void show_splash(void)
{
    for (int i = 0; i < TEXT_COLS * TEXT_ROWS; i++)
        text_buffer[i] = splash[i];     // copy each cell (char + colours) straight to the screen
}

// The main attraction, kernel_main!!!
void kernel_main(void) {
	show_splash();
	print_at("Welcome to shutdownOS!", 21, 0x0F);

	// fake loading because this is a joke
	print_at("Loading from disk... This may take a minute.", 22, 0x0F);
	plat_present();

	plat_sleep_ms(3000);

	print_at("Thanks for using shutdownOS. Goodbye!", 23, 0x0F);
	plat_present();

	plat_sleep_ms(3000);

	plat_shutdown();	// should never come back from this

	print_at("Shutdown failed, hit the power button like a normal person you freak.", 24, 0x0F);
	plat_present();
}
