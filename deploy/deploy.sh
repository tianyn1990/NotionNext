#!/bin/bash

################################################################################
# NotionNext ECS部署脚本
# 功能：从Git拉取最新镜像和配置，停止旧服务，加载新镜像，启动服务
# 使用：./deploy.sh
################################################################################

set -e  # 遇到错误立即退出

# ========== 配置区 ==========
IMAGE_NAME="notionnext"
IMAGE_TAG="latest"
PROJECT_DIR="$(pwd)"
IMAGE_DIR="${PROJECT_DIR}/docker-images"
CONTAINER_NAME="notionnext"

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

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

check_prerequisites() {
    print_step "检查前置条件..."

    # 检查是否在Git仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "不在Git仓库中"
        exit 1
    fi

    # 检查Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker未安装或未启动"
        exit 1
    fi

    # 检查docker compose
    if ! docker compose version &> /dev/null; then
        print_error "docker compose不可用"
        exit 1
    fi

    # 检查必要文件
    if [ ! -f "docker-compose.yml" ]; then
        print_error "找不到docker-compose.yml文件"
        exit 1
    fi

    if [ ! -f ".env" ]; then
        print_warning ".env文件不存在，请确保环境变量配置正确"
    fi

    echo "✅ 前置条件检查通过"
}

show_current_status() {
    print_step "当前服务状态..."

    if docker ps -a | grep -q "${CONTAINER_NAME}"; then
        docker ps -a | grep "${CONTAINER_NAME}"
    else
        echo "容器不存在或未运行"
    fi

    echo ""
    if docker images | grep -q "${IMAGE_NAME}"; then
        echo "当前镜像："
        docker images | grep "${IMAGE_NAME}"
    else
        echo "未找到${IMAGE_NAME}镜像"
    fi
}

git_pull_updates() {
    print_step "从Git拉取最新更新..."

    # 保存当前工作状态
    if ! git diff --quiet; then
        print_warning "检测到本地未提交的变更，将stash保存"
        git stash push -m "auto-stash before deploy $(date '+%Y-%m-%d %H:%M:%S')"
        STASHED=true
    fi

    # 拉取最新代码
    BRANCH=$(git branch --show-current)
    echo "📥 拉取分支: ${BRANCH}"

    if git pull origin "${BRANCH}"; then
        echo "✅ 拉取成功"
    else
        print_error "拉取失败，请检查网络连接"
        exit 1
    fi

    # 恢复stash（如果有）
    if [ "${STASHED}" = true ]; then
        if git stash pop; then
            echo "✅ 已恢复本地变更"
        else
            print_warning "恢复本地变更失败，请手动处理"
        fi
    fi

    # 显示拉取的信息
    echo ""
    print_info "最新提交："
    git log -1 --oneline
}

stop_old_service() {
    print_step "停止旧服务..."

    if docker ps | grep -q "${CONTAINER_NAME}"; then
        echo "🛑 停止容器: ${CONTAINER_NAME}"
        docker compose down

        echo "✅ 服务已停止"
    else
        echo "ℹ️  容器未运行，跳过停止步骤"
    fi
}

cleanup_old_images() {
    print_step "清理旧镜像..."

    # 查找悬空镜像
    DANGLING=$(docker images -f "dangling=true" -q)

    if [ -n "${DANGLING}" ]; then
        echo "🗑️  清理悬空镜像..."
        docker rmi ${DANGLING} 2>/dev/null || true
        echo "✅ 清理完成"
    else
        echo "ℹ️  没有需要清理的镜像"
    fi

    # 显示当前镜像
    echo ""
    echo "当前${IMAGE_NAME}镜像："
    docker images | grep -E "REPOSITORY|${IMAGE_NAME}" || echo "未找到镜像"
}

load_new_image() {
    print_step "加载新镜像..."

    IMAGE_FILE="${IMAGE_DIR}/${IMAGE_NAME}-latest.tar.gz"

    # 检查镜像文件是否存在
    if [ ! -f "${IMAGE_FILE}" ]; then
        print_error "镜像文件不存在: ${IMAGE_FILE}"
        print_error "请先在本地执行 build-and-push.sh 构建并推送镜像"
        exit 1
    fi

    # 显示镜像信息
    if [ -f "${IMAGE_DIR}/build-info.txt" ]; then
        echo ""
        echo "📋 镜像信息："
        cat "${IMAGE_DIR}/build-info.txt"
        echo ""
    fi

    # 删除旧镜像（如果存在）
    if docker images | grep -q "^${IMAGE_NAME}.*${IMAGE_TAG}"; then
        echo "🗑️  删除旧镜像..."
        docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
    fi

    # 解压并加载新镜像
    echo "📦 加载镜像: ${IMAGE_FILE}"
    SIZE=$(du -h "${IMAGE_FILE}" | awk '{print $1}')
    echo "文件大小: ${SIZE}"

    gunzip -c "${IMAGE_FILE}" | docker load

    if [ $? -eq 0 ]; then
        echo "✅ 镜像加载成功"
    else
        print_error "镜像加载失败"
        exit 1
    fi

    # 验证镜像
    if docker images | grep -q "^${IMAGE_NAME}.*${IMAGE_TAG}"; then
        echo "✅ 镜像验证通过"
        docker images | grep "${IMAGE_NAME}"
    else
        print_error "镜像验证失败"
        exit 1
    fi
}

start_new_service() {
    print_step "启动新服务..."

    # 确保配置文件存在
    if [ ! -f ".env" ]; then
        print_error ".env文件不存在，无法启动服务"
        exit 1
    fi

    # 检查NOTION_PAGE_ID是否配置
    if ! grep -q "NOTION_PAGE_ID=" .env || grep -q "NOTION_PAGE_ID=$" .env; then
        print_error "NOTION_PAGE_ID未配置，请编辑.env文件"
        exit 1
    fi

    echo "🚀 启动服务..."
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo "✅ 服务启动成功"
    else
        print_error "服务启动失败"
        exit 1
    fi

    # 等待容器启动
    echo "⏳ 等待服务启动..."
    sleep 5
}

verify_deployment() {
    print_step "验证部署结果..."

    # 检查容器状态
    echo "📊 容器状态："
    docker compose ps

    # 检查容器健康状态
    echo ""
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")

    if [ "${HEALTH_STATUS}" = "healthy" ]; then
        echo "✅ 容器健康状态: ${HEALTH_STATUS}"
    elif [ "${HEALTH_STATUS}" = "starting" ]; then
        echo "⏳ 容器健康状态: ${HEALTH_STATUS}（正在启动）"
    else
        echo "⚠️  容器健康状态: ${HEALTH_STATUS}"
    fi

    # 检查端口监听
    echo ""
    if docker exec "${CONTAINER_NAME}" netstat -tulnp 2>/dev/null | grep -q ":3000"; then
        echo "✅ 端口3000正在监听"
    else
        print_warning "端口3000未监听，请查看日志"
    fi

    # 测试HTTP访问
    echo ""
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200"; then
        echo "✅ HTTP访问测试通过"
    else
        print_warning "HTTP访问测试失败，请查看日志"
    fi

    # 显示最新日志
    echo ""
    echo "📝 最新日志（最后20行）："
    docker compose logs --tail=20 notionnext
}

show_access_info() {
    # 获取ECS公网IP
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "未知")

    echo ""
    echo "=========================================="
    echo "          🎉 部署完成！"
    echo "=========================================="
    echo "📦 镜像: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "🏗️  架构: amd64"
    echo "🌐 访问地址:"
    echo "   - http://localhost:3000"
    echo "   - http://${PUBLIC_IP}:3000"
    echo ""
    echo "📋 常用命令:"
    echo "   查看日志: docker compose logs -f"
    echo "   重启服务: docker compose restart"
    echo "   停止服务: docker compose stop"
    echo "   查看状态: docker compose ps"
    echo ""
    echo "🔧 故障排查:"
    echo "   如遇问题，请查看日志: docker compose logs notionnext"
    echo "=========================================="
}

show_rollback_info() {
    echo ""
    echo "⚠️  如需回滚到上一个版本："
    echo "   1. git log --oneline"
    echo "   2. git reset --hard <commit-id>"
    echo "   3. ./deploy.sh"
}

# ========== 主流程 ==========

main() {
    echo "=========================================="
    echo "   NotionNext ECS 部署脚本"
    echo "   从Git拉取镜像并自动部署"
    echo "=========================================="
    echo ""

    check_prerequisites
    show_current_status
    echo ""

    # 询问是否继续
    read -p "是否继续部署？[y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ 部署已取消"
        exit 0
    fi

    git_pull_updates
    stop_old_service
    cleanup_old_images
    load_new_image
    start_new_service
    verify_deployment
    show_access_info
    show_rollback_info
}

# 支持免交互模式
if [ "$1" = "-y" ] || [ "$1" = "--yes" ]; then
    # 自动确认模式
    REPLY="y"
fi

# 执行主流程
main
