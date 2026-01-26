# DashScope 绿网检测禁用补丁 - v0.23.1

本目录包含针对 RAGFlow v0.23.1 版本的 DashScope 绿网检测禁用补丁文件。

## 文件说明

- `chat_model.py` - 修改后的聊天模型文件
- `embedding_model.py` - 修改后的嵌入模型文件
- `rerank_model.py` - 修改后的重排序模型文件

## 使用方法

### 方式一：Docker Compose 挂载（推荐）

在 `docker-compose.yml` 中添加以下 volume 挂载：

```yaml
services:
  ragflow:
    volumes:
      - ./docker/lvwang_0.23.1/chat_model.py:/ragflow/rag/llm/chat_model.py
      - ./docker/lvwang_0.23.1/embedding_model.py:/ragflow/rag/llm/embedding_model.py
      - ./docker/lvwang_0.23.1/rerank_model.py:/ragflow/rag/llm/rerank_model.py
```

### 方式二：直接替换源文件

```bash
cp docker/lvwang_0.23.1/chat_model.py rag/llm/chat_model.py
cp docker/lvwang_0.23.1/embedding_model.py rag/llm/embedding_model.py
cp docker/lvwang_0.23.1/rerank_model.py rag/llm/rerank_model.py
```

## 修改内容

### 1. chat_model.py
在 `LiteLLMBase._construct_completion_args` 方法中添加：
```python
# Add DashScope green-net disable header automatically for Alibaba Cloud providers
if self.provider in [SupportedLiteLLMProvider.Tongyi_Qianwen, SupportedLiteLLMProvider.Dashscope]:
    extra_headers.setdefault("X-DashScope-DataInspection", '{"input":"disable","output":"disable"}')
```

### 2. embedding_model.py
在 `QWenEmbed` 类的所有 `dashscope.TextEmbedding.call` 调用中添加：
```python
extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
```

### 3. rerank_model.py
在 `QWenRerank.similarity` 方法的 `dashscope.TextReRank.call` 调用中添加：
```python
extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
```

## 功能说明

通过在 API 请求中添加 HTTP 头 `X-DashScope-DataInspection: {"input":"disable","output":"disable"}`，可以禁用阿里云 DashScope 服务的内容安全检测（绿网），避免敏感内容被拦截。

## 注意事项

1. 此修改仅影响阿里云 DashScope 相关的模型（通义千问系列）
2. 不会覆盖用户已经设置的 `X-DashScope-DataInspection` 头
3. 适用于 RAGFlow v0.23.1 版本
4. 如果 DashScope SDK 版本更新，可能需要调整实现方式

## 版本历史

- v0.23.1: 初始版本，基于 v0.23.1 标签创建
