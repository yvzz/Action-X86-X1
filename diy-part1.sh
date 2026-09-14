#!/bin/bash
# DIY Part 1: X1 Pro device setup
# 原则：最小化侵入，只 patch 不改写上游文件
# 幂等设计：重复运行不会重复追加条目
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OPENWRT="$WORKSPACE/source"

echo "=== DIY Part 1: X1 Pro setup ==="

# 1. Clone third-party packages into package/
mkdir -p "$OPENWRT/package"

git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora "$OPENWRT/package/luci-theme-aurora"
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config "$OPENWRT/package/luci-app-aurora-config"
echo "  → Third-party packages cloned"

# 2. 复制 DTS 文件到源码树
DTS_FILE="$OPENWRT/target/linux/mediatek/dts/mt7981b-oray-x1-pro.dts"
if [ -f "$DTS_FILE" ] && grep -q "oray,x1pro" "$DTS_FILE"; then
  echo "  → DTS already exists (skipping)"
else
  cp "$WORKSPACE/devices/mt7981b-oray-x1-pro.dts" "$OPENWRT/target/linux/mediatek/dts/"
  echo "  → DTS copied"
fi

# 3. 应用设备支持 patch（DTS 注册 + filogic.mk + 02_network + platform.sh + preinit）
PATCH_FILE="$WORKSPACE/patches/0001-mediatek-filogic-add-oray-x1-pro.patch"
cd "$OPENWRT"
if git diff --quiet HEAD -- target/linux/mediatek/ 2>/dev/null; then
  if patch -p1 --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
    patch -p1 < "$PATCH_FILE"
    echo "  → Device support patch applied"
  else
    echo "  → Patch already applied or conflict (skipping)"
  fi
else
  echo "  → Working tree not clean, skipping patch"
fi

echo "=== DIY Part 1 done ==="
