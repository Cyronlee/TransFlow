#!/bin/bash
set -euo pipefail

# ============================================================================
# TransFlow DMG Packaging Script
# 使用 create-dmg 工具将 TransFlow.app 打包为 DMG 安装镜像
# ============================================================================

# ── 配置 ──────────────────────────────────────────────────────────────────────

APP_NAME="TransFlow"
SCHEME="TransFlow"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_PROJECT="${PROJECT_DIR}/TransFlow/TransFlow.xcodeproj"
BUILD_DIR="${PROJECT_DIR}/build"
DMG_DIR="${BUILD_DIR}/dmg"
APP_PATH="${DMG_DIR}/${APP_NAME}.app"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}.dmg"

# DMG 外观配置
DMG_VOLNAME="${APP_NAME}"
DMG_BACKGROUND="${PROJECT_DIR}/scripts/dmg/background.png"
DMG_WINDOW_POS_X=200
DMG_WINDOW_POS_Y=120
DMG_WINDOW_WIDTH=800
DMG_WINDOW_HEIGHT=600
DMG_ICON_SIZE=140
DMG_TEXT_SIZE=14
DMG_APP_ICON_X=245
DMG_APP_ICON_Y=290
DMG_APP_DROP_LINK_X=555
DMG_APP_DROP_LINK_Y=290

# 签名配置
CODESIGN_IDENTITY=""        # 代码签名身份（留空=不签名, "-"=ad-hoc, 其他=证书名）
SIGN_ENTITLEMENTS=""        # entitlements plist 路径（可选，留空=自动检测项目 entitlements）
DEFAULT_ENTITLEMENTS="${PROJECT_DIR}/TransFlow/TransFlow/TransFlow.entitlements"

# Build 配置
CONFIGURATION="Release"
ARCH="$(uname -m)"  # arm64 或 x86_64

# ── 颜色输出 ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── 参数解析 ─────────────────────────────────────────────────────────────────

SKIP_BUILD=false
CLEAN_BUILD=false
OPEN_DMG=false
SIGN_APP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --open)
            OPEN_DMG=true
            shift
            ;;
        --sign)
            SIGN_APP=true
            # 如果下一个参数不是 --开头的选项，则视为签名身份
            if [[ $# -gt 1 ]] && [[ "$2" != --* ]]; then
                CODESIGN_IDENTITY="$2"
                shift 2
            else
                shift
            fi
            ;;
        --codesign)
            # 兼容旧参数：--codesign ID（仅签名 DMG）
            SIGN_APP=true
            CODESIGN_IDENTITY="$2"
            shift 2
            ;;
        --entitlements)
            SIGN_ENTITLEMENTS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-build         跳过 Xcode build，直接打包已有的 .app"
            echo "  --clean              clean build（先清理再构建）"
            echo "  --open               打包完成后自动打开 DMG"
            echo "  --sign [IDENTITY]    对 .app 和 DMG 进行代码签名"
            echo "                         不指定 IDENTITY: 自动检测或使用 ad-hoc 签名"
            echo "                         指定 IDENTITY: 使用指定的签名身份"
            echo "  --codesign ID        (旧参数兼容) 同 --sign ID"
            echo "  --entitlements FILE  指定 entitlements plist（配合 --sign 使用）"
            echo "  -h, --help           显示帮助"
            echo ""
            echo "签名说明:"
            echo "  Ad-hoc 签名（无证书）:  ./scripts/build-dmg.sh --sign"
            echo "  指定证书签名:           ./scripts/build-dmg.sh --sign \"Developer ID Application: Name\""
            echo ""
            echo "  注意: 没有付费 Apple Developer Program 会员的 ad-hoc 签名，"
            echo "  用户首次打开时仍需 右键→打开 来绕过 Gatekeeper 验证。"
            exit 0
            ;;
        *)
            error "未知参数: $1（使用 --help 查看帮助）"
            ;;
    esac
done

# ── 前置检查 ─────────────────────────────────────────────────────────────────

info "检查依赖..."

if ! command -v create-dmg &> /dev/null; then
    error "create-dmg 未安装。请运行: brew install create-dmg"
fi

if ! command -v xcodebuild &> /dev/null; then
    error "xcodebuild 未找到。请安装 Xcode Command Line Tools"
fi

success "依赖检查通过"

# ── 签名身份检测 ──────────────────────────────────────────────────────────────

detect_codesign_identity() {
    # 如果已经手动指定了身份，直接返回
    if [ -n "${CODESIGN_IDENTITY}" ]; then
        return
    fi
    
    info "自动检测可用的代码签名身份..."
    
    local identities
    identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
    
    # 优先查找 Developer ID Application（需要付费会员）
    local dev_id
    dev_id=$(echo "$identities" | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
    if [ -n "$dev_id" ]; then
        CODESIGN_IDENTITY="$dev_id"
        info "检测到 Developer ID: ${CODESIGN_IDENTITY}"
        return
    fi
    
    # 其次查找 Apple Development（免费开发者证书）
    local apple_dev
    apple_dev=$(echo "$identities" | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
    if [ -n "$apple_dev" ]; then
        CODESIGN_IDENTITY="$apple_dev"
        info "检测到 Apple Development: ${CODESIGN_IDENTITY}"
        return
    fi
    
    # 查找任意可用的代码签名身份
    local any_id
    any_id=$(echo "$identities" | grep -v "^$" | grep -v "valid identities found" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
    if [ -n "$any_id" ]; then
        CODESIGN_IDENTITY="$any_id"
        info "检测到签名身份: ${CODESIGN_IDENTITY}"
        return
    fi
    
    # 没有找到任何证书，使用 ad-hoc 签名
    warn "未检测到代码签名证书，将使用 ad-hoc 签名（-）"
    warn "Ad-hoc 签名可保证应用完整性，但用户仍需右键→打开来绕过 Gatekeeper"
    CODESIGN_IDENTITY="-"
}

codesign_app() {
    local app_path="$1"
    
    info "正在对 ${APP_NAME}.app 进行代码签名..."
    info "签名身份: ${CODESIGN_IDENTITY}"
    
    # 构建 codesign 参数
    local SIGN_ARGS=(
        --force
        --deep
        --timestamp
        --options runtime
        --sign "${CODESIGN_IDENTITY}"
    )
    
    # ad-hoc 签名不支持 timestamp 和 runtime options
    if [ "${CODESIGN_IDENTITY}" = "-" ]; then
        SIGN_ARGS=(
            --force
            --deep
            --sign "-"
        )
    fi
    
    # 添加 entitlements（如果指定或自动检测到项目默认 entitlements）
    local ent_file="${SIGN_ENTITLEMENTS}"
    if [ -z "${ent_file}" ] && [ -f "${DEFAULT_ENTITLEMENTS}" ]; then
        ent_file="${DEFAULT_ENTITLEMENTS}"
        info "自动检测到项目 entitlements: ${ent_file}"
    fi
    if [ -n "${ent_file}" ]; then
        if [ -f "${ent_file}" ]; then
            SIGN_ARGS+=(--entitlements "${ent_file}")
            info "使用 entitlements: ${ent_file}"
        else
            warn "entitlements 文件不存在: ${ent_file}，跳过"
        fi
    else
        warn "未找到 entitlements 文件，Hardened Runtime 可能会阻止麦克风等权限"
    fi
    
    # 1. 签名 Frameworks 中的每个 dylib / framework
    if [ -d "${app_path}/Contents/Frameworks" ]; then
        info "签名内嵌 Frameworks..."
        find "${app_path}/Contents/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null | while IFS= read -r -d '' fw; do
            codesign "${SIGN_ARGS[@]}" "$fw" 2>&1 || warn "签名失败: $(basename "$fw")"
        done
    fi
    
    # 2. 签名辅助工具（如果有）
    if [ -d "${app_path}/Contents/MacOS" ]; then
        find "${app_path}/Contents/MacOS" -type f -perm +111 ! -name "${APP_NAME}" -print0 2>/dev/null | while IFS= read -r -d '' helper; do
            info "签名辅助工具: $(basename "$helper")"
            codesign "${SIGN_ARGS[@]}" "$helper" 2>&1 || warn "签名失败: $(basename "$helper")"
        done
    fi
    
    # 3. 签名主 .app bundle
    info "签名 ${APP_NAME}.app..."
    codesign "${SIGN_ARGS[@]}" "${app_path}" 2>&1
    
    # 4. 验证签名
    info "验证签名..."
    if codesign --verify --verbose=2 "${app_path}" 2>&1; then
        success "代码签名验证通过"
    else
        warn "代码签名验证未通过，应用可能无法正常运行"
    fi
    
    # 5. 显示签名信息
    echo ""
    info "签名详情:"
    codesign --display --verbose=2 "${app_path}" 2>&1 | head -10
    echo ""
}

# ── 清理 ─────────────────────────────────────────────────────────────────────

info "清理旧的构建产物..."
rm -rf "${DMG_DIR}"
rm -f "${DMG_OUTPUT}"
mkdir -p "${DMG_DIR}"

# ── 构建 ─────────────────────────────────────────────────────────────────────

if [ "$SKIP_BUILD" = true ]; then
    warn "跳过构建步骤"
    
    # 查找已有的 .app
    DERIVED_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Release/*" -type d 2>/dev/null | head -1)
    if [ -z "$DERIVED_APP" ]; then
        error "未找到已构建的 ${APP_NAME}.app，请先构建或去掉 --skip-build"
    fi
    info "使用已有构建: ${DERIVED_APP}"
    cp -R "${DERIVED_APP}" "${APP_PATH}"
else
    if [ "$CLEAN_BUILD" = true ]; then
        info "执行 clean build..."
        xcodebuild clean \
            -project "${XCODE_PROJECT}" \
            -scheme "${SCHEME}" \
            -configuration "${CONFIGURATION}" \
            -quiet
    fi

    info "构建 ${APP_NAME} (${CONFIGURATION}, ${ARCH})..."
    
    xcodebuild build \
        -project "${XCODE_PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -arch "${ARCH}" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        -quiet \
        ONLY_ACTIVE_ARCH=NO
    
    # 复制 .app 到 DMG 准备目录
    BUILT_APP="${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
    if [ ! -d "${BUILT_APP}" ]; then
        error "构建完成但未找到 ${APP_NAME}.app: ${BUILT_APP}"
    fi
    
    cp -R "${BUILT_APP}" "${APP_PATH}"
    success "构建完成"
fi

# 验证 .app 存在
if [ ! -d "${APP_PATH}" ]; then
    error "${APP_NAME}.app 不存在: ${APP_PATH}"
fi

# ── 代码签名 ─────────────────────────────────────────────────────────────────

if [ "$SIGN_APP" = true ]; then
    detect_codesign_identity
    codesign_app "${APP_PATH}"
fi

# ── 获取版本号 ───────────────────────────────────────────────────────────────

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1")
DMG_FINAL="${BUILD_DIR}/${APP_NAME}-${APP_VERSION}.dmg"

info "版本: ${APP_VERSION} (build ${APP_BUILD})"

# ── 创建 DMG ────────────────────────────────────────────────────────────────

info "创建 DMG 安装镜像..."

CREATE_DMG_ARGS=(
    --volname "${DMG_VOLNAME}"
    --window-pos "${DMG_WINDOW_POS_X}" "${DMG_WINDOW_POS_Y}"
    --window-size "${DMG_WINDOW_WIDTH}" "${DMG_WINDOW_HEIGHT}"
    --icon-size "${DMG_ICON_SIZE}"
    --text-size "${DMG_TEXT_SIZE}"
    --icon "${APP_NAME}.app" "${DMG_APP_ICON_X}" "${DMG_APP_ICON_Y}"
    --hide-extension "${APP_NAME}.app"
    --app-drop-link "${DMG_APP_DROP_LINK_X}" "${DMG_APP_DROP_LINK_Y}"
    --no-internet-enable
)

# 添加背景图（如果存在）
if [ -f "${DMG_BACKGROUND}" ]; then
    CREATE_DMG_ARGS+=(--background "${DMG_BACKGROUND}")
    info "使用背景图: ${DMG_BACKGROUND}"
else
    warn "未找到背景图: ${DMG_BACKGROUND}，将使用默认背景"
fi

# 添加 DMG 代码签名（如果启用签名且非 ad-hoc）
# 注意: create-dmg 的 --codesign 不支持 ad-hoc("-") 签名
if [ "$SIGN_APP" = true ] && [ -n "${CODESIGN_IDENTITY}" ] && [ "${CODESIGN_IDENTITY}" != "-" ]; then
    CREATE_DMG_ARGS+=(--codesign "${CODESIGN_IDENTITY}")
    info "DMG 代码签名: ${CODESIGN_IDENTITY}"
fi

# 添加 volume icon（如果存在 .icns）
VOLICON="${PROJECT_DIR}/scripts/dmg/volume-icon.icns"
if [ -f "${VOLICON}" ]; then
    CREATE_DMG_ARGS+=(--volicon "${VOLICON}")
fi

# 执行 create-dmg
# create-dmg 退出码: 0=成功, 2=DMG 已创建但某些美化步骤失败
set +e
create-dmg \
    "${CREATE_DMG_ARGS[@]}" \
    --hdiutil-retries 15 \
    "${DMG_OUTPUT}" \
    "${DMG_DIR}/"
CREATE_DMG_EXIT=$?
set -e

if [ ${CREATE_DMG_EXIT} -ne 0 ] && [ ${CREATE_DMG_EXIT} -ne 2 ]; then
    # 清理可能残留的临时 rw DMG
    rm -f "${BUILD_DIR}"/rw.*.dmg 2>/dev/null
    error "create-dmg 失败 (exit code: ${CREATE_DMG_EXIT})"
fi

if [ -f "${DMG_OUTPUT}" ]; then
    # 重命名为带版本号的文件名
    mv "${DMG_OUTPUT}" "${DMG_FINAL}"
    success "DMG 创建成功!"
elif ls "${BUILD_DIR}"/rw.*.dmg 1>/dev/null 2>&1; then
    # create-dmg 可能因 unmount 失败留下了 rw DMG，尝试手动转换
    warn "create-dmg 未生成最终 DMG，尝试手动转换..."
    RW_DMG=$(ls "${BUILD_DIR}"/rw.*.dmg | head -1)
    
    # 强制 detach 所有可能挂载的 DMG
    for dev in $(hdiutil info 2>/dev/null | grep "/dev/disk" | grep -v "/dev/disk0" | awk '{print $1}' | sort -u); do
        hdiutil detach "$dev" -force 2>/dev/null || true
    done
    sleep 2
    
    hdiutil convert "${RW_DMG}" -format UDZO -o "${DMG_FINAL}" -quiet
    rm -f "${RW_DMG}"
    success "DMG 转换成功!"
else
    error "DMG 创建失败，未找到任何输出文件"
fi

# ── 结果 ─────────────────────────────────────────────────────────────────────

DMG_SIZE=$(du -h "${DMG_FINAL}" | cut -f1 | xargs)

# 签名状态
SIGN_STATUS="未签名"
if [ "$SIGN_APP" = true ]; then
    if [ "${CODESIGN_IDENTITY}" = "-" ]; then
        SIGN_STATUS="Ad-hoc 签名"
    else
        SIGN_STATUS="已签名 (${CODESIGN_IDENTITY})"
    fi
fi

echo ""
echo "============================================"
echo -e "  ${GREEN}${APP_NAME} DMG 打包完成${NC}"
echo "  版本:   ${APP_VERSION} (${APP_BUILD})"
echo "  架构:   ${ARCH}"
echo "  大小:   ${DMG_SIZE}"
echo "  签名:   ${SIGN_STATUS}"
echo "  路径:   ${DMG_FINAL}"
echo "============================================"
echo ""

# 自动打开
if [ "$OPEN_DMG" = true ]; then
    info "打开 DMG..."
    open "${DMG_FINAL}"
fi
