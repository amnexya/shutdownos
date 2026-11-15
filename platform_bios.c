// platform_bios.c - the legacy bios side, 32 bit protected mode, loaded by boot.asm
#include <stdint.h>
#include "platform.h"

// text mode screen mem, the vga card draws whatever we write here
volatile uint16_t *const text_buffer = (volatile uint16_t *)0xB8000;

// send 16 bit val to io port
// c cant do this so we use asm
// gcc syntax is so ugly ugh
static inline void outw(uint16_t port, uint16_t value) {
	__asm__ volatile ("outw %0, %1" : : "a"(value), "Nd"(port));
}

void plat_present(void) {
	// nothing to do, vga hardware reads 0xB8000 by itself
}

// no timer set up (interrupts are off and theres no idt), so just burn cycles
// very roughly calibrated against the old 0x11111111 loop, real speed depends on the cpu
void plat_sleep_ms(uint32_t ms) {
	for (volatile uint32_t i = 0; i < ms * 95000u; i++) { }
}

void plat_shutdown(void) {
	// these only work on emulators, real hardware needs acpi (which is why uefi exists lol)
	outw(0x604,  0x2000);   // QEMU
	outw(0xB004, 0x2000);   // Bochs / old QEMU
	outw(0x4004, 0x3400);   // VirtualBox

	// give pc a moment to actually turn off
	plat_sleep_ms(200);
}
