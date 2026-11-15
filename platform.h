// platform.h - everything the kernel needs from whatever booted it
// the kernel only knows about an 80x25 grid of vga style cells (char + colour byte)
// each boot path (bios / uefi) provides these, so kernel.c doesnt care how it got here
#pragma once
#include <stdint.h>

#define TEXT_COLS 80
#define TEXT_ROWS 25

// 80x25 cells, low byte = char (cp437), high byte = colour (bg << 4 | fg)
// bios: this IS the real vga memory at 0xB8000
// uefi: theres no vga text mode, so its a buffer in ram that plat_present() draws
extern volatile uint16_t *const text_buffer;

void plat_present(void);			// get text_buffer onto the screen (bios: no-op, vga does it for us)
void plat_sleep_ms(uint32_t ms);	// wait a bit
void plat_shutdown(void);			// try to turn the pc off. if this returns, it didnt work
