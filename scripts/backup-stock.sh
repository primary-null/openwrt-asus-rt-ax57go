#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# backup-stock.sh - back up every MTD partition and UBI volume of a router
# running stock (ASUSWRT-style) firmware, over SSH.
#
# Method ("RAM snapshot"): each partition/volume is first copied into the
# router's /tmp (RAM), hashed there, then streamed to this machine and hashed
# again. Live partitions (for example the whole UBI device or a mounted jffs2
# volume) change between two reads, so hashing a direct stream is not a
# reliable check; hashing a frozen RAM copy is.
#
# Safety:
#   * Read-only on the router, except for one temporary file in /tmp that is
#     deleted after every image and on exit.
#   * Never writes to flash, never runs nvram set/commit, mtd, ubi* tools, etc.
#   * Images that do not fit in the router's free /tmp space are skipped with
#     an error instead of filling RAM.
#
# Requirements (local): bash, ssh (OpenSSH client), md5sum, sha256sum, awk.
# Run it from Linux, WSL or macOS (with coreutils). Do not pipe binary data
# through Windows PowerShell; it can corrupt it.
#
# Configuration via environment variables:
#   ROUTER_HOST   router address               (default: 192.168.50.1)
#   ROUTER_USER   SSH user                     (default: admin)
#   ROUTER_PORT   SSH port                     (default: 22)
#   ROUTER_KEY    private key file             (default: none; ssh defaults)
#   SSH_OPTS      extra ssh options, one string (default: empty)
#   OUT_DIR       local output directory       (default: backups/stock-<UTC timestamp>)
#   TMP_MARGIN_KB keep at least this much /tmp free on the router (default: 16384)
#   RETRIES       transfer attempts per image  (default: 3)
#   SKIP_REGEX    extended regex; matching image names are skipped (default: none)
#
# Example:
#   ROUTER_HOST=192.168.50.1 ROUTER_USER=admin ROUTER_KEY=~/.ssh/id_ed25519 \
#     ./scripts/backup-stock.sh
#
# WARNING: the output contains device secrets (nvram holds your admin and
# Wi-Fi passwords; Factory holds MAC addresses and calibration data).
# Keep it private. Never commit it to a public repository.

set -euo pipefail

ROUTER_HOST="${ROUTER_HOST:-192.168.50.1}"
ROUTER_USER="${ROUTER_USER:-admin}"
ROUTER_PORT="${ROUTER_PORT:-22}"
ROUTER_KEY="${ROUTER_KEY:-}"
SSH_OPTS="${SSH_OPTS:-}"
OUT_DIR="${OUT_DIR:-backups/stock-$(date -u +%Y%m%dT%H%M%SZ)}"
TMP_MARGIN_KB="${TMP_MARGIN_KB:-16384}"
RETRIES="${RETRIES:-3}"
SKIP_REGEX="${SKIP_REGEX:-}"

REMOTE_SNAP="/tmp/backup-stock.snap"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

for tool in ssh md5sum sha256sum awk; do
	command -v "$tool" >/dev/null 2>&1 || die "missing local tool: $tool"
done

SSH=(ssh -n -T -p "$ROUTER_PORT" -o ConnectTimeout=10 -o ServerAliveInterval=15)
if [ -n "$ROUTER_KEY" ]; then
	[ -r "$ROUTER_KEY" ] || die "cannot read key file: $ROUTER_KEY"
	SSH+=(-i "$ROUTER_KEY" -o IdentitiesOnly=yes -o BatchMode=yes)
fi
if [ -n "$SSH_OPTS" ]; then
	# shellcheck disable=SC2206  # intentional word splitting of user options
	SSH+=($SSH_OPTS)
fi
SSH+=("${ROUTER_USER}@${ROUTER_HOST}")

# Run a command on the router (busybox ash; keep it POSIX).
rsh() { "${SSH[@]}" "$@"; }

cleanup() {
	rsh "rm -f '$REMOTE_SNAP'" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

mkdir -p "$OUT_DIR/info"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
log "Output directory: $OUT_DIR"

log "Connecting to ${ROUTER_USER}@${ROUTER_HOST}:${ROUTER_PORT} ..."
rsh 'true' || die "SSH connection failed"

for t in cat md5sum df wc rm; do
	rsh "command -v $t >/dev/null 2>&1 || which $t >/dev/null 2>&1" \
		|| die "router lacks required tool: $t"
done

# --- Informational metadata (read-only) -----------------------------------
rsh 'cat /proc/mtd' > "$OUT_DIR/info/proc_mtd.txt"
rsh 'uname -a; cat /proc/version 2>/dev/null' > "$OUT_DIR/info/kernel.txt" || true
rsh 'for k in productid firmver buildno extendno; do printf "%s=" "$k"; nvram get "$k" 2>/dev/null || echo; done' \
	> "$OUT_DIR/info/firmware.txt" 2>/dev/null || true
rsh 'for d in /sys/class/ubi/ubi*_*; do
	[ -d "$d" ] || continue
	printf "%s data_bytes=%s name=%s\n" "${d##*/}" "$(cat "$d/data_bytes")" "$(cat "$d/name")"
done' > "$OUT_DIR/info/ubi_volumes.txt" || true
rsh 'df -k /tmp; echo; cat /proc/meminfo' > "$OUT_DIR/info/memory.txt" || true

if rsh '[ -e /etc/openwrt_release ]'; then
	log "WARNING: router appears to run OpenWrt, not stock firmware. Continuing anyway."
fi

# --- Build the image list: "<device> <expected_bytes> <name>" -------------
LIST=()
while read -r dev size _ name; do
	[ -n "$dev" ] || continue
	case "$dev" in mtd*:) ;; *) continue ;; esac
	dev="${dev%:}"
	name="${name#\"}"; name="${name%\"}"
	LIST+=("/dev/${dev} $((16#$size)) ${dev}_$(sanitize "$name")")
done < "$OUT_DIR/info/proc_mtd.txt"

if [ -s "$OUT_DIR/info/ubi_volumes.txt" ]; then
	while read -r vol bytes name; do
		bytes="${bytes#data_bytes=}"
		name="${name#name=}"
		LIST+=("/dev/${vol} ${bytes} ${vol}_$(sanitize "$name")")
	done < "$OUT_DIR/info/ubi_volumes.txt"
fi

[ "${#LIST[@]}" -gt 0 ] || die "no MTD partitions or UBI volumes found"
log "Found ${#LIST[@]} images to back up."

# --- Dump loop ---------------------------------------------------------------
FAILED=()
: > "$OUT_DIR/MD5SUMS.router"

for entry in "${LIST[@]}"; do
	read -r dev expected base <<<"$entry"
	if [ -n "$SKIP_REGEX" ] && [[ "$base" =~ $SKIP_REGEX ]]; then
		log "Skipping $base (SKIP_REGEX)"
		continue
	fi

	# Prefer the read-only MTD node when it exists.
	src="$dev"
	case "$dev" in
	/dev/mtd*) rsh "[ -e '${dev}ro' ]" && src="${dev}ro" ;;
	esac
	rsh "[ -e '$src' ]" || { log "ERROR: $src not present on router"; FAILED+=("$base"); continue; }

	free_kb="$(rsh "df -k /tmp | awk 'NR>1 {v=\$(NF-2)} END {print v}'" || true)"
	need_kb=$(( expected / 1024 + 1 + TMP_MARGIN_KB ))
	if ! [[ "$free_kb" =~ ^[0-9]+$ ]] || [ "$free_kb" -lt "$need_kb" ]; then
		log "ERROR: $base needs ${need_kb} KiB in router /tmp, only '${free_kb}' KiB free; skipped"
		FAILED+=("$base")
		continue
	fi

	out="$OUT_DIR/${base}.bin"
	ok=0
	for attempt in $(seq 1 "$RETRIES"); do
		log "$base: snapshot $src -> router RAM (attempt $attempt/$RETRIES)"
		rsh "rm -f '$REMOTE_SNAP' && cat '$src' > '$REMOTE_SNAP'" \
			|| { log "$base: snapshot failed"; continue; }

		remote_size="$(rsh "wc -c < '$REMOTE_SNAP'" | tr -d ' \r' || true)"
		remote_md5="$(rsh "md5sum '$REMOTE_SNAP'" | awk '{print $1}' || true)"
		if ! [[ "$remote_md5" =~ ^[0-9a-f]{32}$ ]]; then
			log "$base: could not hash snapshot on router"
			continue
		fi
		if [ "$remote_size" != "$expected" ]; then
			log "$base: NOTE size ${remote_size} differs from expected ${expected}"
		fi

		log "$base: transferring ${remote_size} bytes"
		rsh "cat '$REMOTE_SNAP'" > "$out.part" || { log "$base: transfer failed"; continue; }

		local_md5="$(md5sum "$out.part" | awk '{print $1}')"
		if [ "$local_md5" = "$remote_md5" ]; then
			mv -f "$out.part" "$out"
			printf '%s  %s\n' "$remote_md5" "${base}.bin" >> "$OUT_DIR/MD5SUMS.router"
			log "$base: OK md5 $local_md5"
			ok=1
			break
		fi
		log "$base: md5 mismatch (router $remote_md5, local $local_md5); retrying"
	done
	rsh "rm -f '$REMOTE_SNAP'" || true
	rm -f "$out.part"
	[ "$ok" -eq 1 ] || FAILED+=("$base")
done

# --- Checksums -------------------------------------------------------------
(
	cd "$OUT_DIR"
	shopt -s nullglob
	files=(*.bin)
	if [ "${#files[@]}" -gt 0 ]; then
		sha256sum "${files[@]}" > SHA256SUMS
	fi
)

log "Done. Images and SHA256SUMS are in $OUT_DIR"
if [ "${#FAILED[@]}" -gt 0 ]; then
	log "FAILED images: ${FAILED[*]}"
	exit 2
fi
log "All images verified (router-side md5 == local md5)."
