/* linker.ld - everything goes into mem */

ENTRY(_start)

SECTIONS
{
    . = 0x10000;                /* "." = current address. Start at KERNEL_ADDR */
                                /* (this is the linker's version of [org 0x10000]) */

    .text : {
        *(.text.entry)          /* the stub FIRST, so it's the byte at 0x10000 */
        *(.text*)               /* then all other code */
    }
    .rodata : { *(.rodata*) }   /* read-only data: your string literals end up here */
    .data   : { *(.data*) }     /* initialised global variables */
    .bss    : { *(COMMON) *(.bss*) }  /* zero-initialised globals */

    /DISCARD/ : { *(.note*) *(.comment) *(.eh_frame) }  /* compiler metadata we don't want */
}