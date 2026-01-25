# DashScope 绿网检测禁用修改说明

## 问题背景

阿里云 DashScope 服务默认开启内容安全检测（绿网），会对输入输出内容进行审查。在某些场景下需要禁用此功能。

## 解决方案

通过在 API 请求中添加 `X-DashScope-DataInspection` HTTP 头来禁用内容检测。

### 修改位置

需要修改以下三个文件：

1. `rag/llm/chat_model.py`
2. `rag/llm/embedding_model.py`
3. `rag/llm/rerank_model.py`

---

## 1. chat_model.py 修改

### 位置：LiteLLMBase 类的 _chat 和 _chat_streamly 方法

在 `LiteLLMBase` 类中，找到 `_chat` 方法（约在 1549 行附近），在 `completion_args` 字典定义后添加：

```python
completion_args = {
    "model": self.model_name,
    "messages": history,
    "num_retries": self.max_retries,
    **kwargs,
}

# Add DashScope green-net disable header automatically for Alibaba Cloud providers
if self.provider in [SupportedLiteLLMProvider.Tongyi_Qianwen, SupportedLiteLLMProvider.Dashscope]:
    extra_headers = completion_args.get("extra_headers", {})
    if not isinstance(extra_headers, dict):
        extra_headers = {}
    # Do not override if user already set this header
    extra_headers.setdefault("X-DashScope-DataInspection", '{"input":"disable","output":"disable"}')
    completion_args["extra_headers"] = extra_headers
```

---

## 2. embedding_model.py 修改

### 位置：QWenEmbed 类

#### 2.1 encode 方法修改

找到 `QWenEmbed.encode` 方法中的 `dashscope.TextEmbedding.call` 调用，添加 `extra_headers` 参数：

**原代码：**
```python
resp = dashscope.TextEmbedding.call(
    model=self.model_name, 
    input=texts[i : i + batch_size], 
    api_key=self.key, 
    text_type="document"
)
```

**修改为：**
```python
resp = dashscope.TextEmbedding.call(
    model=self.model_name,
    input=texts[i : i + batch_size],
    api_key=self.key,
    text_type="document",
    extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
)
```

**注意：** 该方法中有两处调用（正常调用和重试调用），都需要修改。

#### 2.2 encode_queries 方法修改

找到 `QWenEmbed.encode_queries` 方法：

**原代码：**
```python
resp = dashscope.TextEmbedding.call(
    model=self.model_name, 
    input=text[:2048], 
    api_key=self.key, 
    text_type="query"
)
```

**修改为：**
```python
resp = dashscope.TextEmbedding.call(
    model=self.model_name,
    input=text[:2048],
    api_key=self.key,
    text_type="query",
    extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
)
```

---

## 3. rerank_model.py 修改

### 位置：QWenRerank 类的 similarity 方法

找到 `QWenRerank.similarity` 方法中的 `dashscope.TextReRank.call` 调用：

**原代码：**
```python
resp = dashscope.TextReRank.call(
    api_key=self.api_key, 
    model=self.model_name, 
    query=query, 
    documents=texts, 
    top_n=len(texts), 
    return_documents=False
)
```

**修改为：**
```python
resp = dashscope.TextReRank.call(
    api_key=self.api_key,
    model=self.model_name,
    query=query,
    documents=texts,
    top_n=len(texts),
    return_documents=False,
    extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
)
```

### 额外修改：错误信息优化

在同一方法的错误处理部分，优化错误信息：

**原代码：**
```python
else:
    raise ValueError(f"Error calling QWenRerank model {self.model_name}: {resp.status_code} - {resp.text}")
```

**修改为：**
```python
else:
    error_msg = getattr(resp, 'message', None) or getattr(resp, 'code', 'Unknown error')
    raise ValueError(f"Error calling QWenRerank model {self.model_name}: {resp.status_code} - {error_msg}")
```

---

## 验证方法

修改完成后，可以通过以下方式验证：

1. 使用通义千问模型进行对话测试
2. 使用通义千问 embedding 模型进行文本嵌入
3. 使用通义千问 rerank 模型进行重排序

观察日志中是否有内容安全相关的错误或警告。

---

## 注意事项

1. 此修改仅影响阿里云 DashScope 相关的模型（通义千问系列）
2. 不会覆盖用户已经设置的 `X-DashScope-DataInspection` 头
3. 适用于 RAGFlow v0.20.5 及后续版本
4. 如果 DashScope SDK 版本更新，可能需要调整实现方式

---

## 版本记录

- v0.20.5: 初始实现
- v0.23.1: 文档化，便于后续版本迁移
