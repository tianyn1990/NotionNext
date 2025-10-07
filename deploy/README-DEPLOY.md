# NotionNext 自动化部署脚本

本项目包含三个自动化部署脚本，实现从本地构建到ECS部署的全流程自动化。

## 📁 脚本清单

| 脚本 | 位置 | 功能 |
|------|------|------|
| `build-and-push.sh` | Mac本地 | 构建AMD64镜像 → 保存压缩 → Git推送 |
| `deploy.sh` | ECS服务器 | Git拉取 → 停止旧服务 → 加载镜像 → 启动服务 |
| `quick-deploy.sh` | Mac本地 | 一键执行：构建+推送+SSH部署 |

## 🚀 快速开始

### 第一次使用（初始化）

#### 1. 在本地Mac配置

```bash
# 进入NotionNext项目目录
cd /Users/hetao/Documents/github/knowledge/notion_next/NotionNext

# 赋予脚本执行权限
chmod +x build-and-push.sh deploy.sh quick-deploy.sh

# 配置quick-deploy.sh中的ECS信息
vim quick-deploy.sh
# 修改以下配置：
# ECS_HOST="你的ECS-IP"
# ECS_USER="root"
# ECS_PORT="22"
# ECS_DEPLOY_DIR="/root/github-repo/NotionNext"
```

#### 2. 在ECS服务器配置

```bash
# SSH登录ECS
ssh root@你的ECS-IP

# 克隆或进入NotionNext目录
cd /root/github-repo/NotionNext

# 确保.env文件配置正确
cat > .env <<EOF
NOTION_PAGE_ID=你的Notion页面ID
NEXT_PUBLIC_THEME=hexo
NEXT_PUBLIC_LANG=zh-CN
EOF

# 赋予deploy.sh执行权限
chmod +x deploy.sh
```

### 日常部署流程

#### 方式A：一键部署（推荐）⭐⭐⭐⭐⭐

```bash
# 在本地Mac执行
cd /Users/hetao/Documents/github/knowledge/notion_next/NotionNext
./quick-deploy.sh
```

**自动完成：**
1. ✅ 构建AMD64架构镜像
2. ✅ 保存并压缩镜像文件
3. ✅ 提交并推送到Git仓库
4. ✅ SSH到ECS服务器
5. ✅ 拉取最新代码和镜像
6. ✅ 停止旧服务
7. ✅ 加载新镜像
8. ✅ 启动新服务
9. ✅ 验证部署结果

#### 方式B：分步部署

**步骤1：本地构建和推送**
```bash
# 在本地Mac执行
cd /Users/hetao/Documents/github/knowledge/notion_next/NotionNext
./build-and-push.sh
```

**步骤2：ECS部署**
```bash
# SSH登录ECS
ssh root@你的ECS-IP

# 执行部署
cd /root/github-repo/NotionNext
./deploy.sh
```

**步骤3（可选）：远程一键部署**
```bash
# 在本地Mac远程执行ECS部署
ssh root@你的ECS-IP 'cd /root/github-repo/NotionNext && ./deploy.sh -y'
```

## 📋 脚本详细说明

### build-and-push.sh（本地Mac）

**功能：**
- 构建适用于ECS的AMD64架构Docker镜像
- 保存镜像为tar.gz文件
- 清理旧镜像文件（保留最新1个）
- 提交并推送到Git仓库

**使用：**
```bash
./build-and-push.sh
```

**输出：**
- `docker-images/notionnext-latest.tar.gz` - 镜像文件
- `docker-images/build-info.txt` - 构建信息

**注意事项：**
- 确保本地Docker Desktop正在运行
- 确保Git仓库配置正确
- 镜像文件约300-500MB，Git推送可能需要几分钟

### deploy.sh（ECS服务器）

**功能：**
- 从Git拉取最新代码和镜像
- 停止旧Docker容器
- 清理旧镜像
- 加载新镜像
- 启动新服务
- 验证部署结果

**使用：**
```bash
# 交互模式（会询问是否继续）
./deploy.sh

# 自动确认模式（无需交互）
./deploy.sh -y
```

**回滚操作：**
```bash
# 查看历史提交
git log --oneline

# 回滚到指定版本
git reset --hard <commit-id>

# 重新部署
./deploy.sh -y
```

### quick-deploy.sh（本地Mac）

**功能：**
- 自动执行build-and-push.sh
- 自动SSH到ECS执行deploy.sh

**使用：**
```bash
./quick-deploy.sh
```

**前置条件：**
- 配置好SSH免密登录（推荐）
- 或确保可以SSH密码登录

## 🛠️ 常见操作

### 仅更新配置文件

如果只修改了`blog.config.js`或`.env`，不需要重新构建镜像：

```bash
# 在本地提交配置
git add blog.config.js .env
git commit -m "update: 更新配置"
git push

# 在ECS上拉取并重启
ssh root@你的ECS-IP
cd /root/github-repo/NotionNext
git pull
docker compose restart
```

### 查看服务状态

```bash
# 在ECS上执行
docker compose ps
docker compose logs -f
```

### 停止服务

```bash
# 在ECS上执行
docker compose stop
```

### 完全清理重新部署

```bash
# 在ECS上执行
docker compose down
docker rmi notionnext:latest
./deploy.sh -y
```

## 🔧 故障排查

### 问题1：本地构建失败

```bash
# 检查Docker是否运行
docker ps

# 检查Docker Buildx
docker buildx version

# 重新创建builder
docker buildx create --use --name multiarch-builder
docker buildx inspect --bootstrap

# 重新构建
./build-and-push.sh
```

### 问题2：Git推送失败

```bash
# 检查Git配置
git remote -v

# 检查网络连接
ping github.com

# 强制推送（谨慎使用）
git push -f origin main
```

### 问题3：ECS部署失败

```bash
# 查看详细日志
docker compose logs notionnext

# 检查镜像是否加载成功
docker images | grep notionnext

# 检查.env配置
cat .env

# 手动验证镜像
docker run -it --rm notionnext:latest sh
```

### 问题4：服务无法访问

```bash
# 检查容器状态
docker compose ps

# 检查端口监听
netstat -tulnp | grep 3000

# 检查防火墙
ufw status

# 检查阿里云安全组
# 登录阿里云控制台检查3000端口是否开放
```

## 📊 目录结构

```
NotionNext/
├── docker-images/              # 镜像文件目录
│   ├── notionnext-latest.tar.gz
│   └── build-info.txt
├── build-and-push.sh          # 本地构建推送脚本
├── deploy.sh                  # ECS部署脚本
├── quick-deploy.sh            # 一键部署脚本
├── docker-compose.yml         # Docker Compose配置
├── Dockerfile                 # Docker镜像定义
├── .env                       # 环境变量（不提交到Git）
├── blog.config.js             # NotionNext配置
└── README-DEPLOY.md           # 本说明文档
```

## ⚙️ 自定义配置

### 保留更多历史镜像

编辑`build-and-push.sh`：
```bash
KEEP_IMAGES=3  # 保留最新3个镜像
```

### 修改镜像名称

编辑所有脚本中的：
```bash
IMAGE_NAME="notionnext"
IMAGE_TAG="latest"
```

### 使用不同的Git分支

脚本会自动检测当前分支，如需切换：
```bash
git checkout develop
./build-and-push.sh
```

## 🔐 安全建议

1. **不要提交.env文件到Git**
   - `.gitignore`已配置忽略`.env`
   - 敏感信息单独在ECS上配置

2. **配置SSH密钥登录**
   ```bash
   # 本地生成密钥
   ssh-keygen -t rsa -b 4096

   # 复制公钥到ECS
   ssh-copy-id root@你的ECS-IP
   ```

3. **限制Git仓库访问权限**
   - 使用私有仓库
   - 配置访问令牌

## 📝 更新日志

- 2024-10-07: 初始版本
  - 支持AMD64镜像构建
  - 支持Git同步镜像文件
  - 支持一键部署

## 🙋 常见问题

**Q: 镜像文件太大，Git推送很慢怎么办？**

A: 镜像压缩后约300-500MB，首次推送较慢。后续更新Git只会推送差异部分。也可以考虑：
- 使用阿里云代码仓库（国内速度快）
- 使用Git LFS管理大文件
- 配置.gitattributes

**Q: 能否不通过Git同步镜像？**

A: 可以，修改脚本使用scp直接上传。参考之前的`scp方案`。

**Q: 如何配置HTTPS？**

A: 参考主文档的Nginx反向代理章节，配置SSL证书。

**Q: 支持多环境部署吗（开发/测试/生产）？**

A: 可以通过不同的`.env`文件和Git分支实现：
```bash
# 开发环境
git checkout develop
./quick-deploy.sh

# 生产环境
git checkout main
./quick-deploy.sh
```

## 📚 相关文档

- [NotionNext部署完整指南](./NotionNext-阿里云ECS-Docker部署完整指南.md)
- [NotionNext官方文档](https://docs.tangly1024.com)
- [Docker官方文档](https://docs.docker.com)

---

**作者：** Claude Code AI Assistant
**更新时间：** 2024-10-07
