# Raw findings: OpenWrt on ASUS RT-AX57 Go (session of 2026-11-15)

All facts below were observed directly on one unit. Personal identifiers (full MAC, serial, PIN,
public IP, passwords) are intentionally omitted and must stay omitted.

## Unit
- Label: Model RT-AX57 Go, "AX3000 Dual Band WiFi 6 Router", H/W Ver A1, production year 2024,
  FCC ID MSQ-RTAX6C00, PN 90IG08N0-MA1C0V. Label MAC (redacted).
- Stock firmware before flashing: 3.0.0.6.102_56747 (extendno 56747-g6eb1e48_260-g5da16_M6PH),
  nvram productid = "PRT-AX57_GO", territory_code US/01. Stock kernel Linux 5.4.246 aarch64.
- Stock /proc/mtd:
    mtd0 0x00400000 "Bootloader"
    mtd1 0x07c00000 "UBI_DEV"
    mtd2 0x0001f000 "nvram"      (gluebi of UBI vol)
    mtd3 0x000f8000 "Factory"
    mtd4 0x000f8000 "Factory2"
    mtd5 0x045fe000 "linux"
    mtd6 0x042b5870 "rootfs"
- Stock UBI volumes: ubi0_0 nvram 126976, ubi0_1 Factory 1015808, ubi0_2 Factory2 1015808,
  ubi0_3 linux 73392128, ubi0_4 jffs2 47362048.
- Factory and Factory2 are byte-identical. Factory begins `81 79 00 00` (MT7981 EEPROM id) then the
  label MAC at offset 0x4. The label MAC appears 3 times in Factory.

## Source / build
- Fork: github.com/jonathan-sturges/openwrt, branch asus_rt-ax57go, commit 30865d9
  ("mediatek: filogic: add support for ASUS RT-AX57GO"). Replaces stalled upstream PR openwrt/openwrt#15055.
- OpenWrt SNAPSHOT r36793, Linux 6.18.54, built in WSL2 Ubuntu. Config: target mediatek/filogic,
  device asus_rt-ax57go, + luci, luci-ssl. Default packages incl. kmod-mt7915e, mt7981 firmware, wpad-basic-mbedtls, kmod-usb3.
- At time of testing the fork branch had NO commits newer than 30865d9 (git fetch checked).

## Backup method that worked (stock firmware)
- Factory reset; completed setup by calling the same endpoints the QIS wizard uses:
  GET /chpass.cgi (base64 new_username/new_passwd) then POST /applyapp.cgi JSON with
  x_Setting=1, sshd_enable=2 (LAN only), sshd_port=22, sshd_authkeys=<ed25519 pubkey>,
  rc_service=restart_sshd. (Doing it in the web UI is equivalent.)
- Stock dropbear accepted an ed25519 key.
- Dumped via `ssh admin@192.168.50.1 'cat /dev/mtdNro'` and `/dev/ubi0_N` from Linux (not PowerShell).
- GOTCHA: mtd1 (whole UBI) and ubi0_4 (jffs2) md5 differ between two reads because they are live.
  Fix: snapshot to router RAM first (`cat /dev/mtd1ro > /tmp/snap.bin`; tmpfs had ~238 MB free,
  124 MB fits), md5 there, then copy. All 10 images then matched router-side md5.

## Install via stock web UI: CONFIRMED WORKING (previously listed as untested)
- Uploaded openwrt-mediatek-filogic-asus_rt-ax57go-initramfs.trx through
  Administration > Firmware Upgrade > Manual (multipart POST to /upgrade.cgi, field "file").
  Stock 3.0.0.6.102_56747 accepted it with no error; router came up as OpenWrt at 192.168.1.1
  about 60-70 s later.
- The .trx and stock ASUS .trx both start with a uImage-style header carrying name "PRT-AX57_GO".
  Stock trx has extra non-zero bytes in its 64-byte trailer; the OpenWrt trx has zeros there, and it was still accepted.
- ASUS wrote exactly the initramfs-kernel.bin payload (trx wrapper stripped) into UBI volume
  "linux" (ubi0_3): first 9699328 bytes of ubi0_3 md5 == initramfs-kernel.bin md5.
  Consequence: after the web-UI flash, the router boots the OpenWrt initramfs from flash on every power cycle (stock is gone).
- Practical trick: a new initramfs can be tested by `ubiupdatevol /dev/ubi0_3 new-initramfs-kernel.bin` + reboot.

## Bugs found in commit 30865d9 and fixed (see patches/)
1. WAN PHY calibration (most important)
   - Symptom (dmesg): `MediaTek MT7981 PHY mdio-bus:00: invalid efuse data` then
     `probe with driver MediaTek MT7981 PHY failed with error -22`; WAN falls back to "Generic PHY", uncalibrated.
   - Cause: board DTS overrides the SoC internal GbE PHY (mdio-bus/ethernet-phy@0, which mt7981b.dtsi already
     gives `nvmem-cells = <&phy_calibration>` from efuse@11f20000 phy-calib@8dc, 0x10 bytes) with
     `nvmem-cells = <&precal_factory_1010>` = Wi-Fi pre-cal data in Factory (0x6f010 bytes). Driver
     mt798x_phy_calibration() requires buf[0..3] non-zero and len >= 16 -> reads wrong data -> -EINVAL.
   - Fix: delete the two nvmem lines from the board phy0 node so the SoC efuse cell applies.
   - After fix: `eth1: PHY [mdio-bus:00] driver [MediaTek MT7981 PHY]`, 1Gbps/Full, DHCP lease, internet OK.
2. gpio-keys (reset button) not working
   - Symptom: `gpio-keys keys: Button node 'vpn_switch' without keycode` then probe failed -22;
     the whole gpio-keys device fails, so the RESET button is also dead.
   - Fix: add `linux,code = <BTN_0>;` to vpn_switch (EV_SW). After fix, gpio-keys binds.
     Physical reset press not yet tested.
3. WAN MAC blank/random
   - Symptom: uci `network.@device[1].macaddr=':'`, eth1 random MAC each boot.
   - Cause: 02_network uses `mtd_get_mac_binary "Factory" 0x4` but Factory is a UBI volume, not MTD.
     `mtd_get_mac_binary_ubi` alone also fails because it looks up UBI part named by CI_UBIPART (default "ubi").
   - Fix: `label_mac=$(CI_UBIPART="UBI_DEV" mtd_get_mac_binary_ubi "Factory" 0x4)`.
   - After fix: LAN = label MAC, WAN = label MAC +1, persists across reboot.

## Permanent install
- From OpenWrt initramfs: `scp -O` sysupgrade.bin to /tmp, `sysupgrade -T` OK, `sysupgrade -n`.
- platform.sh asus_initial_setup (when running from initramfs) removes rootfs/rootfs_data/jffs2 and
  recreates jffs2 at 0x3e000; nand_do_upgrade replaces "linux" etc. Factory/Factory2/nvram untouched.
- Post-install UBI: nvram, Factory, Factory2, linux 4825088, jffs2 253952, rootfs 5332992,
  rootfs_data 109834240, provisioning 253952. Overlay ~90 MB free (ubifs).
- Factory md5 identical before and after (verified).
- Boot to SSH after sysupgrade: about 60 s.

## Test results after permanent install
- LAN: OK (test PC adapter was 100 Mbps-limited; the EN8801SC link itself is fine).
- WAN: 1 Gbps link, DHCP from ISP, internet OK.
- Wi-Fi: both radios (phy0 2.4 GHz 2412-2484 MHz, phy1 5 GHz 5180-5885 MHz) detected; Factory eeprom/precal
  loaded. AP on both bands (same SSID, sae-mixed). Windows client on 5 GHz: signal -33 dBm,
  1200.9 Mbit/s HE-MCS 11 2SS 80 MHz both directions; 25 MB download over Wi-Fi at ~41 Mbit/s (ISP-limited).
- Radio MACs: phy0 = label MAC; phy1 = label MAC with the locally-administered bit set in the first octet.
- LEDs present: green:power, red:status, white:status, mt76-phy0, mt76-phy1.
- USB: xhci-mtk probes, USB 3.2 root hubs registered; no device plugged in, so storage not tested.
- Reboot persistence: config, Wi-Fi, root password, MACs all persist.
- No errors in dmesg after fixes (other than benign rdinit message).

## Not tested / open
- ASUS rescue mode (Firmware Restoration, 192.168.1.x TFTP) on this model.
- Physical reset button press and VPN switch events.
- USB storage.
- Serial console pinout (not opened).
- Going back to stock from OpenWrt.

## Stock downloads (for reference; link, do not redistribute)
- ASUS support API lists firmware 3.0.0.6.102_57206 (2026-10-07, sha256 AC5CCB8B...275D58),
  3.0.0.6.102_56747 (2025-12-22, sha256 29732755...AF27A1) and older; Firmware Restoration 2.1.0.3.
