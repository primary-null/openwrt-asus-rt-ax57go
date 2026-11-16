# OpenWrt on the ASUS RT-AX57 Go: tested install + fixes

This repository documents a complete, tested OpenWrt install on an **ASUS RT-AX57 Go** (MediaTek
MT7981B). It also provides small fixes to the community device support. The fixes were needed
to get the WAN PHY, the buttons, the MAC addresses and the status LED working.

- Base: [jonathan-sturges/openwrt](https://github.com/jonathan-sturges/openwrt), branch
  `asus_rt-ax57go`, commit `30865d9` ("mediatek: filogic: add support for ASUS RT-AX57GO"). That
  branch continues the stalled upstream pull request
  [openwrt/openwrt#15055](https://github.com/openwrt/openwrt/pull/15055).
- Fixes: [`patches/`](patches/) (`git format-patch` series, apply with `git am`).
- Install path: stock web UI firmware upload of an OpenWrt initramfs `.trx`, then `sysupgrade`.
  **Confirmed on stock firmware 3.0.0.6.102_56747**, H/W version A1. No serial console or
  bootloader changes are needed.
- Tested on one unit on 2026-11-15.

> **This is not official OpenWrt support.** This device is not in an OpenWrt release. You use
> these images and instructions at your own risk. Before you flash anything, back up your flash
> (see [step 1](#1-back-up-the-stock-flash)).

---

## What's new here (and what isn't)

From a prior-art check of the OpenWrt forum thread, PR #15055 and the fork (details and links in
[notes/PRIOR-ART.md](notes/PRIOR-ART.md)):

- **New as far as we could find:** a *confirmed* install from the stock ASUS web UI on this model
  (stock 3.0.0.6.102_56747). The forum thread only predicted it "should" work. There was no
  public test report for fork commit `30865d9` before this one.
- **New diagnosis:** three regressions in fork commit `30865d9` (WAN PHY calibration, dead reset
  button, blank WAN MAC), plus a missing blue LED channel (bug 4) found by comparing against the
  stock ASUS configuration and confirmed on hardware. The fork's `25.12-asus-rt-ax57go` branch has the same DTS and
  `02_network` code, so it very likely has the same bugs. That branch was not built or tested here.
- **Not new:** the fixes. Two of them restore what upstream PR #15055 already did (efuse
  `phy_calibration`, `CI_UBIPART="UBI_DEV"` + `mtd_get_mac_binary_ubi`), and the third uses a
  standard pattern (`linux,code = <BTN_0>` on an EV_SW switch). The web-UI install method is
  already standard for sibling ASUS Filogic routers (RT-AX52, RT-AX57M).

---

## Status summary

| Feature | Status | Notes |
|---|---|---|
| Flash from stock web UI (`.trx` upload) | ✅ Works | Accepted by stock 3.0.0.6.102_56747 with no error. Newer stock versions not tested. |
| Boot OpenWrt initramfs | ✅ Works | Up at 192.168.1.1 about 60–70 s after upload. |
| Permanent install (`sysupgrade -n`) | ✅ Works | SSH comes up about 60 s after sysupgrade. |
| WAN port (1 GbE, SoC internal PHY) | ✅ Works **with the patch** | 1 Gbps/Full link, DHCP from ISP, internet OK. Without the patch the PHY is uncalibrated (Generic PHY). |
| LAN port (EN8801SC PHY) | ✅ Works | Tested only at 100 Mbps because the test PC's adapter was limited to 100 Mbps. The link itself is fine. |
| Wi-Fi 2.4 GHz (phy0) | ✅ Works | AP up. Calibration data loaded from Factory. |
| Wi-Fi 5 GHz (phy1) | ✅ Works | HE80, 2 spatial streams, 1200.9 Mbit/s link rate (HE-MCS 11) in both directions. |
| MAC addresses | ✅ Correct **with the patch** | LAN = label MAC, WAN = label MAC + 1, persistent. Without it the WAN MAC is random on every boot. |
| `gpio-keys` driver (reset button, VPN switch) | ✅ Binds **with the patch** | Without the patch the whole `gpio-keys` device fails, so the reset button is also dead. |
| Reset button / VPN switch (physical press) | ❓ Not tested | |
| LEDs | ✅ Works **with patch 0002** | `green:power`, `red:status`, `white:status`, `mt76-phy0`, `mt76-phy1`, plus `blue:status` from patch 0002. Without it the blue channel glows permanently (bug 4). |
| USB | ⚠️ Partially tested | `xhci-mtk` probes and the USB 3.2 root hubs register. No USB device was plugged in, so storage was not tested. |
| Config persistence across reboot | ✅ Works | Config, Wi-Fi, root password and MACs persist. |
| Factory (calibration/MAC) partition preserved | ✅ Verified | Factory md5 was identical before and after install. |
| ASUS rescue mode (Firmware Restoration / TFTP) | ❓ Not tested | |
| Going back to stock from OpenWrt | ❓ Not tested | |
| Serial console | ❓ Not tested | The unit was not opened. |

---

## Hardware facts

| Item | Value |
|---|---|
| Model (label) | RT-AX57 Go, "AX3000 Dual Band WiFi 6 Router" |
| H/W version | A1 (production year 2024) |
| FCC ID | MSQ-RTAX6C00 |
| SoC | MediaTek MT7981B (Filogic 820) |
| Wi-Fi | MT7981 integrated, 2.4 GHz + 5 GHz, driver `mt7915e` |
| WAN PHY | MT7981 internal GbE PHY (`mdio-bus:00`) |
| LAN PHY | Airoha EN8801SC (`ethernet-phy@24`) |
| Flash | NAND, 128 MiB (4 MiB `Bootloader` + 124 MiB `UBI_DEV`) |
| Stock firmware tested | 3.0.0.6.102_56747 (nvram `productid` = `PRT-AX57_GO`), Linux 5.4.246 aarch64 |
| OpenWrt target | `mediatek/filogic`, device `asus_rt-ax57go` |

### Stock flash layout

`/proc/mtd` on stock firmware:

| MTD | Size (hex) | Size (bytes) | Name | Notes |
|---|---|---|---|---|
| mtd0 | 0x00400000 | 4194304 | `Bootloader` | Raw NAND. Never touched by this procedure. |
| mtd1 | 0x07c00000 | 130023424 | `UBI_DEV` | Raw NAND. Holds a single UBI device (`ubi0`). |
| mtd2 | 0x0001f000 | 126976 | `nvram` | gluebi (MTD view) of UBI volume `nvram` |
| mtd3 | 0x000f8000 | 1015808 | `Factory` | same name/size as UBI volume `Factory` |
| mtd4 | 0x000f8000 | 1015808 | `Factory2` | same name/size as UBI volume `Factory2` |
| mtd5 | 0x045fe000 | 73392128 | `linux` | same name/size as UBI volume `linux` |
| mtd6 | 0x042b5870 | 69949552 | `rootfs` | stock root filesystem |

Stock UBI volumes (`ubi0`):

| Volume | Name | Size (bytes) |
|---|---|---|
| ubi0_0 | `nvram` | 126976 |
| ubi0_1 | `Factory` | 1015808 |
| ubi0_2 | `Factory2` | 1015808 |
| ubi0_3 | `linux` | 73392128 |
| ubi0_4 | `jffs2` | 47362048 |

- `Factory` and `Factory2` are byte-identical. `Factory` starts with `81 79 00 00` (MT7981 EEPROM
  ID), followed by the label MAC at offset `0x4`. It also holds the Wi-Fi pre-calibration data.
  **This is the one partition you cannot recreate. Back it up.**
- **`Factory` is a UBI volume, not a raw MTD partition.** This matters for bug 3 below.

UBI volumes after the permanent OpenWrt install:

| Name | Size (bytes) |
|---|---|
| `nvram` | (unchanged) |
| `Factory` | (unchanged) |
| `Factory2` | (unchanged) |
| `linux` | 4825088 |
| `jffs2` | 253952 |
| `rootfs` | 5332992 |
| `rootfs_data` | 109834240 |
| `provisioning` | 253952 |

The overlay (`rootfs_data`, UBIFS) has about 90 MB free.

---

## The bugs and their fixes

Bugs 1-3 were found in commit `30865d9` of the fork. At the time of testing, the fork branch had
no newer commits. Apply the patches in order with `git am`:

| Patch | Fixes |
|---|---|
| [`0001-mediatek-filogic-rt-ax57go-fix-WAN-PHY-calibration-k.patch`](patches/0001-mediatek-filogic-rt-ax57go-fix-WAN-PHY-calibration-k.patch) | Bugs 1-3: WAN PHY calibration and the `gpio-keys` keycode (DTS), WAN MAC (`02_network`) |
| [`0002-mediatek-filogic-rt-ax57go-add-blue-status-LED.patch`](patches/0002-mediatek-filogic-rt-ax57go-add-blue-status-LED.patch) | Bug 4: blue channel of the status LED (DTS) |

Both are offered for upstreaming into the fork or into PR #15055.

### Bug 1: WAN PHY calibration fails (most important)

**Symptom** (`dmesg`):

```
MediaTek MT7981 PHY mdio-bus:00: invalid efuse data
MediaTek MT7981 PHY mdio-bus:00: probe with driver MediaTek MT7981 PHY failed with error -22
```

The WAN port then falls back to the "Generic PHY" driver and runs uncalibrated.

**Root cause:** `mt7981b.dtsi` already gives the SoC's internal GbE PHY (`mdio-bus` /
`ethernet-phy@0`) the correct calibration cell, `nvmem-cells = <&phy_calibration>`. That cell is
16 bytes from the efuse (`efuse@11f20000`, `phy-calib@8dc`). The board DTS overrode it with
`nvmem-cells = <&precal_factory_1010>`, which is the Wi-Fi pre-calibration blob in Factory
(0x6f010 bytes). The driver's `mt798x_phy_calibration()` requires `buf[0..3]` to be non-zero
and the cell to be at least 16 bytes. Given the wrong data, it returns `-EINVAL`.

**Fix** (`mt7981b-asus-rt-ax57go.dts`): delete the two `nvmem-cells` /
`nvmem-cell-names` lines from the board's PHY node so the SoC efuse cell applies again.

**After the fix:** `eth1: PHY [mdio-bus:00] driver [MediaTek MT7981 PHY]`, 1 Gbps/Full, DHCP lease
from the ISP, internet OK.

### Bug 2: `gpio-keys` fails, so the reset button is dead

**Symptom** (`dmesg`):

```
gpio-keys keys: Button node 'vpn_switch' without keycode
```

This is followed by a probe failure with error -22. The entire `gpio-keys` device fails, which
takes the RESET button down with it.

**Root cause:** the `vpn_switch` node (`linux,input-type = <EV_SW>`) had no `linux,code`.

**Fix** (DTS): add `linux,code = <BTN_0>;` to `vpn_switch`. After the fix, `gpio-keys`
binds. Pressing the physical buttons has **not** been tested yet.

### Bug 3: WAN MAC blank/random

**Symptom:** `uci show network` shows `network.@device[1].macaddr=':'`, and `eth1` gets a random
MAC on every boot.

**Root cause:** `target/linux/mediatek/filogic/base-files/etc/board.d/02_network` used
`mtd_get_mac_binary "Factory" 0x4`. On this device, `Factory` is a **UBI volume**, not an MTD
partition. Switching to `mtd_get_mac_binary_ubi` alone is not enough, because that helper looks for
the UBI MTD partition named by `CI_UBIPART`, which defaults to `ubi`. On this device it is
`UBI_DEV`.

**Fix** (`02_network`):

```sh
asus,rt-ax57go)
	label_mac=$(CI_UBIPART="UBI_DEV" mtd_get_mac_binary_ubi "Factory" 0x4)
	lan_mac=$label_mac
	wan_mac=$(macaddr_add "$lan_mac" 1)
	;;
```

**After the fix:** LAN = label MAC, WAN = label MAC + 1, and both persist across reboots.

### Bug 4: the status LED glows blue all the time

**Symptom:** while OpenWrt is running, the front LED shows **blue** instead of the green "running"
state, even though `green:power` is the only LED that is on.

**Root cause:** the front LED is an RGB LED. Stock firmware drives red/green/blue as PWM channels
0/1/2 (nvram `led_red_gpio` / `led_green_gpio` / `led_blue_gpio` = `0x10c8` / `0x10c9` / `0x10ca`;
pinctrl groups `pwm0_0` / `pwm1_0` / `pwm2`), i.e. **GPIO 13 / 14 / 7, all active-low**. The board
DTS only described red and green. GPIO 7 is left unclaimed, and in that state the blue channel
glows.

**Verified on hardware:** with all other LEDs off, driving GPIO 7 through sysfs showed `0` = blue on
and `1` = blue off. With green on and blue off, the LED shows green.

**Fix** (patch 0002): add a `status_blue` `gpio-led` on GPIO 7, `GPIO_ACTIVE_LOW`, `default-state =
"off"`. Not yet flashed on the test unit; the DTS compiles and the GPIO behaviour was confirmed by
hand.

Side note for PR #15055: a reviewer suggested that the reset button and the green status LED share
GPIO 1. The stock configuration says otherwise: reset is GPIO 1 (active-low), and green is PWM
channel 1, which is GPIO 14. The likely mix-up is "PWM1" vs "GPIO 1".

---

## Install guide (the sequence that worked)

You need:

- Images built with the patches. See [docs/BUILD.md](docs/BUILD.md). This repository does not
  distribute firmware binaries. For reference, the SHA-256 sums of the build that was tested are
  in [notes/build-sha256sums.txt](notes/build-sha256sums.txt), and its package list is in
  [notes/package-manifest.txt](notes/package-manifest.txt).
  - `openwrt-mediatek-filogic-asus_rt-ax57go-initramfs.trx`: for the stock web UI.
  - `openwrt-mediatek-filogic-asus_rt-ax57go-squashfs-sysupgrade.bin`: for the permanent install.
- A computer with Linux, WSL or macOS (for `ssh`, `scp` and the backup script), connected by
  Ethernet to a LAN port.
- An SSH key pair (ed25519 works with the stock dropbear).

In the commands below, `<your-router>` means the router's current LAN address: 192.168.50.1 on
stock ASUS firmware, 192.168.1.1 on OpenWrt.

### 1. Back up the stock flash

1. Optional but recommended: factory-reset the router and finish the ASUS setup wizard so you start
   from a known state.
2. In the stock web UI, enable SSH: **Administration → System → Enable SSH = LAN only**, port 22.
   Paste your **public** key into *Authorized Keys* and apply.
3. From Linux or WSL (not PowerShell, which can corrupt binary pipes), run:

   ```sh
   ROUTER_HOST=<your-router> ROUTER_USER=<your-admin-user> ROUTER_KEY=~/.ssh/<your-key> \
     ./scripts/backup-stock.sh
   ```

   The script dumps every MTD partition and UBI volume. It writes `MD5SUMS.router` (each image
   verified against the router-side md5) and `SHA256SUMS` into `backups/stock-<timestamp>/`.

**Why a RAM snapshot?** Some images change between two reads because they are live: the whole
UBI device (`mtd1`) and the mounted `jffs2` volume (`ubi0_4`). Streaming them twice gives
different md5s, so a direct stream cannot be verified. The script first copies each image into the
router's RAM (`cat /dev/mtd1ro > /tmp/snap.bin`), hashes it there, streams that frozen copy, and
compares the hashes. On the test unit, `/tmp` had about 238 MB free, so even the 124 MiB `UBI_DEV`
image fits. With this method, every image matched its router-side md5.

Keep the backup **private and offline**. `nvram` contains your admin and Wi-Fi credentials.
`Factory` contains your MAC addresses and calibration data.

### 2. Flash the OpenWrt initramfs from the stock web UI

1. Open **Administration → Firmware Upgrade**, choose **Manual firmware update → Upload**, and select
   `openwrt-mediatek-filogic-asus_rt-ax57go-initramfs.trx`.
2. Wait. The router came back as OpenWrt at **192.168.1.1** after about 60–70 s. Renew your PC's
   DHCP lease (or unplug and replug the cable).

What happens: the ASUS updater strips the TRX wrapper and writes the initramfs kernel into the UBI
volume `linux`. On the test unit, the start of `ubi0_3` matched `initramfs-kernel.bin`
byte-for-byte. Both the OpenWrt `.trx` and the stock `.trx` carry the image name `PRT-AX57_GO` in
their header. The OpenWrt one has a zeroed 64-byte trailer and was still accepted.

> **From this point on, stock firmware is gone.** The router boots the OpenWrt *initramfs* from
> flash on every power cycle. It is safe to stay here while you test. Nothing in the initramfs
> writes to flash unless you tell it to.

### 3. Test in the initramfs

```sh
ssh root@192.168.1.1
dmesg | grep -iE 'efuse|gpio-keys|mt7981 phy|error'   # should show no efuse/gpio-keys errors
ip link show eth1                                     # WAN MAC = label MAC + 1, stable across reboots
uci show network | grep macaddr                       # must not be ':'
iw dev; iw phy | grep -E 'Wiphy|MHz' | head           # two radios: 2.4 GHz and 5 GHz
```

Plug in the WAN cable and confirm that you get a 1 Gbps link and an address.

Tip: you can try another initramfs build without the web UI. Copy it to `/tmp`, run
`ubiupdatevol /dev/ubi0_3 /tmp/<new>-initramfs-kernel.bin`, then `reboot`.

### 4. Install permanently

```sh
scp -O openwrt-mediatek-filogic-asus_rt-ax57go-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
ssh root@192.168.1.1
sysupgrade -T /tmp/openwrt-mediatek-filogic-asus_rt-ax57go-squashfs-sysupgrade.bin   # test only
sysupgrade -n /tmp/openwrt-mediatek-filogic-asus_rt-ax57go-squashfs-sysupgrade.bin
```

- `scp -O` forces the legacy SCP protocol, because the initramfs has no SFTP server.
- When run from the initramfs, the board's `asus_initial_setup` removes the ASUS `rootfs`,
  `rootfs_data` and `jffs2` volumes and recreates a small `jffs2`. The standard NAND upgrade then
  writes `linux`, `rootfs` and `rootfs_data`. **`Factory`, `Factory2` and `nvram` are not
  touched.** On the test unit, Factory had the same md5 before and after.
- SSH was back after about 60 s.

### 5. Set the root password

```sh
ssh root@192.168.1.1
passwd
```

Or use LuCI at `https://192.168.1.1` (the build includes `luci-ssl`, so expect a self-signed
certificate warning).

### 6. Enable Wi-Fi

Wi-Fi is disabled by default. The tested setup used the same SSID on both bands with WPA2/WPA3
mixed mode (`sae-mixed`):

```sh
uci set wireless.radio0.country='<your-country-code>'
uci set wireless.radio1.country='<your-country-code>'
for r in 0 1; do
  uci set wireless.default_radio$r.ssid='<your-ssid>'
  uci set wireless.default_radio$r.encryption='sae-mixed'
  uci set wireless.default_radio$r.key='<your-wifi-passphrase>'
  uci set wireless.radio$r.disabled='0'
done
uci commit wireless
wifi reload
```

You can also do this in LuCI: **Network → Wireless**.

---

## Recovery notes

- **The bootloader was never touched.** Nothing in this procedure writes `mtd0`. The ASUS
  bootloader and its rescue mode, whatever it supports, are still in place.
- **`Factory`, `Factory2` and `nvram` survive the install** (md5-verified for Factory). Your step 1
  backup is still your only copy if something else goes wrong. Keep `ubi0_1_Factory.bin`
  especially safe.
- **ASUS rescue mode (Firmware Restoration utility / TFTP on 192.168.1.x) has not been tested on
  this model.** Do not rely on it until someone confirms it works.
- **Going back to stock has not been tested.** If you try it, please open an issue with what you
  did and what happened.
- While you are still on the initramfs (after step 2, before step 4), you can test new initramfs
  images with `ubiupdatevol` (see step 3). Rebooting does not lose OpenWrt, because the initramfs
  is in flash.

---

## Test results (after permanent install)

Tested on one unit on 2026-11-15. Build: OpenWrt SNAPSHOT r36793, Linux 6.18.54, fork commit
`30865d9` plus the two patches, with `luci` and `luci-ssl`.

- **WAN:** `eth1: PHY [mdio-bus:00] driver [MediaTek MT7981 PHY]`, 1 Gbps/Full, DHCP from the ISP,
  internet OK.
- **LAN:** OK. Tested at 100 Mbps because of the test PC's adapter. The EN8801SC link itself works.
- **Wi-Fi:** both radios detected: phy0 (2.4 GHz, 2412–2484 MHz) and phy1 (5 GHz, 5180–5885 MHz).
  Factory EEPROM and pre-calibration data were loaded. AP running on both bands (same SSID,
  `sae-mixed`). A Windows client on 5 GHz showed a signal of -33 dBm and a link rate of
  1200.9 Mbit/s (HE-MCS 11, 2 spatial streams, 80 MHz) in both directions. A 25 MB download over
  Wi-Fi ran at about 41 Mbit/s, limited by the ISP connection, not the router.
- **MACs:** LAN = label MAC. WAN = label MAC + 1. phy0 = label MAC. phy1 = label MAC with the
  locally-administered bit set in the first octet.
- **LEDs present:** `green:power`, `red:status`, `white:status`, `mt76-phy0`, `mt76-phy1`.
- **USB:** `xhci-mtk` probes and the USB 3.2 root hubs register. Not tested with a device.
- **Persistence:** config, Wi-Fi, root password and MACs all survive a reboot.
- **dmesg:** clean after the fixes, apart from a harmless `rdinit` message.
- **Timings:** web-UI flash to OpenWrt about 60–70 s. Sysupgrade to SSH about 60 s.

---

## Open items

- [ ] Physical reset button press and VPN switch events (`gpio-keys` now binds, but untested).
- [ ] USB storage.
- [ ] ASUS rescue mode (Firmware Restoration / TFTP) on this model.
- [ ] Going back to stock firmware from OpenWrt.
- [ ] Serial console pinout (the unit was not opened).
- [ ] LAN throughput at 1 Gbps (needs a gigabit test client).
- [ ] Web-UI `.trx` install on newer stock firmware (for example 3.0.0.6.102_57206). Only
      3.0.0.6.102_56747 is confirmed.
- [ ] Send the fixes to the fork and to [openwrt/openwrt#15055](https://github.com/openwrt/openwrt/pull/15055).

Reports from other units or other stock firmware versions are welcome. Please open an issue.

---

## Repository layout

```
README.md                 this file
docs/BUILD.md             how to rebuild the images with the patches
patches/                  fixes on top of jonathan-sturges/openwrt@30865d9 (git am)
scripts/backup-stock.sh   verified full flash backup from stock firmware over SSH
notes/                    raw findings, build checksums, package manifest
```

## Credits

- **Jonathan Sturges** for the [`asus_rt-ax57go` branch](https://github.com/jonathan-sturges/openwrt/tree/asus_rt-ax57go)
  that carries RT-AX57 Go support forward.
- **The authors and reviewers of [openwrt/openwrt#15055](https://github.com/openwrt/openwrt/pull/15055)**,
  the original RT-AX57 Go support pull request.
- **The [OpenWrt project](https://openwrt.org/)** and its contributors, including the MediaTek
  Filogic, mt76 and ASUS-platform maintainers.

## License

- Patches and scripts (`patches/`, `scripts/`): **GPL-2.0-only**, same as OpenWrt. See
  [LICENSE](LICENSE).
- Documentation (`README.md`, `docs/`, `notes/`): **[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)**.

ASUS, ASUSWRT and RT-AX57 Go are trademarks of ASUSTeK Computer Inc. This project is not
affiliated with ASUS or the OpenWrt project. Stock firmware is available from ASUS support and is
not redistributed here.
