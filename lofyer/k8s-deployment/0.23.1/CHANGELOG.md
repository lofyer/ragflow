# RAGFlow K8s 0.23.1 更新计划

基于 0.21.1 版本配置审查，计划进行以下改进：

## 安全性改进

### 1. 敏感信息迁移到 Secret
- [ ] 将 MySQL 密码从 ConfigMap/硬编码迁移到 Secret
- [ ] 将 Redis 密码从启动参数迁移到 Secret
- [ ] 将 MinIO 凭证迁移到 Secret
- [ ] 将 Elasticsearch 密码迁移到 Secret
- [ ] 更新所有 Deployment/StatefulSet 引用 Secret

### 2. 网络安全
- [ ] 添加 NetworkPolicy 限制 Pod 间通信
- [ ] 移除不必要的端口暴露（80/443/5678/5679）

## 资源配置优化

### 3. 移除资源限制
- [x] 移除所有组件的 resources 限制，允许根据实际需求动态使用资源
- [x] MySQL: 已移除资源限制
- [x] Elasticsearch: 已移除资源限制
- [x] Redis: 已移除资源限制
- [x] MinIO: 已移除资源限制
- [x] Ragflow: 已移除资源限制

## 存储改进

### 4. 独立 PVC
- [ ] 为 MySQL 创建独立 PVC
- [ ] 为 Elasticsearch 创建独立 PVC
- [ ] 为 MinIO 创建独立 PVC
- [ ] 为 Redis 创建独立 PVC
- [ ] 移除 NFS server IP 硬编码，改为参数化配置

## 可靠性改进

### 5. 健康检查
- [ ] 为 MySQL 添加 liveness/readiness 探针
- [ ] 为 Elasticsearch 添加 liveness/readiness 探针
- [ ] 检查并优化现有探针配置

### 6. 高可用配置
- [ ] 添加 PodDisruptionBudget
- [ ] 考虑添加 Pod 反亲和性规则

## 流量管理

### 7. Ingress 配置
- [ ] 添加 Ingress 资源用于外部访问
- [ ] 配置 TLS 终止

## 代码清理

### 8. 配置清理
- [ ] 移除未使用的 volume `ragflow-claim4`
- [ ] 清理冗余的 kompose 注解
- [ ] 统一命名规范

## 优先级

1. **高优先级**: 安全性改进（Secret 迁移）
2. **中优先级**: 资源配置优化、健康检查
3. **低优先级**: 存储独立、Ingress、高可用配置
