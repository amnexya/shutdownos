; kernel_entry.asm - helper to enter the kernel, as it's written in C

[bits 32]               ; we're in 32-bit protected mode

section .text.entry     ; custom section, so the linker script puts it first

global _start           ; make _start visible to the linker
extern kernel_main      ; kernel_main exists in the C file, "trust me bro"

_start:
    call kernel_main    ; call into C to start the kernel

    ; if we get here, kernel_main returned
    mov esi, kernel_hang_msg
    mov edi, 0xB8000    ; row 0, top left corner
    call print32

.hang:                  ; park the CPU forever
    cli
    hlt
    jmp .hang           ; loops to the hlt, NOT back to the print

; print32: write a null-terminated string straight into screen memory
;   in: esi -> string, edi -> screen position
print32:
    mov ah, 0x0C        ; colour: light red on black, since it's an error
.next:
    lodsb               ; al = next char from [esi], esi++
    test al, al         ; end of string?
    jz .done
    stosw               ; write al (char) + ah (colour) to [edi], edi += 2
    jmp .next
.done:
    ret

kernel_hang_msg db "Kernel returned, you either stopped it or it crashed. Unfortunately you're gonna have to use your power button this time.", 0