#!/bin/bash

################################################################################
# NotionNext 本地构建和推送脚本（Mac）
# 功能：构建AMD64镜像、保存、压缩、通过Git推送到远程仓库
# 使用：./build-and-push.sh
################################################################################

set -e  # 遇到错误立即退出

# ========== 配置区 ==========
IMAGE_NAME="notionnext"
IMAGE_TAG="latest"
BUILD_DIR="$(pwd)"
OUTPUT_DIR="${BUILD_DIR}/docker-images"
KEEP_IMAGES=1  # 保留最新的镜像数量

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 函数定义 ==========

print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

check_prerequisites() {
    print_step "检查前置条件..."

    # 检查是否在Git仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "不在Git仓库中，请先初始化Git仓库"
        exit 1
    fi

    # 检查是否有未提交的重要变更
    if ! git diff --quiet blog.config.js .env 2>/dev/null; then
        print_warning "配置文件有未提交的变更，将一并提交"
    fi

    # 检查Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker未安装或未启动"
        exit 1
    fi

    # 检查Docker Buildx
    if ! docker buildx version &> /dev/null; then
        print_error "Docker Buildx不可用"
        exit 1
    fi

    # 检查文件
    if [ ! -f "package.json" ] || [ ! -f "Dockerfile" ]; then
        print_error "请在NotionNext项目根目录执行此脚本"
        exit 1
    fi

    echo "✅ 前置条件检查通过"
}

build_image() {
    print_step "开始构建Docker镜像（AMD64架构）..."

    # 确保buildx可用
    docker buildx inspect multiarch-builder &> /dev/null || {
        print_step "创建buildx builder..."
        docker buildx create --use --name multiarch-builder
        docker buildx inspect --bootstrap
    }

    # 构建AMD64镜像
    echo "📦 构建目标平台: linux/amd64"
    docker buildx build \
        --platform linux/amd64 \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        --load \
        .

    if [ $? -eq 0 ]; then
        echo "✅ 镜像构建成功"
    else
        print_error "镜像构建失败"
        exit 1
    fi

    # 验证镜像架构
    ARCH=$(docker inspect "${IMAGE_NAME}:${IMAGE_TAG}" | grep -m 1 '"Architecture"' | awk -F'"' '{print $4}')
    echo "🔍 镜像架构: ${ARCH}"

    if [ "${ARCH}" != "amd64" ]; then
        print_error "镜像架构不正确，期望amd64，实际${ARCH}"
        exit 1
    fi
}

save_and_compress() {
    print_step "保存和压缩镜像..."

    # 创建输出目录
    mkdir -p "${OUTPUT_DIR}"

    # 生成文件名（使用固定名称以便Git跟踪）
    TAR_FILE="${OUTPUT_DIR}/${IMAGE_NAME}-latest.tar"
    GZ_FILE="${TAR_FILE}.gz"

    # 保存镜像
    echo "💾 保存镜像到: ${TAR_FILE}"
    docker save -o "${TAR_FILE}" "${IMAGE_NAME}:${IMAGE_TAG}"

    # 压缩（强制覆盖旧文件）
    echo "🗜️  压缩镜像..."
    gzip -f "${TAR_FILE}"

    # 显示文件大小
    SIZE=$(du -h "${GZ_FILE}" | awk '{print $1}')
    echo "✅ 压缩完成，文件大小: ${SIZE}"

    # 创建时间戳文件
    echo "构建时间: $(date '+%Y-%m-%d %H:%M:%S')" > "${OUTPUT_DIR}/build-info.txt"
    echo "镜像名称: ${IMAGE_NAME}:${IMAGE_TAG}" >> "${OUTPUT_DIR}/build-info.txt"
    echo "镜像架构: amd64" >> "${OUTPUT_DIR}/build-info.txt"
    echo "文件大小: ${SIZE}" >> "${OUTPUT_DIR}/build-info.txt"
}

cleanup_old_images() {
    print_step "清理旧的镜像文件..."

    cd "${OUTPUT_DIR}"

    # 统计镜像文件数量
    IMAGE_COUNT=$(ls -1 ${IMAGE_NAME}-*.tar.gz 2>/dev/null | wc -l)

    if [ ${IMAGE_COUNT} -gt ${KEEP_IMAGES} ]; then
        echo "📦 当前有 ${IMAGE_COUNT} 个镜像文件，保留最新 ${KEEP_IMAGES} 个"

        # 删除旧文件（保留最新的）
        ls -t ${IMAGE_NAME}-*.tar.gz 2>/dev/null | tail -n +$((KEEP_IMAGES + 1)) | xargs rm -f

        echo "✅ 清理完成"
    else
        echo "📦 当前只有 ${IMAGE_COUNT} 个镜像文件，无需清理"
    fi

    cd "${BUILD_DIR}"
}

update_gitignore() {
    print_step "更新.gitignore配置..."

    # 确保docker-images目录不被忽略
    if [ -f ".gitignore" ]; then
        # 检查是否已配置
        if grep -q "docker-images" .gitignore; then
            # 确保docker-images目录被跟踪
            sed -i.bak '/^docker-images\/$/d' .gitignore
            sed -i.bak '/^docker-images$/d' .gitignore
            rm -f .gitignore.bak
        fi
    fi

    # 添加配置（忽略备份和临时文件）
    cat >> .gitignore <<EOF

# Docker构建产物（保留镜像文件，忽略其他）
docker-images/*.tar
docker-images/*.log
node_modules/
.next/
EOF

    echo "✅ .gitignore已更新"
}

git_commit_and_push() {
    print_step "提交并推送到Git仓库..."

    # 添加镜像文件和配置
    git add docker-images/${IMAGE_NAME}-latest.tar.gz
    git add docker-images/build-info.txt
    # git add blog.config.js docker-compose.yml Dockerfile .env .gitignore
    git add blog.config.js docker-compose.yml Dockerfile .gitignore
    # git add *.sh

    # 检查是否有变更
    if git diff --cached --quiet; then
        echo "ℹ️  没有文件变更，跳过提交"
        return
    fi

    # 生成提交信息
    COMMIT_MSG="deploy: update NotionNext image and configs - $(date '+%Y-%m-%d %H:%M:%S')"

    echo "📝 提交信息: ${COMMIT_MSG}"
    git commit -m "${COMMIT_MSG}"

    # 推送到远程仓库
    echo "🚀 推送到远程仓库..."

    # 获取当前分支名
    BRANCH=$(git branch --show-current)

    # 推送
    if git push origin "${BRANCH}"; then
        echo "✅ 推送成功到分支: ${BRANCH}"
    else
        print_error "推送失败，请检查网络连接和权限"
        exit 1
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "          🎉 构建和推送完成！"
    echo "=========================================="
    echo "📦 镜像名称: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "🏗️  镜像架构: amd64"
    echo "📁 镜像位置: ${OUTPUT_DIR}/${IMAGE_NAME}-latest.tar.gz"
    echo "🌿 Git分支: $(git branch --show-current)"
    echo ""
    echo "下一步操作："
    echo "  1. SSH登录ECS"
    echo "  2. 执行部署脚本: cd /root/github-repo/NotionNext && ./deploy.sh"
    echo ""
    echo "或者在ECS上一键执行："
    echo "  ssh root@你的ECS-IP 'cd /root/github-repo/NotionNext && ./deploy.sh'"
    echo "=========================================="
}

# ========== 主流程 ==========

main() {
    echo "=========================================="
    echo "   NotionNext 构建和推送脚本"
    echo "   镜像通过Git同步到ECS"
    echo "=========================================="
    echo ""

    # check_prerequisites
    # build_image
    # save_and_compress
    # cleanup_old_images
    # update_gitignore
    git_commit_and_push
    print_summary
}

# 执行主流程
main
