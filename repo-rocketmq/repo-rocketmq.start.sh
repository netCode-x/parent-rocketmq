#!/bin/bash

# ============================================
# RocketMQ + Prometheus + Grafana + Loki + Alloy
# 一键部署脚本（健康检查 + 失败重试）
# ============================================

set -e

PROJECT_DIR="/root/rocketmq-docker"
HOST_IP="192.168.100.110"
APP_PORT="4567"
APP_LOG_DIR="/root/rocketmq-docker/logs/myapp/"

# ============================================
# 容器 / 镜像清单
# ============================================
CONTAINERS=(
  rmq-namesrv1
  rmq-namesrv2
  rmq-broker-master
  rmq-broker-slave
  rmq-dashboard
  rmq-exporter
  rmq-prometheus
  rmq-grafana
  rmq-loki
  rmq-alloy
)

IMAGES=(
  apache/rocketmq:4.9.7
  styletang/rocketmq-console-ng:latest
  apache/rocketmq-exporter:latest
  prom/prometheus:latest
  grafana/grafana:latest
  grafana/loki:latest
  grafana/alloy:latest
)

# ============================================
# 工具函数
# ============================================
# 获取容器状态（不存在返回 not_found，其它返回 docker 的 State：running/exited/restarting/created/paused）
get_container_state() {
    local name="$1"
    local state
    state=$(docker inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || echo "not_found")
    echo "${state}"
}

# ============================================
# 1. 创建目录
# ============================================
mkdir -p ${PROJECT_DIR}
cd ${PROJECT_DIR}

mkdir -p conf
mkdir -p data/broker-master/{logs,store}
mkdir -p data/broker-slave/{logs,store}
mkdir -p data/prometheus
mkdir -p data/grafana
mkdir -p data/loki
mkdir -p logs/rocketmq
mkdir -p ${APP_LOG_DIR}

# ============================================
# 2. 设置目录权限
# ============================================
chown -R 3000:3000 data/broker-master data/broker-slave 2>/dev/null || true
chown -R 65534:65534 data/prometheus 2>/dev/null || true
chown -R 472:472 data/grafana 2>/dev/null || true
chown -R 10001:10001 data/loki 2>/dev/null || true
chmod -R 755 logs 2>/dev/null || true
chmod -R 755 ${APP_LOG_DIR} 2>/dev/null || true

# ============================================
# 3. 生成 broker-master.conf
# ============================================
tee ${PROJECT_DIR}/conf/broker-master.conf << 'EOF'
brokerClusterName = DefaultCluster
brokerName = broker-master
brokerId = 0
deleteWhen = 04
fileReservedTime = 48
brokerRole = ASYNC_MASTER
flushDiskType = ASYNC_FLUSH
brokerIP1 = 192.168.100.110
listenPort = 10911
autoCreateTopicEnable = true
autoCreateSubscriptionGroup = true
storePathRootDir = /home/rocketmq/store
namesrvAddr = rmq-namesrv1:9876;rmq-namesrv2:9876
EOF

# ============================================
# 4. 生成 broker-slave.conf
# ============================================
tee ${PROJECT_DIR}/conf/broker-slave.conf << 'EOF'
brokerClusterName = DefaultCluster
brokerName = broker-slave
brokerId = 1
deleteWhen = 04
fileReservedTime = 48
brokerRole = SLAVE
flushDiskType = ASYNC_FLUSH
brokerIP1 = 192.168.100.110
listenPort = 10912
autoCreateTopicEnable = true
autoCreateSubscriptionGroup = true
storePathRootDir = /home/rocketmq/store
namesrvAddr = rmq-namesrv1:9876;rmq-namesrv2:9876
EOF

# ============================================
# 5. 生成 prometheus.yml
# ============================================
tee ${PROJECT_DIR}/conf/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    env: 'production'
    cluster: 'rocketmq-cluster'

scrape_configs:
  - job_name: 'rocketmq'
    scrape_interval: 15s
    metrics_path: '/metrics'
    static_configs:
      - targets: ['192.168.100.110:5557']
        labels:
          component: 'rocketmq'
          cluster: 'production'

  - job_name: 'spring-boot-app'
    scrape_interval: 15s
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['192.168.100.110:4567']
        labels:
          component: 'application'
          app: 'rocketmq-producer'
          cluster: 'production'
EOF

# ============================================
# 6. 生成 loki-config.yml
# ============================================
tee ${PROJECT_DIR}/conf/loki-config.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  allow_structured_metadata: true
  retention_period: 168h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
EOF

# ============================================
# 7. 生成 config.alloy
#    方案：Docker 自动发现（采集所有容器 stdout）
#         + 文件采集（应用日志、RocketMQ broker 日志）
# ============================================
tee ${PROJECT_DIR}/conf/config.alloy << 'EOF'
// ============================================
// 方式一：Docker 自动发现，采集所有容器的 stdout 日志
// ============================================
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

discovery.relabel "containers" {
  targets = discovery.docker.containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }

  rule {
    source_labels = ["__meta_docker_container_image"]
    target_label  = "image"
  }

  rule {
    source_labels = ["__meta_docker_container_log_stream"]
    target_label  = "stream"
  }
}

loki.source.docker "containers" {
  host             = "unix:///var/run/docker.sock"
  targets          = discovery.relabel.containers.output
  forward_to       = [loki.write.default.receiver]
  refresh_interval = "5s"
}

// ============================================
// 方式二：文件采集
// 采集 Spring Boot 应用日志文件
// ============================================
loki.source.file "myapp" {
  targets = [
    {__path__ = "/var/log/myapp/*.log"},
    {__path__ = "/var/log/myapp/*/*.log"},
  ]
  forward_to = [loki.write.default.receiver]
}

// 采集 RocketMQ Broker Master 日志文件
loki.source.file "rocketmq_master" {
  targets = [
    {__path__ = "/var/log/rocketmq-master/rocketmqlogs/*.log"},
  ]
  forward_to = [loki.write.default.receiver]
}

// 采集 RocketMQ Broker Slave 日志文件
loki.source.file "rocketmq_slave" {
  targets = [
    {__path__ = "/var/log/rocketmq-slave/rocketmqlogs/*.log"},
  ]
  forward_to = [loki.write.default.receiver]
}

// ============================================
// 写入 Loki
// ============================================
loki.write "default" {
  endpoint {
    url = "http://rmq-loki:3100/loki/api/v1/push"
  }
}
EOF

# ============================================
# 8. 生成 docker-compose.yml
# ============================================
tee ${PROJECT_DIR}/docker-compose.yml << EOF
version: '3.8'

networks:
  rocketmq-net:
    driver: bridge

services:

  rmq-namesrv1:
    image: apache/rocketmq:4.9.7
    container_name: rmq-namesrv1
    ports:
      - "9876:9876"
    networks:
      - rocketmq-net
    environment:
      - JAVA_OPT_EXT=-Xms256m -Xmx256m
      - TZ=Asia/Shanghai
    command: sh mqnamesrv
    restart: always

  rmq-namesrv2:
    image: apache/rocketmq:4.9.7
    container_name: rmq-namesrv2
    ports:
      - "9877:9876"
    networks:
      - rocketmq-net
    environment:
      - JAVA_OPT_EXT=-Xms256m -Xmx256m
      - TZ=Asia/Shanghai
    command: sh mqnamesrv
    restart: always

  rmq-broker-master:
    image: apache/rocketmq:4.9.7
    container_name: rmq-broker-master
    ports:
      - "10911:10911"
      - "10909:10909"
      - "10910:10910"
    networks:
      - rocketmq-net
    environment:
      - NAMESRV_ADDR=rmq-namesrv1:9876;rmq-namesrv2:9876
      - JAVA_OPT_EXT=-Xms512m -Xmx512m -Xmn256m -XX:MaxDirectMemorySize=2g -Drocketmq.namesrv.addr=rmq-namesrv1:9876;rmq-namesrv2:9876
      - TZ=Asia/Shanghai
    volumes:
      - ./data/broker-master/logs:/home/rocketmq/logs
      - ./data/broker-master/store:/home/rocketmq/store
      - ./conf/broker-master.conf:/home/rocketmq/conf/broker.conf
    command: sh -c "mkdir -p /home/rocketmq/logs/rocketmqlogs && sh mqbroker -c /home/rocketmq/conf/broker.conf"
    depends_on:
      - rmq-namesrv1
      - rmq-namesrv2
    restart: always

  rmq-broker-slave:
    image: apache/rocketmq:4.9.7
    container_name: rmq-broker-slave
    ports:
      - "10912:10912"
      - "11911:10911"
      - "11909:10909"
      - "11910:10910"
    networks:
      - rocketmq-net
    environment:
      - NAMESRV_ADDR=rmq-namesrv1:9876;rmq-namesrv2:9876
      - JAVA_OPT_EXT=-Xms512m -Xmx512m -Xmn256m -XX:MaxDirectMemorySize=2g -Drocketmq.namesrv.addr=rmq-namesrv1:9876;rmq-namesrv2:9876
      - TZ=Asia/Shanghai
    volumes:
      - ./data/broker-slave/logs:/home/rocketmq/logs
      - ./data/broker-slave/store:/home/rocketmq/store
      - ./conf/broker-slave.conf:/home/rocketmq/conf/broker.conf
    command: sh -c "mkdir -p /home/rocketmq/logs/rocketmqlogs && sh mqbroker -c /home/rocketmq/conf/broker.conf"
    depends_on:
      - rmq-namesrv1
      - rmq-namesrv2
    restart: always

  rmq-dashboard:
    image: styletang/rocketmq-console-ng:latest
    container_name: rmq-dashboard
    ports:
      - "8082:8080"
    networks:
      - rocketmq-net
    environment:
      - JAVA_OPTS=-Drocketmq.namesrv.addr=rmq-namesrv1:9876;rmq-namesrv2:9876 -Dcom.rocketmq.sendMessageWithVIPChannel=false
      - TZ=Asia/Shanghai
    depends_on:
      - rmq-namesrv1
      - rmq-namesrv2
    restart: always

  rmq-exporter:
    image: apache/rocketmq-exporter:latest
    container_name: rmq-exporter
    ports:
      - "5557:5557"
    networks:
      - rocketmq-net
    environment:
      - JAVA_OPTS=-Xms256m -Xmx256m
      - namesrvAddr=rmq-namesrv1:9876;rmq-namesrv2:9876
      - rocketmq.config.namesrvAddr=rmq-namesrv1:9876;rmq-namesrv2:9876
      - TZ=Asia/Shanghai
    depends_on:
      - rmq-namesrv1
      - rmq-namesrv2
    restart: always

  rmq-prometheus:
    image: prom/prometheus:latest
    container_name: rmq-prometheus
    ports:
      - "9090:9090"
    networks:
      - rocketmq-net
    volumes:
      - ./conf/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./data/prometheus:/prometheus
    user: "0:0"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'
    restart: always

  rmq-grafana:
    image: grafana/grafana:latest
    container_name: rmq-grafana
    ports:
      - "3000:3000"
    networks:
      - rocketmq-net
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - TZ=Asia/Shanghai
    volumes:
      - ./data/grafana:/var/lib/grafana
    depends_on:
      - rmq-prometheus
      - rmq-loki
    restart: always

  rmq-loki:
    image: grafana/loki:latest
    container_name: rmq-loki
    ports:
      - "3100:3100"
    networks:
      - rocketmq-net
    volumes:
      - ./conf/loki-config.yml:/etc/loki/local-config.yaml
      - ./data/loki:/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: always

  rmq-alloy:
    image: grafana/alloy:latest
    container_name: rmq-alloy
    ports:
      - "12345:12345"
    networks:
      - rocketmq-net
    volumes:
      - ./conf/config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - \${APP_LOG_DIR}:/var/log/myapp:ro
      - ./data/broker-master/logs:/var/log/rocketmq-master:ro
      - ./data/broker-slave/logs:/var/log/rocketmq-slave:ro
    command:
      - run
      - /etc/alloy/config.alloy
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
    depends_on:
      - rmq-loki
    restart: always
EOF

# ============================================
# 9. 权限验证
# ============================================
echo "=========================================="
echo "权限验证:"
echo "=========================================="
ls -la data/

echo ""
echo "=========================================="
echo "各目录详细信息:"
echo "=========================================="
echo "RocketMQ Broker 目录:"
ls -la data/broker-master/ data/broker-slave/ | grep -E "^d|^total"
echo ""
echo "Prometheus 目录:"
ls -la data/prometheus/
echo ""
echo "Grafana 目录:"
ls -la data/grafana/
echo ""
echo "Loki 目录:"
ls -la data/loki/
echo ""
echo "应用日志目录 (${APP_LOG_DIR}):"
ls -la ${APP_LOG_DIR}/

echo ""
echo "=========================================="
echo "目录结构:"
echo "=========================================="
tree ${PROJECT_DIR} 2>/dev/null || find ${PROJECT_DIR} -type d | sort

# ============================================
# 10. 自动探测 compose 命令
# ============================================
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    echo "错误: 未找到 docker-compose 或 docker compose，请先安装。"
    exit 1
fi

echo ""
echo "使用命令: ${COMPOSE}"

# ============================================
# 10.1 写入 .env
# ============================================
echo "APP_LOG_DIR=${APP_LOG_DIR}" > ${PROJECT_DIR}/.env
echo "已写入 .env: APP_LOG_DIR=${APP_LOG_DIR}"

echo ""
echo "校验 docker-compose.yml 语法..."
export APP_LOG_DIR
${COMPOSE} config >/dev/null
if [ $? -ne 0 ]; then
    echo "错误: docker-compose.yml 语法有问题，请检查。"
    exit 1
fi
echo "语法检查通过。"

# ============================================
# 11. 启动所有服务
# ============================================
echo ""
echo "=========================================="
echo "步骤 11: 启动/更新服务"
echo "=========================================="

${COMPOSE} up -d --remove-orphans

echo "等待服务启动（30s）..."
sleep 30

${COMPOSE} ps

# ============================================
# 12. 健康检查 + 失败重试
# ============================================
echo ""
echo "=========================================="
echo "步骤 12: 容器健康检查与失败重试"
echo "=========================================="

check_and_restart() {
    local cname="$1"
    local state
    state=$(get_container_state "${cname}")
    if [ "${state}" = "running" ]; then
        echo "✅ [${cname}] running"
        return 0
    else
        echo "⚠️  [${cname}] 状态异常: ${state}"
        return 1
    fi
}

# 第一轮检查
FAILED_CONTAINERS=()
for cname in "${CONTAINERS[@]}"; do
    if ! check_and_restart "${cname}"; then
        FAILED_CONTAINERS+=("${cname}")
    fi
done

# 对异常容器进行重试
if [ ${#FAILED_CONTAINERS[@]} -gt 0 ]; then
    echo ""
    echo "---- 尝试重启异常容器: ${FAILED_CONTAINERS[*]} ----"
    for cname in "${FAILED_CONTAINERS[@]}"; do
        state=$(get_container_state "${cname}")
        if [ "${state}" = "not_found" ]; then
            echo ">>> [${cname}] 容器不存在，重建..."
            ${COMPOSE} up -d --no-deps "${cname}" || true
        else
            echo ">>> [${cname}] 尝试 docker restart..."
            docker restart "${cname}" || true
        fi
    done

    echo "等待 20s 后二次检查..."
    sleep 20

    STILL_FAILED=()
    for cname in "${FAILED_CONTAINERS[@]}"; do
        if ! check_and_restart "${cname}"; then
            STILL_FAILED+=("${cname}")
        fi
    done

    if [ ${#STILL_FAILED[@]} -gt 0 ]; then
        echo ""
        echo "⚠️  以下容器重启后仍未恢复: ${STILL_FAILED[*]}"
        echo "---- 尝试强制重建这些容器 ----"
        for cname in "${STILL_FAILED[@]}"; do
            echo ">>> 强制重建 [${cname}] ..."
            docker rm -f "${cname}" >/dev/null 2>&1 || true
            ${COMPOSE} up -d --no-deps --force-recreate "${cname}" || true
        done
        echo "等待 20s 后最终检查..."
        sleep 20

        FINAL_FAILED=()
        for cname in "${STILL_FAILED[@]}"; do
            if ! check_and_restart "${cname}"; then
                FINAL_FAILED+=("${cname}")
            fi
        done

        if [ ${#FINAL_FAILED[@]} -gt 0 ]; then
            echo ""
            echo "❌ 以下容器最终仍未启动成功: ${FINAL_FAILED[*]}"
            echo "请手动查看日志："
            for cname in "${FINAL_FAILED[@]}"; do
                echo "  docker logs ${cname} --tail 100"
            done
        else
            echo "✅ 所有异常容器已恢复。"
        fi
    else
        echo "✅ 所有异常容器已通过 restart 恢复。"
    fi
else
    echo "✅ 所有容器首次检查均正常。"
fi

# ============================================
# 13. 集群状态
# ============================================
echo ""
echo "查看集群状态"
docker exec rmq-namesrv1 sh -c "sh mqadmin clusterList -n localhost:9876" || true

# ============================================
# 14. 验证 Loki
# ============================================
echo ""
echo "验证 Loki 状态..."
sleep 5
if curl -s http://${HOST_IP}:3100/ready | grep -q "ready"; then
    echo "✅ Loki 已就绪"
else
    echo "⚠️  Loki 未就绪，请查看日志: docker logs rmq-loki --tail 50"
fi

# ============================================
# 15. 验证 Alloy
# ============================================
echo ""
echo "验证 Alloy 挂载与采集源..."

echo "--- docker.sock ---"
if docker exec rmq-alloy ls -l /var/run/docker.sock >/dev/null 2>&1; then
    echo "✅ Alloy 已挂载 docker.sock"
else
    echo "⚠️  Alloy 未挂载 docker.sock，Docker 自动发现将失效"
fi

echo "--- 应用日志目录 /var/log/myapp ---"
if docker exec rmq-alloy ls /var/log/myapp/ >/dev/null 2>&1; then
    echo "✅ Alloy 可读取 /var/log/myapp"
    docker exec rmq-alloy ls -lh /var/log/myapp/ || true
else
    echo "⚠️  Alloy 暂时读不到 /var/log/myapp（可能应用还没开始写日志）"
fi

echo "--- RocketMQ Master 日志目录 /var/log/rocketmq-master ---"
if docker exec rmq-alloy ls /var/log/rocketmq-master/rocketmqlogs/ >/dev/null 2>&1; then
    echo "✅ Alloy 可读取 Master 日志"
    docker exec rmq-alloy ls -lh /var/log/rocketmq-master/rocketmqlogs/ || true
else
    echo "⚠️  Alloy 暂时读不到 Master 日志（可能 Broker 还没开始写日志）"
fi

echo "--- RocketMQ Slave 日志目录 /var/log/rocketmq-slave ---"
if docker exec rmq-alloy ls /var/log/rocketmq-slave/rocketmqlogs/ >/dev/null 2>&1; then
    echo "✅ Alloy 可读取 Slave 日志"
    docker exec rmq-alloy ls -lh /var/log/rocketmq-slave/rocketmqlogs/ || true
else
    echo "⚠️  Alloy 暂时读不到 Slave 日志（可能 Broker 还没开始写日志）"
fi

echo ""
echo "--- Loki 已采集的标签 ---"
curl -s http://${HOST_IP}:3100/loki/api/v1/labels || true
echo ""


docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="
echo ""
echo "📊 访问地址："
echo "  RocketMQ 控制台: http://${HOST_IP}:8082"
echo "  Prometheus:      http://${HOST_IP}:9090"
echo "  Grafana:         http://${HOST_IP}:3000 (admin/admin)"
echo "  Alloy UI:        http://${HOST_IP}:12345"
echo "  Loki:            http://${HOST_IP}:3100"
echo ""
echo "📌 Grafana 添加 Loki 数据源时，URL 填："
echo "  http://rmq-loki:3100"
echo ""
echo "📌 Grafana Explore 常用 LogQL："
echo '  {container="repo-rocketmq"}'
echo '  {container=~"rmq-.*"}'
echo '  {filename=~"/var/log/myapp/.*"}'
echo ""
echo "📝 常用命令："
echo "  查看集群状态: docker exec rmq-namesrv1 sh -c 'sh mqadmin clusterList -n localhost:9876'"
echo "  查看 Topic:   docker exec rmq-namesrv1 sh -c 'sh mqadmin topicList -n localhost:9876'"
echo "  发送测试消息: docker exec rmq-broker-master sh -c 'sh mqadmin sendMessage -n rmq-namesrv1:9876 -t TestTopic -p hello'"
echo "  查看 Alloy:   docker logs rmq-alloy --tail 50"
echo "  查看 Loki:    docker logs rmq-loki --tail 50"
echo "  查看应用日志: ls -lh ${APP_LOG_DIR}/"
echo ""