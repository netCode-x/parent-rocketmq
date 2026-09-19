#!/bin/bash
set -e

# ===== 配置变量 =====
APP_NAME="repo-rocketmq"
PORT=4567
HOST_IP="192.168.100.110"
DEPLOY_DIR="/root/deploy/jdk21-app"
# ===================

mkdir -p "${DEPLOY_DIR}"
cd "${DEPLOY_DIR}"

echo "===== 开始部署 ${APP_NAME} ====="
echo "脚本位置: $(dirname $(readlink -f $0))"
echo "工作目录: $(pwd)"

# 自动匹配 JAR（排除 .original）
JAR_FILE=$(ls repo-rocketmq-*.jar 2>/dev/null | grep -v '\.original$' | head -n1)
if [ -z "${JAR_FILE}" ] || [ ! -f "${JAR_FILE}" ]; then
    echo "错误: 未找到 JAR 文件 (repo-rocketmq-*.jar)！"
    exit 1
fi
echo "使用 JAR: ${JAR_FILE}"

# 生成 Dockerfile
echo "0. 生成 Dockerfile..."
cat > Dockerfile <<EOF
FROM openjdk:21-jdk-slim
LABEL maintainer="yangkaihu@yeah.net"
WORKDIR /app
COPY ${JAR_FILE} app.jar
EXPOSE ${PORT}
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF

# 停旧容器 / 删旧镜像
echo "1. 停止并删除旧容器..."
docker stop ${APP_NAME} 2>/dev/null || true
docker rm   ${APP_NAME} 2>/dev/null || true

echo "2. 删除旧镜像..."
docker rmi ${APP_NAME}:latest 2>/dev/null || true

# 构建
echo "3. 构建新镜像..."
docker build -t ${APP_NAME}:latest . || { echo "镜像构建失败"; exit 1; }

# 启动
echo "4. 启动新容器..."
if docker run -d \
    --name ${APP_NAME} \
    -p ${PORT}:${PORT} \
    -e TZ="Asia/Shanghai" \
    --restart=always \
    ${APP_NAME}:latest; then
    echo "===== 部署完成 ====="
    echo "应用访问地址: http://${HOST_IP}:${PORT}"
    echo "查看日志: docker logs ${APP_NAME} -f"
else
    echo "===== 部署失败 ====="
    exit 1
fi

# 等待 3 秒后看日志
sleep 3
echo "----- 最近 30 行日志 -----"
docker logs ${APP_NAME} --tail 30