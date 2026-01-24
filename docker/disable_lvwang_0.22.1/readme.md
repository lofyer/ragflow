diff --git a/rag/llm/chat_model.py b/rag/llm/chat_model.py
index 5ea610a8..2c50015f 100644
--- a/rag/llm/chat_model.py
+++ b/rag/llm/chat_model.py
@@ -1557,6 +1557,15 @@ class LiteLLMBase(ABC):
             "num_retries": self.max_retries,
             **kwargs,
         }
+        # Add DashScope green-net disable header automatically for Alibaba Cloud providers
+        if self.provider in [SupportedLiteLLMProvider.Tongyi_Qianwen, SupportedLiteLLMProvider.Dashscope]:
+            extra_headers = completion_args.get("extra_headers", {})
+            if not isinstance(extra_headers, dict):
+                extra_headers = {}
+            # Do not override if user already set this header
+            extra_headers.setdefault("X-DashScope-DataInspection", '{"input":"disable","output":"disable"}')
+            completion_args["extra_headers"] = extra_headers
+
         if stream:
             completion_args.update(
                 {
diff --git a/rag/llm/embedding_model.py b/rag/llm/embedding_model.py
index 3b147885..ff043038 100644
--- a/rag/llm/embedding_model.py
+++ b/rag/llm/embedding_model.py
@@ -224,10 +224,22 @@ class QWenEmbed(Base):
         texts = [truncate(t, 2048) for t in texts]
         for i in range(0, len(texts), batch_size):
             retry_max = 5
-            resp = dashscope.TextEmbedding.call(model=self.model_name, input=texts[i : i + batch_size], api_key=self.key, text_type="document")
+            resp = dashscope.TextEmbedding.call(
+                model=self.model_name,
+                input=texts[i : i + batch_size],
+                api_key=self.key,
+                text_type="document",
+                extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
+            )
             while (resp["output"] is None or resp["output"].get("embeddings") is None) and retry_max > 0:
                 time.sleep(10)
-                resp = dashscope.TextEmbedding.call(model=self.model_name, input=texts[i : i + batch_size], api_key=self.key, text_type="document")
+                resp = dashscope.TextEmbedding.call(
+                    model=self.model_name,
+                    input=texts[i : i + batch_size],
+                    api_key=self.key,
+                    text_type="document",
+                    extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
+                )
                 retry_max -= 1
             if retry_max == 0 and (resp["output"] is None or resp["output"].get("embeddings") is None):
                 if resp.get("message"):
@@ -247,7 +259,13 @@ class QWenEmbed(Base):
         return np.array(res), token_count
 
     def encode_queries(self, text):
-        resp = dashscope.TextEmbedding.call(model=self.model_name, input=text[:2048], api_key=self.key, text_type="query")
+        resp = dashscope.TextEmbedding.call(
+            model=self.model_name,
+            input=text[:2048],
+            api_key=self.key,
+            text_type="query",
+            extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
+        )
         try:
             return np.array(resp["output"]["embeddings"][0]["embedding"]), self.total_token_count(resp)
         except Exception as _e:
diff --git a/rag/llm/rerank_model.py b/rag/llm/rerank_model.py
index a69efa7e..644861fc 100644
--- a/rag/llm/rerank_model.py
+++ b/rag/llm/rerank_model.py
@@ -512,7 +512,15 @@ class QWenRerank(Base):
 
         import dashscope
 
-        resp = dashscope.TextReRank.call(api_key=self.api_key, model=self.model_name, query=query, documents=texts, top_n=len(texts), return_documents=False)
+        resp = dashscope.TextReRank.call(
+            api_key=self.api_key,
+            model=self.model_name,
+            query=query,
+            documents=texts,
+            top_n=len(texts),
+            return_documents=False,
+            extra_headers={"X-DashScope-DataInspection": '{"input":"disable","output":"disable"}'}
+        )
         rank = np.zeros(len(texts), dtype=float)
         if resp.status_code == HTTPStatus.OK:
             try:
