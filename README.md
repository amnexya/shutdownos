# SHUTDOWNOS

Made for Durhack 2026, horrific, never use.

Don't you just love having a completely useless OS with a fully custom built bootloader in assembly, that turns your PC off whenever you boot into it! Load this thing and have fun! freak.

Now available in two delicious flavours:

- **Legacy BIOS**: hand-written two-stage NASM bootloader → 32-bit protected mode → C kernel. Only really works in qemu.
- **UEFI**: the same C kernel, built as a 64-bit EFI app. Draws the VGA text screen onto the GOP framebuffer and powers off through the firmware's `ResetSystem`, so it **really turns off real hardware**.

## BIOS

```sh
sudo pacman -S --needed nasm base-devel qemu-desktop
make run
# or if you don't want the window to close
make debug
```

## UEFI

```sh
sudo pacman -S --needed clang lld edk2-ovmf qemu-desktop
make run-efi
# or if you don't want the window to close
make debug-efi
```

### Booting it on a real machine (e.g. the T480s)

1. Turn Secure Boot off in the firmware setup (the binary isn't signed). If you use `sbctl`, `sudo sbctl sign /boot/EFI/shutdownos/shutdownos.efi` works instead.
2. Copy it onto the ESP:
   ```sh
   make shutdownos.efi
   sudo make install-efi ESP=/boot     # -> /boot/EFI/shutdownos/shutdownos.efi
   ```
3. Add a firmware boot entry **without** putting it in the boot order (unless you want every boot to be a shutdown):
   ```sh
   findmnt /boot                        # check which disk + partition the ESP is
   sudo efibootmgr --create-only --disk /dev/nvme0n1 --part 1 \
        --label "ShutdownOS" --loader '\EFI\shutdownos\shutdownos.efi'
   ```
4. Reboot, mash F12, pick ShutdownOS. Watch your laptop turn itself off.

To get rid of it: `sudo efibootmgr -b XXXX -B` (number from `efibootmgr`) and delete `/boot/EFI/shutdownos`.

## Credits

The UEFI build renders text with [Spleen](https://github.com/fcambus/spleen) 8x16 (CP437), © Frederic Cambus, BSD 2-Clause, see `LICENSE-spleen`.

## Disclosure
AI was used a small amount in this project, primarily for small bug fixes I could not figure out myself. The model used was Claude Opus 5.5 on effort level High. It primarily assisted with the NASM bootloader, and the EFI port.
