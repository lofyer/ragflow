# RAGFlow 多实例部署方案

## 概述

RAGFlow 架构设计支持多实例水平扩展部署，所有状态均外部化存储。

> **官方支持状态**: RAGFlow 官方提供了 Helm Chart 用于 Kubernetes 部署，支持外部服务连接和多实例扩展。参考 `helm/` 目录。

## 架构图

```
                      ┌─────────────────┐
                      │  Load Balancer  │
                      │  (Nginx/HAProxy)│
                      └────────┬────────┘
             ┌─────────────────┼─────────────────┐
             ▼                 ▼                 ▼
      ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
      │ ragflow-svr │   │ ragflow-svr │   │ ragflow-svr │
      │   :9380     │   │   :9380     │   │   :9380     │
      └─────────────┘   └─────────────┘   └─────────────┘
             │                 │                 │
             └─────────────────┼─────────────────┘
                               ▼
      ┌──────────┬──────────┬──────────┬──────────┐
      │  MySQL   │  Redis   │ ES/Infin │  MinIO   │
      │  :3306   │  :6379   │  :9200   │  :9000   │
      └──────────┴──────────┴──────────┴──────────┘
                               ▲
             ┌─────────────────┼─────────────────┐
             │                 │                 │
      ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
      │task_executor│   │task_executor│   │task_executor│
      └─────────────┘   └─────────────┘   └─────────────┘
```

## 已支持多实例的特性

### 1. 共享存储架构
- **MySQL**: 用户数据、会话、知识库元数据
- **Redis**: 分布式锁、任务队列、缓存
- **Elasticsearch/Infinity**: 文档索引和检索
- **MinIO**: 文件对象存储

### 2. 分布式锁机制
关键后台任务已使用 `RedisDistributedLock` 保护：
- `update_progress()` - 文档处理进度更新
- `graphrag_task_{kb_id}` - GraphRAG 任务
- `clean_task_executor` - 任务清理

### 3. 无状态 API
- HTTP API 本身无状态
- 会话数据存储在 MySQL
- 认证 Token 通过数据库验证

## 部署注意事项

### 1. 负载均衡器配置

#### Nginx 示例配置
```nginx
upstream ragflow_servers {
    least_conn;
    server ragflow-server-1:9380;
    server ragflow-server-2:9380;
    server ragflow-server-3:9380;
}

server {
    listen 80;
    
    # 流式响应超时配置
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
    proxy_connect_timeout 60s;
    
    # SSE 支持
    proxy_buffering off;
    proxy_cache off;
    
    location / {
        proxy_pass http://ragflow_servers;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # 流式接口特殊处理
    location ~ ^/api/v1/.*/completions {
        proxy_pass http://ragflow_servers;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
    }
}
```

### 2. 流式响应处理
- `/completions` 等 SSE 接口需要禁用代理缓冲
- 适当延长超时时间（建议 300s+）
- 如遇问题可配置会话亲和性（sticky session）

### 3. task_executor 独立扩展
- 文档处理任务通过 Redis 队列分发
- 可独立于 ragflow-server 扩展
- 建议根据文档处理负载调整实例数

## Docker Compose 多实例示例

```yaml
version: '3.8'

services:
  ragflow-server-1:
    image: infiniflow/ragflow:latest
    environment:
      - MYSQL_HOST=mysql
      - REDIS_HOST=redis
      - ES_HOST=es01
      - MINIO_HOST=minio
    depends_on:
      - mysql
      - redis
      - es01
      - minio

  ragflow-server-2:
    image: infiniflow/ragflow:latest
    environment:
      - MYSQL_HOST=mysql
      - REDIS_HOST=redis
      - ES_HOST=es01
      - MINIO_HOST=minio
    depends_on:
      - mysql
      - redis
      - es01
      - minio

  nginx:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - ragflow-server-1
      - ragflow-server-2
```

## Kubernetes 部署 (官方 Helm Chart)

RAGFlow 官方提供 Helm Chart，支持 Kubernetes 部署和外部服务连接。

### 安装
```bash
helm upgrade --install ragflow ./helm \
  --namespace ragflow --create-namespace
```

### 使用外部服务
```yaml
# values.override.yaml
mysql:
  enabled: false
minio:
  enabled: false
redis:
  enabled: false

env:
  MYSQL_HOST: mydb.example.com
  MYSQL_PASSWORD: "<password>"
  MINIO_HOST: s3.example.com
  MINIO_PASSWORD: "<password>"
  REDIS_HOST: redis.example.com
  REDIS_PASSWORD: "<password>"
```

### 多副本扩展
修改 `ragflow.deployment` 配置或使用 HPA：
```bash
kubectl scale deployment ragflow --replicas=3 -n ragflow
```

### Ingress 配置
```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: ragflow.example.com
      paths:
        - path: /
          pathType: Prefix
```

## 健康检查

每个 ragflow-server 实例提供健康检查端点：
```bash
curl http://ragflow-server:9380/api/v1/system/status
```

## 生产环境注意事项

> **警告**: 默认 Docker Compose 使用开发服务器，生产环境建议：
> 1. 使用 Kubernetes + Helm Chart 部署
> 2. 或配置生产级 WSGI 服务器（如 Gunicorn）

参考 GitHub Issue: [#11224](https://github.com/infiniflow/ragflow/issues/11224), [#5489](https://github.com/infiniflow/ragflow/issues/5489)

## 总结

RAGFlow 原生支持多实例部署：
1. 确保所有实例连接相同的后端存储
2. 正确配置负载均衡器（特别是流式响应）
3. 根据负载独立扩展 ragflow-server 和 task_executor
4. 生产环境推荐使用 Kubernetes + Helm Chart
