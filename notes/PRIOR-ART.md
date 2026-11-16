# Prior art check: OpenWrt on ASUS RT-AX57 Go (checked 2026-11-15/16)

Scope: compared our findings in `FINDINGS-RAW.md` against the GitHub REST API (openwrt/openwrt,
the jonathan-sturges fork, issue/PR search) and the OpenWrt forum (topic JSON; forum search was
rate-limited (HTTP 429), so topics were found through the forum sitemap files instead). General web search was unavailable
(HTTP 402; Bing and Mojeek returned nothing useful). SNBForums, Reddit and Chinese forums were **not** checked.
"Not found" below means not found in these sources, not proof that nobody has reported it.

## Verdict

| # | Finding | Verdict | Evidence |
|---|---------|---------|----------|
| 1 | Install via the stock ASUS web UI (upload `initramfs.trx` on 3.0.0.6.102_56747) works | **Partially known.** We found no public report of anyone actually doing it on the RT-AX57 Go, on any firmware version. But it was predicted for this model, and it is the documented method for sibling ASUS filogic routers. | Predicted, not tested: forum post #19 (2026-10-09) https://forum.openwrt.org/t/add-support-for-asus-rt-ax57-go/251789 ; fork builds an `initramfs.trx` artifact, but its commit message documents only TFTP+serial: https://github.com/jonathan-sturges/openwrt/commit/30865d9eea7314c717a841f060e686bc2ab4c2ff ; the "Vendor-UI Method" is upstream for RT-AX52 https://github.com/openwrt/openwrt/commit/50d9ca6e5a04724e4263a348bdbe5ff4b1c43998 and RT-AX57M https://github.com/openwrt/openwrt/commit/114b5c2063576d0ce1944d3308280f2ecd72e969 |
| 1b | ASUS strips the trx and writes the payload into UBI volume `linux`, so OpenWrt initramfs then boots from flash | **Partially known** (this is how the existing ASUS filogic install flow works, and `asus_initial_setup` exists for it). We found no measurement like ours (md5 of `ubi0_3`) for this model. | Same RT-AX52 / RT-AX57M commits as above |
| 2a | WAN PHY "invalid efuse data": board `phy0` points `phy-cal-data` at Factory precal instead of the SoC efuse | **Partially known.** The *correct* wiring was already public: PR #15055 (2024) uses `<&phy_calibration>`, and a reviewer said the PHY "has already been defined in mt7981b.dtsi". The *bug* is a regression in the fork commit 30865d9 (`<&precal_factory_1010>`). We found no public report of that regression, its dmesg symptom or a fix. | PR #15055 DTS (head 341aa3e): https://github.com/openwrt/openwrt/pull/15055/files ; review comment https://github.com/openwrt/openwrt/pull/15055#discussion_r2304074155 ; fork DTS: https://github.com/jonathan-sturges/openwrt/commit/30865d9eea7314c717a841f060e686bc2ab4c2ff ; forum thread doesn't mention it: https://forum.openwrt.org/t/add-support-for-asus-rt-ax57-go/251789 |
| 2b | `vpn_switch` (EV_SW) has no `linux,code`, so gpio-keys fails to probe and the reset button stops working | **New as a report for this device**, but the fix is a standard pattern. The `vpn_switch` node exists only in the fork (PR #15055 has reset only). We found no report of the failure. EV_SW slide switches with `linux,code = <BTN_0>` are already used upstream (for example GL-MT3000). | Fork DTS: https://github.com/jonathan-sturges/openwrt/commit/30865d9eea7314c717a841f060e686bc2ab4c2ff ; upstream pattern: https://github.com/openwrt/openwrt/blob/main/target/linux/mediatek/dts/mt7981b-glinet-gl-mt3000.dts (lines 33-34) ; related but different GPIO issue raised in review: https://github.com/openwrt/openwrt/pull/15055#discussion_r2403487522 |
| 2c | WAN MAC blank: `02_network` uses `mtd_get_mac_binary` on a UBI volume; fix is `CI_UBIPART="UBI_DEV" mtd_get_mac_binary_ubi "Factory" 0x4` | **Already known (fix); new (regression report).** PR #15055 already used exactly `CI_UBIPART="UBI_DEV"` + `mtd_get_mac_binary_ubi "Factory" 0x4` for this device, and upstream uses the same idiom for RT-AX52/RT-AX57M/RT-AX59U/TUF. The fork switched to plain `mtd_get_mac_binary`, and nobody has publicly reported that this breaks it. A reviewer also suggested assigning MACs in the DT, which may be the better upstream fix. | PR #15055 `02_network`: https://github.com/openwrt/openwrt/pull/15055/files ; upstream idiom: https://github.com/openwrt/openwrt/blob/main/target/linux/mediatek/filogic/base-files/etc/hotplug.d/ieee80211/11_fix_wifi_mac (lines 41-64) ; review: https://github.com/openwrt/openwrt/pull/15055#discussion_r2304078661 ; fork: https://github.com/jonathan-sturges/openwrt/commit/30865d9eea7314c717a841f060e686bc2ab4c2ff |
| 3 | Upstream status | **Known (status only):** PR #15055 is still open, not merged, and changes were requested in 2025-04. The device is **not** in official OpenWrt `main`. We found no other PR for rt-ax57go in openwrt/openwrt. | https://api.github.com/repos/openwrt/openwrt/pulls/15055 ; https://github.com/openwrt/openwrt/pull/15055 ; GitHub issue search `rt-ax57go` returns only #15055: https://api.github.com/search/issues?q=rt-ax57go ; no `asus-rt-ax57go` DTS on main (only `rt-ax57m`): https://github.com/openwrt/openwrt/tree/main/target/linux/mediatek/dts |
| 4 | Forum status | **Known.** Thread exists (21 posts, last 2026-10-13). Nobody there reports a web-UI install or any of our three bugs. | https://forum.openwrt.org/t/add-support-for-asus-rt-ax57-go/251789 |
| 5 | Serial pinout / ASUS rescue mode on this model | **Serial: partially known. Rescue mode: could not verify.** PR #15055 says "UART 3V3 115200 8N1 (Pinout silkscreened / Do not connect VCC)" and documents U-Boot menu key `4` plus TFTP to 192.168.1.70. We found no photo or pin order. We found no model-specific report of rescue mode; only ASUS's generic FAQ. | https://github.com/openwrt/openwrt/pull/15055 ; https://www.asus.com/support/faq/1000814/ |
| - | Live-MTD dump gotcha (`mtd1`/jffs2 md5 changes between reads; snapshot to tmpfs first) | **Not assessed**. This is generic Linux/UBI behaviour, so it is very unlikely to be novel. | No search done |
| - | Wi-Fi, USB and LED results; Factory left untouched by sysupgrade | **Mostly new as test reports for this fork commit.** The forum has only an anecdotal "performance at range is not very good" (post #20). | https://forum.openwrt.org/t/add-support-for-asus-rt-ax57-go/251789 |

## Notes

### Upstream PR #15055 (liushiyou006)
- Opened 2024-04-03. It has one commit (341aa3e, force-pushed 2024-04-16) and still targets kernel 6.1 `pending-6.1` patches. It is
  **open, not merged**. API `updated_at` 2026-01-30. https://api.github.com/repos/openwrt/openwrt/pulls/15055
- Review history (https://github.com/openwrt/openwrt/pull/15055):
  - 2024-10: musashino205 asked for a rebase onto 6.6 and a split into 3 commits.
  - 2025-04-21: abajk requested changes ("Both patches are already in the tree. This PR should be rebased").
  - 2025-08-27: DragonBluep left a detailed DTS review: drop pwm/pinctrl, "this phy has already been defined in mt7981b.dtsi", do MAC and EEPROM in the DT, add mt7915e.
  - 2025-10-03: raenye said the reset button and green status LED share GPIO 1.
  - 2026-10-03: jonathan-sturges referenced the PR from his fork commit.
- Its DTS already had `phy0 ... nvmem-cells = <&phy_calibration>; nvmem-cell-names = "phy-cal-data";` (efuse),
  and its `02_network` already used `CI_UBIPART="UBI_DEV"` + `mtd_get_mac_binary_ubi "Factory" 0x4`.
  So our fixes 2a and 2c mostly **restore what PR #15055 already had**. They are not new techniques.

### jonathan-sturges fork
- Branch `asus_rt-ax57go`: HEAD is still 30865d9 (2026-10-03). Its commit message says it "supplants" #15055 and documents
  only TFTP/serial install. https://api.github.com/repos/jonathan-sturges/openwrt/commits?sha=asus_rt-ax57go
- There is also a branch `25.12-asus-rt-ax57go` (b381250, 2026-10-03, "Asus RT-AX57 Go for 25.12"). It has the **same** DTS and
  `02_network` content, so it should have the same three bugs (inferred from the diff; not built or tested).
  https://api.github.com/repos/jonathan-sturges/openwrt/commits?sha=25.12-asus-rt-ax57go
- We found no PR from jonathan-sturges to openwrt/openwrt for this device.
  https://api.github.com/search/issues?q=repo:openwrt/openwrt+author:jonathan-sturges

### Forum
- Main thread "Add support for Asus RT-AX57 Go", started 2026-07-10 by jonathans (= jonathan-sturges), 21 posts, last post 2026-10-13:
  https://forum.openwrt.org/t/add-support-for-asus-rt-ax57-go/251789
  - Posts 1-16: the EN8801SC LAN PHY linked up but passed no frames. It was fixed with `managed = "in-band-status"` (post #16, 2026-09-30).
  - Post #18 (2026-10-09): the author says he is at the "it works for me" phase, is polishing the install flow, and wants testers.
  - Post #19 (starcraft66, 2026-10-09): says, based on analysis of stock firmware, that installing the initramfs from the stock web UI
    "should" work as on sibling ASUS routers. His unit had not arrived yet. **No follow-up confirms it.**
  - Post #20: anecdotal weak Wi-Fi range. No mention of WAN calibration, reset/gpio-keys or WAN MAC problems.
- Other "AX57" topics are about different hardware (RT-AX57 = Broadcom, RT-AX57M):
  https://forum.openwrt.org/t/adding-openwrt-support-for-asus-rt-ax57/210496 ,
  https://forum.openwrt.org/t/openwrt-support-for-asus-rt-ax57m-ax1800s-v2/208534 ,
  https://forum.openwrt.org/t/support-for-asus-rt-ax1800hp-v2-rt-ax57/233635
- Topics were found by grepping the forum sitemaps (https://forum.openwrt.org/sitemap.xml), which list topic titles and slugs.
  Posts that mention the RT-AX57 Go inside threads with other titles would not have been found.

### Honest novelty summary
- Probably new: a **confirmed** stock-web-UI install on this model (firmware 3.0.0.6.102_56747). Also new: public diagnosis of the three
  regressions in fork commit 30865d9, plus test results for that build.
- Not new: the techniques used to fix them (efuse `phy_calibration` cell, `CI_UBIPART="UBI_DEV"` + `mtd_get_mac_binary_ubi`,
  `linux,code = <BTN_0>` on an EV_SW key), the web-UI install method for ASUS filogic routers, and the UART parameters.
- Could not verify: any model-specific rescue-mode report, a serial pin order or photo, and any SNBForums/Reddit/Chinese-forum reports.
