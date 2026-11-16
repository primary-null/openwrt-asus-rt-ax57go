# Test results: firmware with all fixes

One retail unit (H/W A1, 2024), tested 2026-11-15/16.

**Build:** OpenWrt SNAPSHOT r36793 (Linux 6.18.54), `jonathan-sturges/openwrt@30865d9` plus both patches in [`../patches/`](../patches/), with `luci` and `luci-ssl`.

**Install:** installed with plain `sysupgrade` (settings kept) over the earlier 3-fix build. Every setting, the password and the SSH key were identical afterwards (compared against a snapshot taken before testing).

A visual summary is in [dashboard.html](dashboard.html). Download it and open it in a browser.

## Summary

| Area | Result |
|---|---|
| Stability | 60-minute soak: 0 kernel warnings or errors, 0 interface errors, no unexpected reboots, temperature 50.4–51.4 °C, load ~0.04 |
| Reboots | 3 consecutive reboots: SSH back in 34–35 s, Wi-Fi and internet ready in 38–39 s. Settings, password, SSH key and Factory checksum were identical after each one. |
| Settings-preserving upgrade | Worked. `sysupgrade` kept wireless, network, firewall, the root password, `authorized_keys`, the SSH host keys and the HTTPS certificate. |
| Blue LED (patch 0002) | Working. `blue:status` is registered and off by default, and the front LED now shows green while running instead of blue. |
| Reset button (short press) | A short press rebooted the router, and settings were preserved. This was confirmed by timing, not captured live: a reboot happened at the time of the press, and nothing else sent a reboot. |
| VPN slider | `gpio-keys` binds and IRQ 15 is registered. A physical flip has not been confirmed yet. |
| NAND | 0 bad blocks, highest erase count 53, no ECC or bitflip messages |
| Firewall (WAN) | Inbound accepts only ICMP, DHCP renew, IGMP and IPv6 housekeeping. 22, 80 and 443 are closed from WAN (rules checked, not tested from outside). |

## Wi-Fi throughput (one client at a time)

The client was a Windows laptop (MediaTek MT7922) about 1 m from the router. Downloads were HTTP from the router itself.

| Mode | PHY link | Download (best run) | Upload | Ping avg / max |
|---|---|---|---|---|
| 5 GHz, 160 MHz (ch 36–64, 60 s CAC) | 2402 Mbit/s | **844 Mbit/s** | 189 Mbit/s (CPU-bound) | 5.9 / 109 ms |
| 5 GHz, 80 MHz (default) | 1201 Mbit/s | **718 Mbit/s** | 177 Mbit/s (CPU-bound) | 4.0 / 17 ms |
| 5 GHz DFS ch 100, 80 MHz | 1201 Mbit/s | 619 Mbit/s | 184 Mbit/s (CPU-bound) | 3.6 / 8 ms |
| 2.4 GHz, 20 MHz, 27 dBm | 17–52 Mbit/s (MCS 0–4) | 33 Mbit/s | 140 Mbit/s | 5.4 / 83 ms |
| 2.4 GHz, 20 MHz, 15 dBm | 103–172 Mbit/s (MCS 4–7) | 63 Mbit/s | – | – |

- Upload and HTTPS are limited by the router's CPU (87–97 % on both cores while serving the test), not by the radio.
- 5 GHz over 10 minutes: 600 pings, 0 % loss, average 4.26 ms, no mt76 or hostapd errors.
- WPA3-only, WPA2-only and the default WPA2/WPA3 mixed mode all work. Each client connects only with the matching profile.

### The 2.4 GHz finding

At 27 dBm with the client about 1 m away (−21 dBm), the router's transmissions to the client stayed at MCS 0–4 with thousands of failed transmissions. Download was 19–33 Mbit/s, while upload from the same client reached MCS 11. Lowering power with `uci set wireless.radio0.txpower=15` roughly doubled download.

This looks like receiver overload at very close range rather than a range problem. It has **not** been tested from another room yet.

Side notes:

- `iw ... set txpower fixed` is accepted but ignored on this driver. Only the UCI `txpower` option takes effect.
- At country US, 5 GHz runs at 23 dBm (24 dBm on DFS channels). The per-rate power table is flat and below the regulatory limit, which may relate to an anecdotal "weak range" report on the forum. This was recorded only; nothing was changed.

## Real phones

| Client | Band, security | PHY link | Download (64 MB over HTTP) | Ping |
|---|---|---|---|---|
| Pixel 8 Pro | 5 GHz, WPA3-SAE | 1201 Mbit/s | **555–642 Mbit/s** | 4.4 ms avg, 0 % loss |
| Galaxy Z Fold 3 | 5 GHz, WPA2-PSK | 1081–1201 Mbit/s | 382–589 Mbit/s | about 20 ms idle average (phone power saving), 0 % loss |
| Fold 3 + laptop at the same time | 5 GHz + 2.4 GHz | – | **553–569 Mbit/s combined** (Fold 523–535, laptop 29–35) | laptop 5 ms avg under load |

WPA3 and WPA2 clients run side by side, and both bands carry full traffic at the same time without slowing each other down. Latency stays low under load.

## Hardware comparison with the stock firmware

The stock device tree and GPIO map were extracted offline from this unit's own flash backup and compared with the OpenWrt DTS:

- Reset is GPIO 1, active-low.
- The VPN switch is GPIO 0, active-high.
- White, red and green are GPIO 4, 13 and 14, all active-low.
- Blue is GPIO 7, active-low. It was missing from OpenWrt and is added by patch 0002.
- The EN8801SC is at MDIO address 24, with reset on GPIO 39.
- WAN PHY calibration comes from the efuse, the same as OpenWrt after patch 0001.
- The Wi-Fi EEPROM offsets match.

Stock has no fan, WPS button, USB power GPIO or extra LEDs.

The PR #15055 review concern that reset and the green LED share GPIO 1 is not supported by the stock data: green is PWM channel 1, which is GPIO 14.

## Still open

- 2.4 GHz performance from another room (range rather than close-range overload).
- Physical VPN slider flip, captured live.
- USB storage.
- ASUS rescue mode and going back to stock.
- LAN throughput at 1 Gbit/s. The test PC's wired adapter is limited to 100 Mbit/s.
- IPv6 prefix delegation. The test ISP connection didn't provide a prefix, so this is untested rather than broken.
