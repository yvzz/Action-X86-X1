#!/bin/bash
# DIY Part 1: X1 Pro device setup
# 使用 sed/awk 直接注入设备支持，不依赖 patch 的精确行号匹配
# 设备名：oray_x1pro，DTS 单文件
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OPENWRT="$WORKSPACE/source"

echo "=== DIY Part 1: X1 Pro setup ==="

# 1. Clone third-party packages into package/
mkdir -p "$OPENWRT/package"

git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora "$OPENWRT/package/luci-theme-aurora"
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config "$OPENWRT/package/luci-app-aurora-config"
echo "  → Third-party packages cloned"

# 2. 复制 DTS 文件到源码树（单文件）
DTS_FILE="$OPENWRT/target/linux/mediatek/dts/mt7981b-oray-x1-pro.dts"
if [ -f "$DTS_FILE" ] && grep -q "oray,x1pro" "$DTS_FILE"; then
  echo "  → DTS already exists (skipping)"
else
  cp "$WORKSPACE/devices/mt7981b-oray-x1-pro.dts" "$OPENWRT/target/linux/mediatek/dts/"
  echo "  → DTS copied"
fi

# 3. 注入设备构建规则到 filogic.mk
FILOGIC_MK="$OPENWRT/target/linux/mediatek/image/filogic.mk"
if grep -q "oray_x1pro" "$FILOGIC_MK"; then
  echo "  → filogic.mk already has oray_x1pro (skipping)"
else
  awk '
  /^TARGET_DEVICES \+= / && !inserted {
    print "define Device/oray_x1pro"
    print "  DEVICE_VENDOR := Oray"
    print "  DEVICE_MODEL := X1 Pro"
    print "  DEVICE_VARIANT := v1"
    print "  DEVICE_DTS := mt7981b-oray-x1-pro"
    print "  DEVICE_DTS_DIR := ../dts"
    print "  BOARD_NAME := oray_x1pro"
    print "  SUPPORTED_DEVICES += oray,x1pro"
    print "  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"
    print "  UBINIZE_OPTS := -E 5"
    print "  BLOCKSIZE := 128k"
    print "  PAGESIZE := 2048"
    print "  IMAGE_SIZE := 114688k"
    print "  KERNEL_IN_UBI := 1"
    print "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata"
    print "endef"
    print "TARGET_DEVICES += oray_x1pro"
    print ""
    inserted=1
  }
  { print }
  ' "$FILOGIC_MK" > "$FILOGIC_MK.tmp" && mv "$FILOGIC_MK.tmp" "$FILOGIC_MK"
  echo "  → filogic.mk: oray_x1pro device added"
fi

# 4. 注入 02_network 设备支持
NETWORK_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if grep -q "oray,x1pro" "$NETWORK_FILE"; then
  echo "  → 02_network already has oray,x1pro (skipping)"
else
  cp "$NETWORK_FILE" "$NETWORK_FILE.bak"

  # 4a. interfaces: 在 mediatek_setup_interfaces() 的 case 中插入
  awk '
  BEGIN { in_interfaces = 0 }
  /mediatek_setup_interfaces\(\)/ { in_interfaces = 1 }
  in_interfaces && /openembed,som7981\|\\\\/ {
    print
    print "\toray,x1pro|\\"
    in_interfaces = 0
    next
  }
  { print }
  ' "$NETWORK_FILE.bak" > "$NETWORK_FILE.tmp"

  # 4b. MAC: 在 mediatek_setup_macs() 的 case 中插入 oray,x1pro 条目
  awk '
  BEGIN { in_macs = 0; mac_inserted = 0 }
  /mediatek_setup_macs\(\)/ { in_macs = 1 }
  in_macs && !mac_inserted && /qihoo,360t7\)/ {
    print "\toray,x1pro)"
    print "\t\twan_mac=$(mtd_get_mac_binary Factory 0xe000)"
    print "\t\tlan_mac=$(macaddr_add \"$wan_mac\" 1)"
    print "\t\tlabel_mac=$wan_mac"
    print "\t\t;;"
    print ""
    mac_inserted = 1
  }
  { print }
  ' "$NETWORK_FILE.tmp" > "$NETWORK_FILE" && rm "$NETWORK_FILE.tmp" "$NETWORK_FILE.bak"
  echo "  → 02_network: oray,x1pro added"
fi

# 5. 注入 platform.sh sysupgrade 支持
PLATFORM_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
if grep -q "oray,x1pro" "$PLATFORM_FILE"; then
  echo "  → platform.sh already has oray,x1pro (skipping)"
else
  awk '
  /^case "\$board" in/ && !plat_inserted {
    print
    print "\toray,x1pro)"
    print "\t\tCI_UBIPART=\"ubi\""
    print "\t\tCI_KERNPART=\"kernel\""
    print "\t\tCI_ROOTPART=\"rootfs\""
    print "\t\tnand_do_upgrade \"$1\""
    print "\t\t;;"
    plat_inserted=1
    next
  }
  { print }
  ' "$PLATFORM_FILE" > "$PLATFORM_FILE.tmp" && mv "$PLATFORM_FILE.tmp" "$PLATFORM_FILE"
  echo "  → platform.sh: oray,x1pro added"
fi

# 6. 注入 preinit 05_set_preinit_iface
PREINIT_FILE="$OPENWRT/target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface"
if grep -q "oray,x1pro" "$PREINIT_FILE"; then
  echo "  → preinit already has oray,x1pro (skipping)"
else
  sed -i '/openembed,som7981|\\/a\\toray,x1pro|\\' "$PREINIT_FILE"
  echo "  → preinit: oray,x1pro added"
fi

echo "=== DIY Part 1 done ==="
