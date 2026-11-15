## ---- legacy bios build (boot.asm + 32 bit kernel) ----

CFLAGS = -m32 -ffreestanding -fno-pie -fno-stack-protector \
         -fno-asynchronous-unwind-tables -fcf-protection=none \
         -O2 -Wall -Wextra

## ---- uefi build (64 bit PE app, no bootloader needed) ----

EFI_CC     = clang
EFI_CFLAGS = -target x86_64-unknown-windows -ffreestanding -fno-builtin \
             -fno-stack-protector -fno-stack-check -mno-red-zone \
             -O2 -Wall -Wextra -std=c11
EFI_LDFLAGS = -subsystem:efi_application -entry:efi_main -nodefaultlib

# arch (edk2-ovmf) paths, override on other distros, e.g.
#   make run-efi OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
OVMF_CODE ?= /usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS ?= /usr/share/edk2/x64/OVMF_VARS.4m.fd

all: os.img shutdownos.efi

## ---- bios ----

os.img: boot.bin kernel.bin
	test $$(stat -c %s kernel.bin) -le 8192
	rm -f os.img
	dd if=boot.bin   of=os.img bs=512 count=1           conv=notrunc status=none  # sector 0: stage 1
	dd if=boot.bin   of=os.img bs=512 skip=1 seek=1024  conv=notrunc status=none  # stage 2 -> sector 1024
	dd if=kernel.bin of=os.img bs=512 seek=1025         conv=notrunc status=none  # kernel -> sector 1025
	truncate -s $$((1041 * 512)) os.img                                           # pad to the end of the kernel's 16 sectors

boot.bin: boot.asm
	nasm -f bin boot.asm -o boot.bin

kernel_entry.o: kernel_entry.asm
	nasm -f elf32 kernel_entry.asm -o kernel_entry.o

kernel.o: kernel.c splash.h platform.h
	gcc $(CFLAGS) -c kernel.c -o kernel.o

platform_bios.o: platform_bios.c platform.h
	gcc $(CFLAGS) -c platform_bios.c -o platform_bios.o

kernel.elf: kernel_entry.o kernel.o platform_bios.o linker.ld
	ld -m elf_i386 -T linker.ld -o kernel.elf kernel_entry.o kernel.o platform_bios.o

kernel.bin: kernel.elf
	objcopy -O binary kernel.elf kernel.bin

run: os.img
	qemu-system-x86_64 -drive format=raw,file=os.img -display gtk

debug: os.img
	qemu-system-x86_64 -drive format=raw,file=os.img -display gtk -no-shutdown

## ---- uefi ----

kernel.efi.o: kernel.c splash.h platform.h
	$(EFI_CC) $(EFI_CFLAGS) -c kernel.c -o kernel.efi.o

platform_efi.efi.o: platform_efi.c efi.h platform.h font.h
	$(EFI_CC) $(EFI_CFLAGS) -c platform_efi.c -o platform_efi.efi.o

shutdownos.efi: kernel.efi.o platform_efi.efi.o
	lld-link $(EFI_LDFLAGS) -out:shutdownos.efi kernel.efi.o platform_efi.efi.o

# a folder laid out like an esp, qemu turns it into a fake fat drive (no mkfs/mtools needed)
esp/EFI/BOOT/BOOTX64.EFI: shutdownos.efi
	mkdir -p esp/EFI/BOOT
	cp shutdownos.efi esp/EFI/BOOT/BOOTX64.EFI

# fresh copy of the nvram every run so stale boot entries never get in the way
QEMU_EFI = qemu-system-x86_64 -machine q35 -m 256M \
           -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) \
           -drive if=pflash,format=raw,file=ovmf_vars.fd \
           -drive format=raw,file=fat:rw:esp

run-efi: esp/EFI/BOOT/BOOTX64.EFI
	cp $(OVMF_VARS) ovmf_vars.fd
	$(QEMU_EFI) -display gtk

debug-efi: esp/EFI/BOOT/BOOTX64.EFI
	cp $(OVMF_VARS) ovmf_vars.fd
	$(QEMU_EFI) -display gtk -no-shutdown

# copy onto a real esp, e.g. the t480s: sudo make install-efi ESP=/boot
ESP ?= /boot
install-efi: shutdownos.efi
	install -Dm644 shutdownos.efi $(ESP)/EFI/shutdownos/shutdownos.efi

clean:
	rm -f *.o *.bin *.elf *.efi os.img ovmf_vars.fd
	rm -rf esp

.PHONY: all run debug run-efi debug-efi install-efi clean
