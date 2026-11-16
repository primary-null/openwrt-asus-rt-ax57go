# Building OpenWrt for the ASUS RT-AX57 Go (with the fixes)

These steps rebuild the images that were tested in the [README](../README.md): the fork
[jonathan-sturges/openwrt](https://github.com/jonathan-sturges/openwrt), branch `asus_rt-ax57go`,
commit `30865d9`, plus the two patches in [`../patches/`](../patches/).

The tested build was done in **WSL2 Ubuntu** on Windows. Any normal x86_64 Linux machine works the
same way; skip the WSL-specific parts.

Result of the tested build: OpenWrt SNAPSHOT r36793, Linux 6.18.54, target `mediatek/filogic`,
device `asus_rt-ax57go`, plus `luci` and `luci-ssl`. For comparison, its checksums are in
[`../notes/build-sha256sums.txt`](../notes/build-sha256sums.txt) and its package list is in
[`../notes/package-manifest.txt`](../notes/package-manifest.txt). Your hashes will differ, because
OpenWrt snapshot builds are not bit-for-bit reproducible across machines and feed revisions.

## 1. Prepare the build environment (WSL2 Ubuntu)

Work inside the Linux filesystem (for example `~/src`). **Do not build under `/mnt/c/...`**: the
Windows filesystem is case-insensitive and slow, and the OpenWrt build breaks there.

Install the build dependencies (the package list follows the OpenWrt build-system documentation for
Debian/Ubuntu):

```sh
sudo apt update
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3-setuptools python3-dev rsync swig \
  unzip zlib1g-dev file wget
```

**Use a clean PATH.** WSL appends the Windows PATH, which contains spaces and parentheses (for
example `Program Files (x86)`), and the OpenWrt build system rejects that. Set this in every shell
you build from:

```sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

(To make it permanent, you can set `appendWindowsPath = false` under `[interop]` in
`/etc/wsl.conf` and then run `wsl --shutdown`.)

## 2. Get the source and apply the patches

```sh
mkdir -p ~/src && cd ~/src

# This repository (for the patches)
git clone https://github.com/<you>/openwrt-asus-rt-ax57go.git

# The fork, at the tested commit
git clone -b asus_rt-ax57go https://github.com/jonathan-sturges/openwrt.git openwrt
cd openwrt
git switch -c rt-ax57go-fixes 30865d9

# git am needs a committer identity (local to this clone is fine)
git config user.name  "<your name>"
git config user.email "<your email>"

git am ../openwrt-asus-rt-ax57go/patches/*.patch
```

Check that the patches applied:

```sh
grep -n 'CI_UBIPART="UBI_DEV"' target/linux/mediatek/filogic/base-files/etc/board.d/02_network
grep -n 'BTN_0' target/linux/mediatek/dts/mt7981b-asus-rt-ax57go.dts
grep -n 'precal_factory_1010' target/linux/mediatek/dts/mt7981b-asus-rt-ax57go.dts
# the first two must match; the third must NOT show a line inside the ethernet-phy@0 node
```

If the fork branch has moved on since `30865d9`, you can try `git am` on top of the newer branch
head instead. Check first whether the fixes are already included upstream.

## 3. Feeds

```sh
./scripts/feeds update -a
./scripts/feeds install -a
```

## 4. Configuration

Create a minimal `.config` and expand it:

```sh
cat > .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_asus_rt-ax57go=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
EOF
make defconfig
```

Confirm that the device is selected:

```sh
grep 'CONFIG_TARGET_mediatek_filogic_DEVICE_asus_rt-ax57go=y' .config
```

The device's default packages already include `kmod-mt7915e`, the MT7981 Wi-Fi firmware,
`wpad-basic-mbedtls` and `kmod-usb3`. Add more packages with `make menuconfig` if you want them.

## 5. Build

```sh
make download -j8
make -j"$(nproc)"
# if it fails, rerun single-threaded with verbose output to see the real error:
# make -j1 V=s
```

A first build takes a long time, because it builds the toolchain.

## 6. Output

The images are in `bin/targets/mediatek/filogic/`:

| File | Use |
|---|---|
| `openwrt-mediatek-filogic-asus_rt-ax57go-initramfs.trx` | Upload in the **stock ASUS web UI** (install step 2). |
| `openwrt-mediatek-filogic-asus_rt-ax57go-initramfs-kernel.bin` | Same initramfs without the TRX wrapper. Can be written with `ubiupdatevol /dev/ubi0_3` from a running OpenWrt initramfs. |
| `openwrt-mediatek-filogic-asus_rt-ax57go-squashfs-sysupgrade.bin` | `sysupgrade -n` from OpenWrt (install step 4). |
| `sha256sums` | Checksums. Verify them after copying the images to another machine. |

To copy the images to Windows, for example:

```sh
mkdir -p /mnt/c/Users/<you>/Downloads/rt-ax57go
cp bin/targets/mediatek/filogic/*asus_rt-ax57go* bin/targets/mediatek/filogic/sha256sums \
   /mnt/c/Users/<you>/Downloads/rt-ax57go/
```

Then continue with the [install guide](../README.md#install-guide-the-sequence-that-worked).
