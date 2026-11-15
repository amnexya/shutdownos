#include <stdint.h>
#include "splash.h"

// send 16 bit val to io port
// c cant do this so we use asm
// gcc syntax is so ugly ugh
static inline void outw(uint16_t port, uint16_t value) {
	__asm__ volatile ("outw %0, %1" : : "a"(value), "Nd"(port));
}

// text mode screen mem
#define VGA ((volatile uint16_t *)0xB8000)

static void print_at(const char *s, int row,uint8_t colour) {
	volatile uint16_t *cell = VGA + row * 80; // start of the row
	while (*s)								// until null terminator
		*cell++ = (uint16_t)((colour << 8) | (uint8_t)*s++);
}

static void show_splash(void)
{
    for (int i = 0; i < 80 * 25; i++)
        VGA[i] = splash[i];     // copy each cell (char + colours) straight to the screen
}

// The main attraction, kernel_main!!!
void kernel_main(void) {
	show_splash();
	print_at("Welcome to shutdownOS!", 21, 0x0F);

	// fake loading because this is a joke
	print_at("Loading from disk... This may take a minute.", 22, 0x0F);

	for (volatile int i = 0; i < 0x11111111; i++) { }

	print_at("Thanks for using shutdownOS. Goodbye!", 23, 0x0F);

	for (volatile int i = 0; i < 0x11111111; i++) { }

	outw(0x604,  0x2000);   // QEMU
	outw(0xB004, 0x2000);   // Bochs / old QEMU
	outw(0x4004, 0x3400);   // VirtualBox

	// give pc a moment to actually turn off
	for (volatile int i = 0; i < 0x1000000; i++) { }

	print_at("Shutdown failed, hit the power button like a normal person you freak.", 24, 0x0F);
}