#!/bin/bash

# Caddy 文件上传脚本 - 专门负责上传编译好的 Caddy 文件到 GitHub

echo "========== Caddy 文件上传 =========="

# 参数检查
if [[ $# -eq 0 ]]; then
    echo "用法: $0 <caddy-file-path> [version]"
    echo "示例: $0 /root/caddy-v2.10.2-linux-amd64 v2.10.2"
    exit 1
fi

CADDY_FILE="$1"
VERSION="${2:-v2.10.2}"

# 从文件名提取版本信息（如果没有提供版本参数）
if [[ "$VERSION" == "v2.10.2" && "$CADDY_FILE" =~ caddy-v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    VERSION="v${BASH_REMATCH[1]}"
fi

FILE_NAME=$(basename "$CADDY_FILE")

echo "文件路径: $CADDY_FILE"
echo "版本: $VERSION"
echo "文件名: $FILE_NAME"

# 检查文件是否存在
if [[ ! -f "$CADDY_FILE" ]]; then
    echo "错误: Caddy 文件不存在: $CADDY_FILE"
    exit 1
fi

echo "文件大小: $(du -h "$CADDY_FILE" | cut -f1)"

# 读取配置
CONFIG_FILE="/root/caddy-build-config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

GITHUB_TOKEN=$(jq -r '.github_token' "$CONFIG_FILE")
GITHUB_REPO=$(jq -r '.github_repo' "$CONFIG_FILE")

echo "GitHub 仓库: $GITHUB_REPO"
echo "Token 长度: ${#GITHUB_TOKEN} 字符"

# 验证配置
if [[ "$GITHUB_TOKEN" == "null" || "$GITHUB_TOKEN" == "" ]]; then
    echo "错误: GitHub Token 未配置"
    exit 1
fi

if [[ "$GITHUB_REPO" == "null" || "$GITHUB_REPO" == "" ]]; then
    echo "错误: GitHub 仓库未配置"
    exit 1
fi

# 获取或创建 Release
echo ""
echo "检查 Release: $VERSION..."

RELEASE_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$VERSION")

UPLOAD_URL=$(echo "$RELEASE_INFO" | jq -r '.upload_url' | sed 's/{?name,label}//')
RELEASE_ID=$(echo "$RELEASE_INFO" | jq -r '.id')

if [[ "$UPLOAD_URL" == "null" || "$UPLOAD_URL" == "" ]]; then
    echo "Release 不存在，创建新的 Release: $VERSION..."

    CREATE_DATA=$(jq -n \
        --arg tag "$VERSION" \
        --arg name "天神之眼 $VERSION" \
        --arg body "自动编译的天神之眼 $VERSION，本程序运行在debian11以上！" \
        '{
            tag_name: $tag,
            name: $name,
            body: $body,
            draft: false,
            prerelease: false
        }')

    RELEASE_INFO=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CREATE_DATA" \
        "https://api.github.com/repos/$GITHUB_REPO/releases")

    UPLOAD_URL=$(echo "$RELEASE_INFO" | jq -r '.upload_url' | sed 's/{?name,label}//')
    RELEASE_ID=$(echo "$RELEASE_INFO" | jq -r '.id')

    if [[ "$UPLOAD_URL" == "null" || "$UPLOAD_URL" == "" ]]; then
        echo "错误: 无法创建 Release"
        echo "响应: $RELEASE_INFO"
        exit 1
    fi

    echo "Release 创建成功"
fi

echo "Release ID: $RELEASE_ID"
echo "上传 URL: $UPLOAD_URL"

# 检查是否有重复文件
echo ""
echo "检查重复文件..."
ASSETS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/releases/$RELEASE_ID/assets")

EXISTING_ASSET=$(echo "$ASSETS" | jq -r --arg name "$FILE_NAME" '.[] | select(.name==$name) | .id')

if [[ "$EXISTING_ASSET" != "" && "$EXISTING_ASSET" != "null" ]]; then
    echo "发现重复文件，ID: $EXISTING_ASSET"
    echo "删除重复文件..."
    
    DELETE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_REPO/releases/assets/$EXISTING_ASSET")
    
    DELETE_CODE=$(echo "$DELETE_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    echo "删除结果: HTTP $DELETE_CODE"
    
    if [[ "$DELETE_CODE" == "204" ]]; then
        echo "✓ 重复文件删除成功"
    else
        echo "✗ 重复文件删除失败"
    fi
fi

# 上传文件（带重试机制）
echo ""
echo "开始上传文件..."

MAX_RETRIES=3
for ((retry=1; retry<=MAX_RETRIES; retry++)); do
    echo "尝试上传 (第 $retry 次)..."

    UPLOAD_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
        --connect-timeout 30 \
        --max-time 120 \
        -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$CADDY_FILE" \
        "$UPLOAD_URL?name=$FILE_NAME" 2>&1)

    UPLOAD_EXIT=$?

    # 分析响应
    HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2 | tr -d ' ')
    TIME_TOTAL=$(echo "$UPLOAD_RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2 | tr -d ' ')
    JSON_RESPONSE=$(echo "$UPLOAD_RESPONSE" | sed '/HTTP_CODE:/d' | sed '/TIME_TOTAL:/d')

    echo "curl 退出码: $UPLOAD_EXIT"
    echo "HTTP 状态码: [$HTTP_CODE]"
    echo "耗时: ${TIME_TOTAL}秒"

    if [[ "$HTTP_CODE" == "201" ]]; then
        echo "✅ 上传成功!"
        DOWNLOAD_URL=$(echo "$JSON_RESPONSE" | jq -r '.browser_download_url' 2>/dev/null)
        if [[ "$DOWNLOAD_URL" != "null" && "$DOWNLOAD_URL" != "" ]]; then
            echo "下载链接: $DOWNLOAD_URL"
        fi
        echo ""
        echo "========== 上传完成 =========="
        exit 0
    fi

    # 检查是否是重复文件错误
    if [[ "$HTTP_CODE" == "422" ]]; then
        ERROR_CODE=$(echo "$JSON_RESPONSE" | jq -r '.errors[0].code // empty' 2>/dev/null)
        if [[ "$ERROR_CODE" == "already_exists" ]]; then
            echo "检测到重复文件，重新检查并删除..."
            # 重新获取资产列表并删除
            ASSETS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/$GITHUB_REPO/releases/$RELEASE_ID/assets")
            EXISTING_ASSET=$(echo "$ASSETS" | jq -r --arg name "$FILE_NAME" '.[] | select(.name==$name) | .id')

            if [[ "$EXISTING_ASSET" != "" && "$EXISTING_ASSET" != "null" ]]; then
                echo "删除重复文件 ID: $EXISTING_ASSET"
                DELETE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
                    -X DELETE \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    "https://api.github.com/repos/$GITHUB_REPO/releases/assets/$EXISTING_ASSET")
                DELETE_CODE=$(echo "$DELETE_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
                if [[ "$DELETE_CODE" == "204" ]]; then
                    echo "重复文件删除成功，重试上传..."
                    ((retry--))  # 不计入重试次数
                    continue
                fi
            fi
        fi
    fi

    echo "❌ 上传失败"
    echo "错误响应: $JSON_RESPONSE"

    if [[ $retry -lt $MAX_RETRIES ]]; then
        echo "等待 5 秒后重试..."
        sleep 5
    fi
done

echo ""
echo "========== 上传失败，已重试 $MAX_RETRIES 次 =========="
exit 1
