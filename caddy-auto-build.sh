#!/bin/bash

# Caddy 自动编译和发布脚本
# 作者: simtelboy
# 用途: 定期检查 Caddy 版本并自动编译发布

set -e

# 配置文件路径
CONFIG_FILE="/root/caddy-build-config.json"
LOG_FILE="/var/log/caddy-auto-build.log"
CADDY_BUILD_DIR="/root"

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# 错误处理函数
error_exit() {
    log "错误: $1"
    exit 1
}

# 检查是否为强制编译模式
check_force_build() {
    if [[ "$FORCE_BUILD" == "true" ]]; then
        log "========== 强制编译模式已启用 =========="
        log "⚠️  将跳过版本检查，强制重新编译"
        log "⚠️  这将覆盖 GitHub 上的同版本文件"
        return 0  # 强制编译模式
    else
        return 1  # 正常模式
    fi
}

# 设置环境变量
setup_environment() {
    # 确保使用正确的 Go 版本
    export PATH="/usr/local/go/bin:$PATH"
    export GOPATH="$HOME/go"
    export PATH="$GOPATH/bin:$PATH"

    # 创建 GOPATH 目录（如果不存在）
    mkdir -p "$GOPATH/bin"

    log "环境变量设置完成"
    log "PATH: $PATH"
    log "GOPATH: $GOPATH"

    # 验证 Go 版本
    if command -v go >/dev/null 2>&1; then
        local go_version=$(go version)
        log "当前 Go 版本: $go_version"

        # 检查是否为 1.25+ 版本
        if echo "$go_version" | grep -q "go1\.2[5-9]\|go1\.[3-9][0-9]\|go[2-9]\."; then
            log "✓ Go 版本满足 Caddy v2.10.2 要求"
        else
            error_exit "Go 版本过低，Caddy v2.10.2 需要 Go >= 1.25"
        fi
    else
        error_exit "Go 未找到，请检查安装"
    fi
}

# 检查必要的工具
check_dependencies() {
    log "检查依赖工具..."

    # 检查基本工具
    command -v curl >/dev/null 2>&1 || error_exit "curl 未安装"
    command -v jq >/dev/null 2>&1 || error_exit "jq 未安装"
    command -v git >/dev/null 2>&1 || error_exit "git 未安装"
    command -v gcc >/dev/null 2>&1 || error_exit "gcc 未安装，需要 C 编译器。请运行: apt-get install build-essential"

    # 检查 Go（应该已经在环境设置中验证过）
    command -v go >/dev/null 2>&1 || error_exit "Go 未找到"

    # 检查 xcaddy
    if ! command -v xcaddy >/dev/null 2>&1; then
        error_exit "xcaddy 未安装。请检查安装脚本"
    fi

    log "依赖检查完成"
}

# 读取配置文件
read_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "配置文件不存在，创建默认配置..."
        create_default_config
    fi
    
    GITHUB_TOKEN=$(jq -r '.github_token' "$CONFIG_FILE")
    GITHUB_REPO=$(jq -r '.github_repo' "$CONFIG_FILE")
    FORWARDPROXY_HASH=$(jq -r '.forwardproxy_hash' "$CONFIG_FILE")
    
    if [[ "$GITHUB_TOKEN" == "null" || "$GITHUB_TOKEN" == "" ]]; then
        error_exit "GitHub Token 未配置，请编辑 $CONFIG_FILE"
    fi
    
    log "配置读取完成"
}

# 创建默认配置文件
create_default_config() {
    cat > "$CONFIG_FILE" << EOF
{
    "github_token": "YOUR_GITHUB_TOKEN_HERE",
    "github_repo": "simtelboy/eye",
    "forwardproxy_hash": "fd64f79a187f3733a99fc79e7cb77278b3c1500c"
}
EOF
    log "已创建默认配置文件: $CONFIG_FILE"
    log "请编辑配置文件并设置您的 GitHub Token"
}

# 获取 Caddy 官方最新版本
get_caddy_latest_version() {
    log "获取 Caddy 官方最新版本..."
    CADDY_LATEST=$(curl -s "https://api.github.com/repos/caddyserver/caddy/releases/latest" | jq -r '.tag_name')
    
    if [[ "$CADDY_LATEST" == "null" || "$CADDY_LATEST" == "" ]]; then
        error_exit "无法获取 Caddy 最新版本"
    fi
    
    log "Caddy 官方最新版本: $CADDY_LATEST"
}

# 获取我们项目的最新版本
get_our_latest_version() {
    log "获取项目最新版本..."
    OUR_LATEST=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | jq -r '.tag_name')
    
    if [[ "$OUR_LATEST" == "null" ]]; then
        OUR_LATEST="v0.0.0"
        log "项目暂无发布版本，设置为: $OUR_LATEST"
    else
        log "项目最新版本: $OUR_LATEST"
    fi
}

# 版本比较函数
version_compare() {
    # 移除 v 前缀进行比较
    local ver1=$(echo "$1" | sed 's/^v//')
    local ver2=$(echo "$2" | sed 's/^v//')

    log "比较版本: $ver1 vs $ver2"

    if [[ "$ver1" == "$ver2" ]]; then
        log "版本相等"
        return 0  # 相等
    fi

    # 使用更可靠的版本比较方法
    # 将版本号分解为数字数组进行比较
    IFS='.' read -ra VER1_PARTS <<< "$ver1"
    IFS='.' read -ra VER2_PARTS <<< "$ver2"

    # 确保两个版本号有相同的部分数量
    local max_parts=${#VER1_PARTS[@]}
    if [[ ${#VER2_PARTS[@]} -gt $max_parts ]]; then
        max_parts=${#VER2_PARTS[@]}
    fi

    # 逐个比较版本号的每个部分
    for ((i=0; i<max_parts; i++)); do
        local part1=${VER1_PARTS[i]:-0}
        local part2=${VER2_PARTS[i]:-0}

        # 移除非数字字符（如 rc, beta 等）
        part1=$(echo "$part1" | sed 's/[^0-9].*$//')
        part2=$(echo "$part2" | sed 's/[^0-9].*$//')

        # 如果为空，设为 0
        part1=${part1:-0}
        part2=${part2:-0}

        if [[ $part1 -gt $part2 ]]; then
            log "版本比较结果: $ver1 > $ver2"
            return 1  # ver1 > ver2
        elif [[ $part1 -lt $part2 ]]; then
            log "版本比较结果: $ver1 < $ver2"
            return 2  # ver1 < ver2
        fi
    done

    log "版本相等（详细比较）"
    return 0  # 相等
}

# 检查网络连接
check_network() {
    log "检查网络连接..."

    # 检查基本网络连接
    local network_ok=false
    local retry_count=0
    local max_retries=3

    while [[ $retry_count -lt $max_retries && "$network_ok" == "false" ]]; do
        if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
            network_ok=true
            break
        fi

        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log "网络连接失败，等待 5 秒后重试 ($retry_count/$max_retries)..."
            sleep 5
        fi
    done

    if [[ "$network_ok" == "false" ]]; then
        error_exit "网络连接失败！请检查网络设置。"
    fi

    # 检查 GitHub 连接
    local github_ok=false
    retry_count=0

    while [[ $retry_count -lt $max_retries && "$github_ok" == "false" ]]; do
        if curl -s --connect-timeout 10 --max-time 30 --head https://github.com >/dev/null 2>&1; then
            github_ok=true
            break
        fi

        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log "GitHub 连接失败，等待 10 秒后重试 ($retry_count/$max_retries)..."
            sleep 10
        fi
    done

    if [[ "$github_ok" == "false" ]]; then
        error_exit "无法连接到 GitHub！请检查网络设置或 GitHub 状态。"
    fi

    # 检查 GitHub API 访问
    local api_response=$(curl -s --connect-timeout 10 --max-time 30 \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/user" 2>/dev/null)

    local api_login=$(echo "$api_response" | jq -r '.login // empty' 2>/dev/null)

    if [[ "$api_login" == "" ]]; then
        log "GitHub API 响应: $api_response"
        error_exit "GitHub Token 验证失败！请检查 Token 是否有效。"
    fi

    log "网络连接正常，GitHub API 访问正常 (用户: $api_login)"
}

# 检查磁盘空间
check_disk_space() {
    log "检查磁盘空间..."

    # 检查根分区可用空间（KB）
    local available_space=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))

    log "可用磁盘空间: ${available_gb}GB"

    if [[ $available_gb -lt 2 ]]; then
        log "磁盘空间不足，开始清理..."
        cleanup_disk_space

        # 重新检查空间
        available_space=$(df / | tail -1 | awk '{print $4}')
        available_gb=$((available_space / 1024 / 1024))
        log "清理后可用空间: ${available_gb}GB"

        if [[ $available_gb -lt 2 ]]; then
            error_exit "磁盘空间仍然不足！需要至少 2GB 可用空间进行编译。当前可用: ${available_gb}GB"
        fi
    fi

    log "磁盘空间检查通过"
}

# 清理磁盘空间
cleanup_disk_space() {
    log "开始清理磁盘空间..."

    # 清理 Go 编译临时文件
    log "清理 Go 编译临时文件..."
    rm -rf /tmp/go-build* 2>/dev/null || true
    rm -rf /tmp/buildenv_* 2>/dev/null || true

    # 清理 Go 缓存
    log "清理 Go 缓存..."
    if command -v go >/dev/null 2>&1; then
        go clean -cache 2>/dev/null || true
        go clean -modcache 2>/dev/null || true
    fi

    # 清理系统缓存
    log "清理系统缓存..."
    apt clean 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    # 清理日志文件
    log "清理旧日志文件..."
    journalctl --vacuum-time=3d 2>/dev/null || true

    # 清理旧的编译文件
    log "清理旧的编译文件..."
    find "$CADDY_BUILD_DIR" -name "caddy-*" -type f -mtime +7 -delete 2>/dev/null || true

    log "磁盘空间清理完成"
}

# 设置编译环境
setup_build_environment() {
    log "设置编译环境..."

    # 创建自定义临时目录
    local build_tmp_dir="/root/caddy-build-tmp"
    mkdir -p "$build_tmp_dir"

    # 设置环境变量使用自定义临时目录
    export TMPDIR="$build_tmp_dir"
    export GOCACHE="$build_tmp_dir/go-cache"
    export GOMODCACHE="$build_tmp_dir/go-mod"

    # 设置 Go 编译选项
    export CGO_ENABLED=1

    # 设置编译标志以确保兼容性
    # 使用静态链接减少对系统库的依赖
    export CGO_CFLAGS="-O2 -g"
    export CGO_LDFLAGS="-static-libgcc"

    # 设置 Go 编译标志
    export GOOS=linux
    export GOARCH=amd64

    # 清理旧的临时文件
    rm -rf /tmp/go-build* 2>/dev/null || true
    rm -rf /tmp/buildenv_* 2>/dev/null || true
    rm -rf "$build_tmp_dir"/* 2>/dev/null || true

    log "编译环境设置完成"
    log "TMPDIR: $TMPDIR"
    log "GOCACHE: $GOCACHE"
    log "GOMODCACHE: $GOMODCACHE"
    log "CGO_ENABLED: $CGO_ENABLED"
    log "CGO_CFLAGS: $CGO_CFLAGS"
    log "CGO_LDFLAGS: $CGO_LDFLAGS"
}

# 编译 Caddy
build_caddy() {
    log "开始编译 Caddy $CADDY_LATEST..."

    # 检查磁盘空间
    check_disk_space

    # 检查 C 编译器（CGO 需要）
    if ! command -v gcc >/dev/null 2>&1; then
        error_exit "gcc 未安装，CGO 编译需要 C 编译器。请运行: apt-get install build-essential"
    fi

    log "C 编译器检查通过: $(gcc --version | head -n1)"

    # 检查 glibc
    if ldconfig -p | grep -q libc.so.6; then
        local glibc_version=$(ldd --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+' | head -n1)
        log "glibc 检查通过: $glibc_version"
    else
        error_exit "glibc 不可用，Caddy 编译需要 glibc"
    fi

    # 设置编译环境
    setup_build_environment

    cd "$CADDY_BUILD_DIR"

    # 清理旧的编译文件
    rm -f caddy

    # 设置环境变量并编译
    log "开始编译，使用 CGO_ENABLED=1 和兼容性标志..."

    local build_cmd="CGO_ENABLED=1 CGO_CFLAGS=\"$CGO_CFLAGS\" CGO_LDFLAGS=\"$CGO_LDFLAGS\" xcaddy build --with github.com/caddyserver/forwardproxy=github.com/simtelboy/caddysinglefile@$FORWARDPROXY_HASH"
    log "执行编译命令: $build_cmd"

    # 使用完整的环境变量进行编译
    CGO_ENABLED=1 \
    CGO_CFLAGS="$CGO_CFLAGS" \
    CGO_LDFLAGS="$CGO_LDFLAGS" \
    GOOS="$GOOS" \
    GOARCH="$GOARCH" \
    xcaddy build --with github.com/caddyserver/forwardproxy=github.com/simtelboy/caddysinglefile@"$FORWARDPROXY_HASH"
    
    if [[ ! -f "caddy" ]]; then
        error_exit "Caddy 编译失败"
    fi
    
    # 验证编译的版本
    local built_version=$(./caddy version | head -n1 | awk '{print $1}')
    log "编译完成，版本: $built_version"
    
    # 重命名为带版本号的文件名
    mv caddy "caddy-$CADDY_LATEST-linux-amd64"
    
    log "Caddy 编译成功: caddy-$CADDY_LATEST-linux-amd64"
}

# 创建或获取 GitHub Release
create_github_release() {
    log "检查 GitHub Release: $CADDY_LATEST..."

    # 首先检查是否已存在该版本的 release
    local existing_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$CADDY_LATEST")

    local existing_id=$(echo "$existing_response" | jq -r '.id')

    if [[ "$existing_id" != "null" && "$existing_id" != "" ]]; then
        log "Release $CADDY_LATEST 已存在，ID: $existing_id"

        local upload_url=$(echo "$existing_response" | jq -r '.upload_url' | sed 's/{?name,label}//')
        log "使用现有 Release，上传 URL: $upload_url"
        echo "$upload_url|$existing_id"
        return
    fi

    log "创建新的 GitHub Release: $CADDY_LATEST..."

    local release_data=$(cat << EOF
{
    "tag_name": "$CADDY_LATEST",
    "target_commitish": "main",
    "name": "Caddy $CADDY_LATEST with ForwardProxy",
    "body": "自动编译的 Caddy $CADDY_LATEST，包含 ForwardProxy 模块\\n\\n编译时间: $(date)\\nForwardProxy Hash: $FORWARDPROXY_HASH",
    "draft": false,
    "prerelease": false
}
EOF
)

    local response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$release_data" \
        "https://api.github.com/repos/$GITHUB_REPO/releases")

    local upload_url=$(echo "$response" | jq -r '.upload_url' | sed 's/{?name,label}//')
    local new_release_id=$(echo "$response" | jq -r '.id')

    if [[ "$upload_url" == "null" || "$upload_url" == "" ]]; then
        log "GitHub API 响应: $response"
        error_exit "创建 Release 失败"
    fi

    log "Release 创建成功，上传 URL: $upload_url"
    echo "$upload_url|$new_release_id"
}



# 处理重复文件
handle_duplicate_asset() {
    local asset_name="$1"
    local release_id="$2"

    log "处理重复文件: $asset_name"

    local assets_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_REPO/releases/$release_id/assets")

    local asset_id=$(echo "$assets_response" | jq -r ".[] | select(.name == \"$asset_name\") | .id")

    if [[ "$asset_id" != "" && "$asset_id" != "null" ]]; then
        log "发现重复文件，ID: $asset_id，自动删除..."

        local delete_response=$(curl -s -X DELETE \
            -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$GITHUB_REPO/releases/assets/$asset_id")

        if [[ "$delete_response" == "" ]]; then
            log "重复文件删除成功"
            return 0
        else
            log "警告: 删除重复文件失败: $delete_response"
            return 1
        fi
    else
        log "未发现重复文件"
        return 0
    fi
}



# 上传文件到 GitHub Release (已废弃，使用 upload-caddy.sh)
upload_to_github_deprecated() {
    local upload_url="$1"
    local release_id="$2"
    local file_path="$CADDY_BUILD_DIR/caddy-$CADDY_LATEST-linux-amd64"
    local file_name="caddy-$CADDY_LATEST-linux-amd64"

    log "上传文件到 GitHub: $file_name..."
    log "文件路径: $file_path"
    log "上传 URL: $upload_url"

    # 验证上传 URL
    if [[ "$upload_url" == "null" || "$upload_url" == "" ]]; then
        error_exit "无效的上传 URL"
    fi

    # 检查文件是否存在
    if [[ ! -f "$file_path" ]]; then
        log "错误: 文件不存在: $file_path"
        log "查找可能的文件位置..."
        find "$CADDY_BUILD_DIR" -name "*caddy*" -type f | head -5 | while read file; do
            log "找到文件: $file"
        done
        error_exit "编译文件不存在"
    fi

    log "文件大小: $(du -h "$file_path" | cut -f1)"

    # 首先检查并删除重复文件
    if [[ "$release_id" != "null" && "$release_id" != "" ]]; then
        log "检查是否存在重复文件..."
        handle_duplicate_asset "$file_name" "$release_id"
    fi

    # 重试上传最多3次
    local max_retries=3

    for ((retry_count=1; retry_count<=max_retries; retry_count++)); do
        log "尝试上传 (第 $retry_count 次)..."
        log "文件: $file_path"
        log "上传URL: $upload_url?name=$file_name"

        # 检查文件是否存在
        if [[ ! -f "$file_path" ]]; then
            log "错误: 文件不存在: $file_path"
            return 1
        fi

        log "开始执行 curl 命令..."
        log "命令参数检查:"
        log "  文件大小: $(du -h "$file_path" | cut -f1)"
        log "  上传URL长度: ${#upload_url} 字符"
        log "  Token长度: ${#GITHUB_TOKEN} 字符"

        # 使用 timeout 命令确保不会无限等待
        local curl_output
        local curl_exit_code

        log "执行 curl 命令（最大等待 150 秒）..."

        # 使用 timeout 命令包装 curl，确保不会卡死
        curl_output=$(timeout 150 curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
            --connect-timeout 30 \
            --max-time 120 \
            -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"$file_path" \
            "$upload_url?name=$file_name" 2>&1)
        curl_exit_code=$?

        log "curl 命令执行完成，退出码: $curl_exit_code"

        # 检查是否是 timeout 导致的退出
        if [[ $curl_exit_code -eq 124 ]]; then
            log "错误: curl 命令超时（150秒）"
        fi

        # 检查 curl 命令是否成功执行
        if [[ $curl_exit_code -ne 0 ]]; then
            log "错误: curl 命令执行失败，退出码: $curl_exit_code"
            case $curl_exit_code in
                6) log "curl 错误: 无法解析主机名" ;;
                7) log "curl 错误: 无法连接到服务器" ;;
                28) log "curl 错误: 操作超时" ;;
                35) log "curl 错误: SSL 连接错误" ;;
                *) log "curl 错误: 未知错误码 $curl_exit_code" ;;
            esac
            log "curl 输出: $curl_output"
        else
            log "curl 命令执行成功"

            # 分离响应和 HTTP 状态码
            local http_code=$(echo "$curl_output" | grep "HTTP_CODE:" | cut -d: -f2 | tr -d ' ')
            local time_total=$(echo "$curl_output" | grep "TIME_TOTAL:" | cut -d: -f2 | tr -d ' ')
            local json_response=$(echo "$curl_output" | sed '/HTTP_CODE:/d' | sed '/TIME_TOTAL:/d')

            log "HTTP 状态码: [$http_code]"
            log "上传耗时: ${time_total}秒"
            log "响应长度: $(echo "$json_response" | wc -c) 字符"

            # 检查是否能正确解析响应
            if [[ -z "$curl_output" ]]; then
                log "错误: curl 命令没有返回任何输出"
            elif [[ -z "$http_code" ]]; then
                log "错误: 无法从响应中提取 HTTP 状态码"
                log "curl 原始输出前100字符: $(echo "$curl_output" | head -c 100)"
            else
                # 检查成功情况
                if [[ "$http_code" == "201" ]]; then
                    log "✅ 文件上传成功!"
                    local download_url=$(echo "$json_response" | jq -r '.browser_download_url' 2>/dev/null)
                    if [[ "$download_url" != "null" && "$download_url" != "" ]]; then
                        log "下载链接: $download_url"
                    fi
                    return 0
                fi

                # 检查是否是重复文件错误
                if [[ "$http_code" == "422" ]]; then
                    local error_code=$(echo "$json_response" | jq -r '.errors[0].code // empty' 2>/dev/null)
                    if [[ "$error_code" == "already_exists" ]]; then
                        log "检测到重复文件，删除后重试..."
                        if handle_duplicate_asset "$file_name" "$release_id"; then
                            log "重复文件已删除，重新上传..."
                            # 重复文件处理不算重试次数
                            ((retry_count--))
                            continue
                        else
                            log "处理重复文件失败"
                        fi
                    fi
                fi

                # 记录其他错误
                log "❌ 上传失败，HTTP状态码: $http_code"
                if [[ -n "$json_response" ]]; then
                    log "错误响应: $json_response"
                fi
            fi
        fi

        # 如果不是最后一次重试，等待后继续
        if [[ $retry_count -lt $max_retries ]]; then
            log "等待 5 秒后重试..."
            sleep 5
        fi
    done

    error_exit "文件上传失败，已重试 $max_retries 次"
}

# 主函数
main() {
    log "========== 天神之眼 自动编译脚本开始 =========="

     # 检查是否为强制编译模式
    local force_mode=false
    if check_force_build; then
        force_mode=true
    fi


    # 设置环境变量
    setup_environment

    # 检查依赖
    check_dependencies

    # 读取配置
    read_config

    # 检查网络连接
    check_network

    # 检查磁盘空间
    check_disk_space
    
    # 获取版本信息
    get_caddy_latest_version
    get_our_latest_version
    
    # 如果是强制编译模式，跳过版本比较
    if [[ "$force_mode" == "true" ]]; then
        log "🚀 强制编译模式：跳过版本比较，直接开始编译"
        log "目标版本: $CADDY_LATEST"
    else
        # 正常模式：进行版本比较
        log "开始版本比较: Caddy $CADDY_LATEST vs 项目 $OUR_LATEST"

        # 临时禁用 set -e 以避免版本比较函数的返回值导致脚本退出
        set +e
        version_compare "$CADDY_LATEST" "$OUR_LATEST"
        local compare_result=$?
        set -e

        log "版本比较返回值: $compare_result"

        if [[ $compare_result -eq 0 ]]; then
            log "版本相同，无需更新"
            exit 0
        elif [[ $compare_result -eq 2 ]]; then
            log "Caddy 官方版本 ($CADDY_LATEST) 低于或等于项目版本 ($OUR_LATEST)，无需更新"
            exit 0
        fi

        log "发现新版本！Caddy: $CADDY_LATEST > 项目: $OUR_LATEST"
    fi
    
    # 编译 Caddy
    build_caddy

    # 使用独立的上传脚本
    local caddy_file_path="$CADDY_BUILD_DIR/caddy-$CADDY_LATEST-linux-amd64"

    log "调用独立上传脚本..."
    local upload_script="/usr/local/bin/upload-caddy.sh"

    # 如果在系统目录找不到，尝试当前目录（开发环境）
    if [[ ! -f "$upload_script" ]]; then
        upload_script="./upload-caddy.sh"
    fi

    if [[ -f "$upload_script" ]]; then
        if "$upload_script" "$caddy_file_path" "$CADDY_LATEST"; then
            log "✅ 文件上传成功!"
        else
            error_exit "文件上传失败"
        fi
    else
        error_exit "上传脚本不存在: $upload_script"
    fi
    
    log "========== 自动编译和发布完成 =========="
}

# 运行主函数
main "$@"
