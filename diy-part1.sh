#!/bin/bash
# DIY Part 1: X1 Pro device setup
# 使用 awk index() 子串匹配注入，避免反斜杠正则转义问题
# 设备名：oray_x1pro，compatible：oray,x1pro，DTS 单文件
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OPENWRT="$WORKSPACE/source"

echo "=== DIY Part 1: X1 Pro setup ==="

# 1. Clone third-party packages into package/
mkdir -p "$OPENWRT/package"

for pkg in luci-theme-aurora luci-app-aurora-config; do
  if [ -d "$OPENWRT/package/$pkg" ]; then
    echo "  → $pkg already exists, skipping clone"
  else
    git clone --depth=1 "https://github.com/eamonxg/$pkg" "$OPENWRT/package/$pkg"
  fi
done
echo "  → Third-party packages cloned"

# 2. 复制 DTS 文件到源码树（单文件）
DTS_SRC="$WORKSPACE/devices/mt7981b-oray-x1-pro.dts"
DTS_DST="$OPENWRT/target/linux/mediatek/dts/mt7981b-oray-x1-pro.dts"
if [ -f "$DTS_DST" ] && grep -q "oray,x1pro" "$DTS_DST"; then
  echo "  → DTS already exists (skipping)"
else
  cp "$DTS_SRC" "$DTS_DST"
  echo "  → DTS copied"
fi

# 3. 注入设备构建规则到 filogic.mk
FILOGIC_MK="$OPENWRT/target/linux/mediatek/image/filogic.mk"
if grep -q "oray_x1pro" "$FILOGIC_MK"; then
  echo "  → filogic.mk already has oray_x1pro (skipping)"
else
  awk '
  index($0, "TARGET_DEVICES +=") && !inserted {
    print "define Device/oray_x1pro"
    print "  DEVICE_VENDOR := Oray"
    print "  DEVICE_MODEL := X1 Pro"
    print "  DEVICE_DTS := mt7981b-oray-x1-pro"
    print "  DEVICE_DTS_DIR := ../dts"
    print "  BOARD_NAME := oray_x1pro"
    print "  SUPPORTED_DEVICES += oray,x1pro"
    print "  UBINIZE_OPTS := -E 5"
    print "  BLOCKSIZE := 128k"
    print "  PAGESIZE := 2048"
    print "  IMAGE_SIZE := 114688k"
    print "  KERNEL_IN_UBI := 1"
    print "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata"
    print "  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount"
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
  # 4a. interfaces: 加入 openembed,som7981 组（lan=eth1 千兆口, wan=eth0 2.5G 口）
  #     锚点 openwrt,one|（该组末尾，唯一）
  awk '
  /mediatek_setup_interfaces\(\)/ { in_if = 1 }
  /mediatek_setup_macs\(\)/ { in_if = 0 }
  in_if && index($0, "openwrt,one|") && !if_done {
    print
    print "\toray,x1pro|\\"
    if_done = 1
    next
  }
  { print }
  ' "$NETWORK_FILE" > "$NETWORK_FILE.tmp" && mv "$NETWORK_FILE.tmp" "$NETWORK_FILE"

  # 4b. MAC: 在 mediatek_setup_macs() 中 qihoo,360t7) 的 ;; 之后插入 oray 独立分支
  awk '
  /mediatek_setup_macs\(\)/ { in_macs = 1 }
  in_macs && index($0, "qihoo,360t7)") { in_qihoo = 1 }
  in_qihoo && /^\t\t;;$/ && !mac_done {
    print
    print "\toray,x1pro)"
    print "\t\twan_mac=$(mtd_get_mac_binary Factory 0xe000)"
    print "\t\tlan_mac=$(macaddr_add \"$wan_mac\" 1)"
    print "\t\tlabel_mac=$wan_mac"
    print "\t\t;;"
    mac_done = 1
    in_qihoo = 0
    next
  }
  { print }
  ' "$NETWORK_FILE" > "$NETWORK_FILE.tmp" && mv "$NETWORK_FILE.tmp" "$NETWORK_FILE"

  # 验证注入结果
  if grep -q "oray,x1pro" "$NETWORK_FILE"; then
    echo "  → 02_network: oray,x1pro added (interfaces + macs)"
  else
    echo "  → [WARN] 02_network injection may have failed" >&2
  fi
fi

# 5. 注入 platform.sh sysupgrade 支持（加入 qihoo,360t7 的 ubi/nand 组）
#    用 |\ 续行加入 case 组，共享 CI_UBIPART/CI_KERNPART/CI_ROOTPART + nand_do_upgrade
PLATFORM_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
if grep -q "oray,x1pro" "$PLATFORM_FILE"; then
  echo "  → platform.sh already has oray,x1pro (skipping)"
else
  awk '
  /platform_do_upgrade\(\)/ { in_plat = 1 }
  in_plat && index($0, "jcg,q30-pro|") && !plat_done {
    print
    print "\toray,x1pro|\\"
    plat_done = 1
    next
  }
  { print }
  ' "$PLATFORM_FILE" > "$PLATFORM_FILE.tmp" && mv "$PLATFORM_FILE.tmp" "$PLATFORM_FILE"
  echo "  → platform.sh: oray,x1pro added"
fi

# 6. 注入 preinit 05_set_preinit_iface（加入 openembed,som7981 组，eth1 为 preinit 口）
PREINIT_FILE="$OPENWRT/target/linux/mediatek/base-files/lib/preinit/05_set_preinit_iface"
if grep -q "oray,x1pro" "$PREINIT_FILE"; then
  echo "  → preinit already has oray,x1pro (skipping)"
else
  awk '
  index($0, "openembed,som7981|") && !pre_done {
    print
    print "\toray,x1pro|\\"
    pre_done = 1
    next
  }
  { print }
  ' "$PREINIT_FILE" > "$PREINIT_FILE.tmp" && mv "$PREINIT_FILE.tmp" "$PREINIT_FILE"
  echo "  → preinit: oray,x1pro added"
fi

echo "=== DIY Part 1 done ==="
