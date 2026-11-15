CFLAGS = -m32 -ffreestanding -fno-pie -fno-stack-protector \
         -fno-asynchronous-unwind-tables -fcf-protection=none \
         -O2 -Wall -Wextra

os.img: boot.bin kernel.bin
	test $$(stat -c %s kernel.bin) -le 8192
	rm -f os.img
	dd if=boot.bin   of=os.img bs=512 count=1           conv=notrunc status=none  # sector 0: stage 1
	dd if=boot.bin   of=os.img bs=512 skip=1 seek=1024  conv=notrunc status=none  # stage 2 -> sector 1024
	dd if=kernel.bin of=os.img bs=512 seek=1025         conv=notrunc status=none  # kernel -> sector 1025
	truncate -s $$((1041 * 512)) os.img          conv=notrunc status=none  # kernel -> sector 1025
	truncate -s $$((1041 * 512)) os.img                                   # pad to the end of the kernel's 16 sectors                                  # pad to the end of the kernel's 16 sectors

boot.bin: boot.asm
	nasm -f bin boot.asm -o boot.bin

kernel_entry.o: kernel_entry.asm
	nasm -f elf32 kernel_entry.asm -o kernel_entry.o

kernel.o: kernel.c splash.h
	gcc $(CFLAGS) -c kernel.c -o kernel.o

kernel.elf: kernel_entry.o kernel.o linker.ld
	ld -m elf_i386 -T linker.ld -o kernel.elf kernel_entry.o kernel.o

kernel.bin: kernel.elf
	objcopy -O binary kernel.elf kernel.bin

run: os.img
	qemu-system-x86_64 -drive format=raw,file=os.img -display gtk

debug: os.img
	qemu-system-x86_64 -drive format=raw,file=os.img -display gtk -no-shutdown

clean:
	rm -f *.o *.bin *.elf os.img

.PHONY: run debug clean