; bootloader.asm - bootloader for shutdownos, a useless os

; this is the lowest level ive ever written fuck my life
; bootloader for shutdownos
; an os that boots to shut down your pc
; you could just press the power button but wheres the fun in that???

[org 0x7C00] 				; shows nasm where this code is gonna be
[bits 16] 					; cpu is in real mode

;; boot sector start ;;

STAGE2_SECTORS equ 1

STAGE2_LBA equ 1024
KERNEL_LBA equ STAGE2_LBA + STAGE2_SECTORS

KERNEL_SECTORS 	equ 16
KERNEL_SEGMENT 	equ 0x1000
KERNEL_ADDR		equ KERNEL_SEGMENT * 16

; jump over fat stuff, some bioses (usb floppy emu mode) scribble their own fat headers over these bytes,
; so if our code lived here itd get fucked
jmp short start 			; jump to the start memory
nop							; no operation, does fuck all, layout expets 3 byte jmp at the start, so this 
							; fills it ig
times 90-($-$$) db 0 		; long as we have 0 bytes left to reach 90, this'll pass and we'll be off

start:
	cli						; ignore all interrupts, we're setting up the stack

	jmp 0x0000:.flush_cs	; normalise cs incase we enter at 07C0:0000

; cs fetches
; ds reads and writes
; es is a second data segment for some bios shit
; ss is for the stack
.flush_cs:
	xor ax, ax				; clear a register, set to 0
	mov ds, ax				; set ds to 0
	mov es, ax				; set es to 0
	mov ss, ax				; set ss to 0
	mov sp, 0x7C00			; fuck the stack into the free stack region at 0x0500-0x7BFF

	sti 					; bring back interrupts, we good now

	cld						; bios can never promise df = 0. so clear our direction flag

	mov [boot_drive], dl	; save the boot drive number, becasuse dl gets fucked later

	mov si, msg_stage1		; move stage1 message to si
	call print				; print that fucker

	mov di, 3				; try reading 3 times, thats all we get

.try_read:
	mov word [dap_count], STAGE2_SECTORS	; (re)set how many sectors we want, bios overwrites this
											; with how many it actually read if it fails, could be 0
	mov si, dap				; ds:si -> disk address packet, tells the bios what to read and where
	mov ah, 0x42			; bios extended read (lba), no more cyl/head/sector bullshit
	mov dl, [boot_drive]	; which drive are we looking at, this'll be the one we saved in .flush_cs
	int 0x13				; call our bios
	jnc .read_ok			; if bios says we're okay, then jump over to .read_ok

	xor ah, ah				; bios func 0, reset disk
	mov dl, [boot_drive]	; show what drive we're doing again
	int 0x13				; call bios again
	dec di 					; decrement di by 1, di--
	jnz .try_read			; jump again if not 0, basically a loop till we hit 0

	jmp disk_error			; if we're here, it fucked smth, print an error

.read_ok:
	jmp 0x0000:stage2  		; jmp to our stage2 code

disk_error:
	mov si, msg_diskerr		; fucked up, move the disk error message to si
	call print				; print that message

hang:						; something boke baaad
	cli						; NO MORE INTERRUPTS
	hlt						; STOP YO ASS
	jmp hang				; keep repeating if we get an NMI
							; it cannot and should not go past here otherwise shit starts to break

print:
	; push these guys into the stack bc we're gonna change them and they could be getting used rn
	push ax
	push bx
	push si

	mov ah, 0x0E 			; 0x0E means print one character and move the cursor forward, we print 
							; whatever char is in al (ah is the function number)
	xor bh, bh 				; pick screen page 0

.next_char:
	lodsb					; this loads a sring byte into al from si, and adds 1 to si to point to the 
							; next char in memory
	test al, al 			; checks al
	jz .done 				; jump is zero, a byte of 0 marks the end of the string, null terminator like 
							; in c
	int 0x10				; make bios print the character to screen
	jmp .next_char			; go around again for the next character!

.done:
	; restore the below registers with what we pulled them from and return the address that call pushed
	pop si
	pop bx
	pop ax
	ret

msg_stage1	db "Stage 1: Running boot sector code.", 13, 10, 0
msg_diskerr	db "Disk read err! Something shit itself!", 13, 10, 0
boot_drive	db 0

; disk address packet, int 13h ah=0x42 reads this to know what to do
; layout is fixed by the bios spec, byte for byte
; stage 2 reuses it for the kernel, so it lives here in stage 1
dap:
	db 0x10					; size of this packet, 16 bytes
	db 0					; reserved, always 0
dap_count:		dw STAGE2_SECTORS	; how many sectors to read
dap_offset:		dw 0x7E00			; where to put them, offset...
dap_segment:	dw 0x0000			; ...and segment, so 0x0000:0x7E00
dap_lba:		dq STAGE2_LBA		; first sector to read (64 bit, counting from 0)

times 440-($-$$) db 0		; stage 1 has to fit in 440 bytes, thats the code area of the ssd's sector 0
							; everything after is the disk signature + partition table, dont touch that
times 510-($-$$) db 0 		; fills with 0 till we're at 510 bytes, if we go over, num goes negative and 
							; nasm freaks out
dw 0xAA55					; define word for boot signature, bios will only boot if this is present

;; boot sector end ;;

;;  stage 2 start  ;;

stage2: ; we're past the boot sector now, above 512 bytes at 0x7E00
	mov si, msg_stage2		; load stage2 message to si for printing
	call print
	
	; reuse stage 1's packet, just change what we're asking for
	mov word  [dap_count],   KERNEL_SECTORS	; 16 sectors
	mov word  [dap_offset],  0x0000			; to 0x1000:0x0000...
	mov word  [dap_segment], KERNEL_SEGMENT	; ...which is real address 0x10000
	mov dword [dap_lba],     KERNEL_LBA		; starting at the sector after stage 2
											; (top 4 bytes of dap_lba are already 0)

	mov si, dap				; ds:si -> the packet
	mov ah, 0x42			; extended read again
	mov dl, [boot_drive]	; use the drive we stored
	int 0x13 				; call bios
	jc disk_error			; if we carry, it means we failed and should throw an error

	mov si, msg_kernel 		; move kernel msg into si
	call print 				; print it

	;; ps: shutdownos doesnt really need this bc i doubt we'll go above 1mb ;;
	;; 	   but we might as well... ;;
	in al, 0x92 			; read value of i/o 0x92
	or al, 2 				; set to 1 (enabling A20 and turning on ram above 1mb)
	and al, 0xFE			; make sure bit 0 is clear (writing to this bit causes pc to restart)
	out 0x92, al  			; write back

	;; hide the cursor, otherwise it sits blinking on the splash ;;
	mov ah, 0x01  			; bios set cursor shape
	mov cx, 0x2000			; bit 5 of ch set = invisible
	int 0x10

	;; basic gdt ;;
	cli 					; final interrupt block, they stay off for good now
	lgdt [gdt_descriptor]	; tell cpu where to find gdt
	mov eax, cr0  			; read control reg 0, switches shit on and off
	or eax, 1  				; set bit 0 protection enable
	mov cr0, eax  			; move it back, we've hit protected mode!!!
	jmp CODE_SEG:pm_entry  	; load cs with out code selector (0x08)

[bits 32] ; we're in 32 bit mode now!!!
pm_entry:
	mov ax, DATA_SEG		; data selector
	mov ds, ax  			; point every seg register at it
	mov es, ax 
	mov fs, ax  
	mov gs, ax  
	mov ss, ax  
	mov esp, 0x90000		; fresh stack, free memory well clear
	jmp KERNEL_ADDR			; we're done! pass over to the kernel.

msg_stage2 db "Stage 2: loaded into memory above 512 bytes (0x7E00).", 13, 10, 0
msg_kernel db "Kernel loaded at 0x10000. We are switching into 32 bit mode motherfucker!", 13, 10, 0

;; GDT stuff ;;
gdt_start:
	dq 0 					; mandatory null descriptor (8 zero bytes)

gdt_code:
	dw 0xFFFF 				; limit, bits 0-15
	dw 0x0000  				; base, 0-15
	db 0x00  				; base 16-23
	db 10011010b  			; access byte (below)
	db 11001111b  			; flags top 4 bits, limit bits 16-19
	db 0x00  				; base, 24-31

gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b            ; same as code, but marked as writable data
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:             ; the 6-byte structure that lgdt reads
    dw gdt_end - gdt_start - 1  ; size of the table, minus 1 (the CPU wants it that way)
    dd gdt_start                ; address of the table (dd = 4 bytes)

CODE_SEG equ gdt_code - gdt_start   ; = 8, byte position of the code entry
DATA_SEG equ gdt_data - gdt_start   ; = 16, byte position of the data entry

times 512*(1+STAGE2_SECTORS)-($-$$) db 0 	; extend sectors as we're outside of boot sector now
