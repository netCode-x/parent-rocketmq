#!/bin/bash

# ========== 可配置变量 ==========
OLLAMA_CONTAINER="ollama"
OLLAMA_IMAGE="ollama/ollama"
OLLAMA_PORT=11434
OLLAMA_VOLUME="ollama_data"
MODEL_NAME="deepseek-r1:1.5b"          # 可改为其他模型，如 llama3.2, qwen2.5 等
OPEN_WEBUI_CONTAINER="open-webui"
OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
OPEN_WEBUI_PORT=3000
NETWORK_NAME="ollama-net"
# ================================

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Ollama Docker 部署脚本 ===${NC}"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误：未找到 docker 命令，请先安装 Docker。${NC}"
    exit 1
fi

# 创建 Docker 网络（如果不存在）
if ! docker network inspect "$NETWORK_NAME" &> /dev/null; then
    echo "创建 Docker 网络 $NETWORK_NAME ..."
    docker network create "$NETWORK_NAME"
else
    echo "Docker 网络 $NETWORK_NAME 已存在。"
fi

# ---------- 1. 拉取 Ollama 镜像 ----------
echo "拉取 Ollama 镜像 $OLLAMA_IMAGE ..."
docker pull "$OLLAMA_IMAGE"

# ---------- 2. 启动 Ollama 容器 ----------
if docker ps -a --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
    echo "容器 $OLLAMA_CONTAINER 已存在。"
    if docker ps --format '{{.Names}}' | grep -q "^${OLLAMA_CONTAINER}$"; then
        echo "容器正在运行。"
    else
        echo "启动已存在的容器..."
        docker start "$OLLAMA_CONTAINER"
    fi
else
    echo "创建并启动 Ollama 容器..."
    docker run -d \
      --name "$OLLAMA_CONTAINER" \
      --network "$NETWORK_NAME" \
      -p "$OLLAMA_PORT:$OLLAMA_PORT" \
      -v "$OLLAMA_VOLUME:/root/.ollama" \
      -e OLLAMA_HOST=0.0.0.0 \
      --restart unless-stopped \
      "$OLLAMA_IMAGE"
fi

# ---------- 3. 验证 Ollama 服务 ----------
echo "等待 Ollama 服务启动..."
sleep 5

echo "验证 Ollama API ..."
if curl -s "http://localhost:$OLLAMA_PORT/api/tags" > /dev/null; then
    echo -e "${GREEN}Ollama API 响应正常。${NC}"
else
    echo -e "${YELLOW}警告：Ollama API 无响应，请检查容器日志：docker logs $OLLAMA_CONTAINER${NC}"
fi

# ---------- 4. 拉取模型 ----------
echo "拉取模型 $MODEL_NAME ..."
if docker exec "$OLLAMA_CONTAINER" ollama pull "$MODEL_NAME"; then
    echo -e "${GREEN}模型 $MODEL_NAME 拉取成功。${NC}"
else
    echo -e "${YELLOW}模型拉取可能失败，请检查网络或模型名称。${NC}"
fi

# 提示如何运行模型
echo -e "${GREEN}你可以使用以下命令与模型交互：${NC}"
echo "  docker exec -it $OLLAMA_CONTAINER ollama run $MODEL_NAME"
echo "退出对话按 Ctrl + D"

# ---------- 5. 可选安装 Open WebUI ----------
read -p "是否安装 Open WebUI 图形界面？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "拉取 Open WebUI 镜像..."
    docker pull "$OPEN_WEBUI_IMAGE"

    if docker ps -a --format '{{.Names}}' | grep -q "^${OPEN_WEBUI_CONTAINER}$"; then
        echo "容器 $OPEN_WEBUI_CONTAINER 已存在。"
        if docker ps --format '{{.Names}}' | grep -q "^${OPEN_WEBUI_CONTAINER}$"; then
            echo "容器正在运行。"
        else
            echo "启动已存在的容器..."
            docker start "$OPEN_WEBUI_CONTAINER"
        fi
    else
        echo "创建并启动 Open WebUI 容器..."
        docker run -d \
          --name "$OPEN_WEBUI_CONTAINER" \
          --network "$NETWORK_NAME" \
          -p "$OPEN_WEBUI_PORT:8080" \
          -v open-webui:/app/backend/data \
          -e OLLAMA_BASE_URL="http://$OLLAMA_CONTAINER:$OLLAMA_PORT" \
          --restart always \
          "$OPEN_WEBUI_IMAGE"
    fi

    echo -e "${GREEN}Open WebUI 已启动。${NC}"
    echo "请等待 10-15 秒，然后访问：http://<本机IP>:$OPEN_WEBUI_PORT"
    echo "首次访问需要注册管理员账号。"
else
    echo "跳过 Open WebUI 安装。"
fi

echo -e "${GREEN}部署完成！${NC}"