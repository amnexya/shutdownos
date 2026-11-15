// platform_efi.c - the uefi side of shutdownos
//
// no bootloader needed here: the firmware reads EFI/BOOT/BOOTX64.EFI (or whatever the boot entry
// points at) off the fat32 esp, loads it like a normal program and calls efi_main in 64 bit long mode.
// we never call ExitBootServices, the firmware can keep running the machine, we just borrow
// the screen and then ask it nicely to power off. and unlike the bios build, that actually
// works on real hardware, because ResetSystem goes through the firmware's own acpi code.
#include <stdint.h>
#include <stddef.h>
#include "efi.h"
#include "platform.h"
#include "font.h"

void kernel_main(void);

static EFI_SYSTEM_TABLE  *st;
static EFI_BOOT_SERVICES *bs;
static EFI_GRAPHICS_OUTPUT_PROTOCOL *gop;		// NULL if the firmware has no framebuffer for us

// uefi has no vga text mode, so the kernel writes into this and plat_present() draws it
static uint16_t cells[TEXT_COLS * TEXT_ROWS];
volatile uint16_t *const text_buffer = cells;

// the 80x25 grid is 640x400 pixels with the 8x16 font, we scale that up to fit the screen
#define SRC_W (TEXT_COLS * 8)
#define SRC_H (TEXT_ROWS * 16)

static uint32_t out_w, out_h, out_x, out_y;		// size + position of the scaled picture
static EFI_GRAPHICS_OUTPUT_BLT_PIXEL *backbuf;	// we draw here, then blt the whole thing in one go
static uint16_t *xmap, *ymap;					// screen pixel -> source pixel, nearest neighbour

// the standard 16 vga colours, in uefi's {blue, green, red, reserved} order
static const EFI_GRAPHICS_OUTPUT_BLT_PIXEL vga_palette[16] = {
	{0x00,0x00,0x00,0}, {0xAA,0x00,0x00,0}, {0x00,0xAA,0x00,0}, {0xAA,0xAA,0x00,0},
	{0x00,0x00,0xAA,0}, {0xAA,0x00,0xAA,0}, {0x00,0x55,0xAA,0}, {0xAA,0xAA,0xAA,0},
	{0x55,0x55,0x55,0}, {0xFF,0x55,0x55,0}, {0x55,0xFF,0x55,0}, {0xFF,0xFF,0x55,0},
	{0x55,0x55,0xFF,0}, {0xFF,0x55,0xFF,0}, {0x55,0xFF,0xFF,0}, {0xFF,0xFF,0xFF,0},
};

// no libc, but the compiler is allowed to emit calls to these for loops/struct copies, so they must exist
void *memset(void *d, int c, size_t n) {
	uint8_t *p = d;
	while (n--) *p++ = (uint8_t)c;
	return d;
}
void *memcpy(void *d, const void *s, size_t n) {
	uint8_t *p = d;
	const uint8_t *q = s;
	while (n--) *p++ = *q++;
	return d;
}

// work out how big we can draw the 640x400 picture, and grab memory for it
static int setup_screen(void) {
	uint32_t scr_w = gop->Mode->Info->HorizontalResolution;
	uint32_t scr_h = gop->Mode->Info->VerticalResolution;

	// fit 640x400 (16:10) inside the screen, keep the aspect ratio, black bars on the sides
	if ((uint64_t)scr_w * SRC_H <= (uint64_t)scr_h * SRC_W) {
		out_w = scr_w;
		out_h = (uint32_t)((uint64_t)scr_w * SRC_H / SRC_W);
	} else {
		out_h = scr_h;
		out_w = (uint32_t)((uint64_t)scr_h * SRC_W / SRC_H);
	}
	out_x = (scr_w - out_w) / 2;
	out_y = (scr_h - out_h) / 2;

	if (bs->AllocatePool(EfiLoaderData, (UINTN)out_w * out_h * sizeof(*backbuf), (void **)&backbuf) != EFI_SUCCESS ||
	    bs->AllocatePool(EfiLoaderData, out_w * sizeof(*xmap), (void **)&xmap) != EFI_SUCCESS ||
	    bs->AllocatePool(EfiLoaderData, out_h * sizeof(*ymap), (void **)&ymap) != EFI_SUCCESS)
		return 0;

	for (uint32_t x = 0; x < out_w; x++) xmap[x] = (uint16_t)((uint64_t)x * SRC_W / out_w);
	for (uint32_t y = 0; y < out_h; y++) ymap[y] = (uint16_t)((uint64_t)y * SRC_H / out_h);

	// wipe the whole screen black, gets rid of the lenovo logo / firmware text
	EFI_GRAPHICS_OUTPUT_BLT_PIXEL black = {0, 0, 0, 0};
	gop->Blt(gop, &black, EfiBltVideoFill, 0, 0, 0, 0, scr_w, scr_h, 0);
	return 1;
}

// backup plan if theres no framebuffer: dump the text rows through the firmware console.
// the splash is all half-block chars so it gets skipped, you just get the words
static void present_console(void) {
	CHAR16 line[TEXT_COLS + 1];
	for (int row = 0; row < TEXT_ROWS; row++) {
		int len = 0, last = -1;
		for (int col = 0; col < TEXT_COLS; col++) {
			uint8_t ch = (uint8_t)cells[row * TEXT_COLS + col];
			if (ch < 0x20 || ch > 0x7E) ch = ' ';
			line[len++] = ch;
			if (ch != ' ') last = col;
		}
		if (last < 0) continue;			// empty row, dont bother
		line[last + 1] = 0;				// chop trailing spaces so we dont wrap + scroll
		st->ConOut->SetCursorPosition(st->ConOut, 0, (UINTN)row);
		st->ConOut->OutputString(st->ConOut, line);
	}
}

// draw all 80x25 cells exactly like a vga card would: look up the glyph, fg colour for
// set bits, bg colour for clear bits. the splash's 0xDF half blocks come out as 2 "pixels" per cell
void plat_present(void) {
	if (!gop) { present_console(); return; }

	EFI_GRAPHICS_OUTPUT_BLT_PIXEL *px = backbuf;
	for (uint32_t y = 0; y < out_h; y++) {
		uint32_t sy = ymap[y];
		const uint16_t *row = cells + (sy / 16) * TEXT_COLS;
		uint32_t gy = sy % 16;							// which line of the glyph
		for (uint32_t x = 0; x < out_w; x++) {
			uint32_t sx = xmap[x];
			uint16_t cell = row[sx / 8];
			uint8_t ch = (uint8_t)cell, attr = (uint8_t)(cell >> 8);
			int on = font8x16[ch][gy] & (0x80 >> (sx % 8));
			// bg only gets 3 bits, bit 7 is "blink" on real vga
			*px++ = vga_palette[on ? (attr & 0x0F) : ((attr >> 4) & 0x07)];
		}
	}
	gop->Blt(gop, backbuf, EfiBltBufferToVideo, 0, 0, out_x, out_y, out_w, out_h, 0);
}

void plat_sleep_ms(uint32_t ms) {
	bs->Stall((UINTN)ms * 1000);	// real timer this time, takes microseconds
}

void plat_shutdown(void) {
	// the firmware does the acpi s5 dance for us. works on qemu (ovmf) AND the t480s
	st->RuntimeServices->ResetSystem(EfiResetShutdown, EFI_SUCCESS, 0, NULL);
}

// firmware jumps here. image = our own handle, systab = the keys to the kingdom
EFI_STATUS EFIAPI efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab) {
	(void)image;
	st = systab;
	bs = systab->BootServices;

	// firmware resets the pc after 5 min if a boot app hasnt finished. funny, but no
	bs->SetWatchdogTimer(0, 0, 0, NULL);

	st->ConOut->EnableCursor(st->ConOut, 0);
	st->ConOut->ClearScreen(st->ConOut);

	static const EFI_GUID gop_guid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
	if (bs->LocateProtocol(&gop_guid, NULL, (void **)&gop) != EFI_SUCCESS || !setup_screen())
		gop = NULL;		// no framebuffer, fall back to the text console

	kernel_main();

	// kernel came back, so the shutdown failed. dont return to the firmware or it'll just
	// boot the next entry (arch) and that would ruin the bit. sit here with the message up instead
	for (;;)
		__asm__ volatile ("hlt");
}
