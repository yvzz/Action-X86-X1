#!/bin/bash
# DIY Part 1: X1 Pro device setup
# 原则：最小化侵入，只 patch 不改写上游文件
# 幂等设计：重复运行不会重复追加条目
# 参考 TR3000：第三方包直接 clone 到 package/，不用 feeds
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OPENWRT="$WORKSPACE/source"

echo "=== DIY Part 1: X1 Pro setup ==="

# 1. Clone third-party packages into package/ (参照 TR3000)
#    直接 clone 避免 feeds 分支/index 问题
mkdir -p "$OPENWRT/package"

git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora "$OPENWRT/package/luci-theme-aurora"
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config "$OPENWRT/package/luci-app-aurora-config"
echo "  → Third-party packages cloned"

# 2. DTS/dtsi 与 filogic.mk 已合入上游源码（yvzz/immortalwrt-mt798x-6.6）
#    不再需要从仓库复制，避免用旧版本回退上游改动。

# 4. Patch upstream 02_network — X1 Pro 接口定义（幂等）
NETWORK_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if [ -f "$NETWORK_FILE" ]; then
  if ! grep -q "oray,x1pro|\\\\" "$NETWORK_FILE"; then
    python3 -c '
import sys
f = sys.argv[1]
with open(f) as fh:
    content = fh.read()
old = "\tcudy,tr3000-v1-ubootmod|\\\n"
new = old + "\toray,x1pro-v1|\\\n"
content = content.replace(old, new, 1)
with open(f, "w") as fh:
    fh.write(content)
' "$NETWORK_FILE"
    echo "  → 02_network patched (X1 Pro interfaces added)"
  else
    echo "  → 02_network already has X1 Pro entries (skipping)"
  fi
else
  echo "  ⚠ 02_network not found at $NETWORK_FILE"
fi

# 5. Patch platform.sh — sysupgrade 支持（幂等）
PLATFORM_FILE="$OPENWRT/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
if [ -f "$PLATFORM_FILE" ]; then
  if ! grep -q "oray,x1pro|\\\\" "$PLATFORM_FILE"; then
    python3 -c '
import sys
f = sys.argv[1]
with open(f) as fh:
    content = fh.read()
old = "\tcudy,wbr3000uax-v1-ubootmod|\\\n"
new = old + "\toray,x1pro|\\\n"
content = content.replace(old, new, 1)
with open(f, "w") as fh:
    fh.write(content)
' "$PLATFORM_FILE"
    echo "  → platform.sh patched"
  else
    echo "  → platform.sh already has X1 Pro entry (skipping)"
  fi
fi

echo "=== DIY Part 1 done ==="
