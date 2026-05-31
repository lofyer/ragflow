# RAGFlow Project Instructions for GitHub Copilot

This file provides context, build instructions, and coding standards for the RAGFlow project.
It is structured to follow GitHub Copilot's [customization guidelines](https://docs.github.com/en/copilot/concepts/prompting/response-customization).

## 1. Project Overview
RAGFlow is an open-source RAG (Retrieval-Augmented Generation) engine based on deep document understanding. It is a full-stack application with a Python backend and a React/TypeScript frontend.

- **Backend**: Python 3.10+ (Flask/Quart)
- **Frontend**: TypeScript, React, UmiJS
- **Architecture**: Microservices based on Docker.
  - `api/`: Backend API server.
  - `rag/`: Core RAG logic (indexing, retrieval).
  - `deepdoc/`: Document parsing and OCR.
  - `web/`: Frontend application.

## 2. Directory Structure
- `api/`: Backend API server (Flask/Quart).
  - `apps/`: API Blueprints (Knowledge Base, Chat, etc.).
  - `db/`: Database models and services.
- `rag/`: Core RAG logic.
  - `llm/`: LLM, Embedding, and Rerank model abstractions.
- `deepdoc/`: Document parsing and OCR modules.
- `agent/`: Agentic reasoning components.
- `web/`: Frontend application (React + UmiJS).
- `docker/`: Docker deployment configurations.
- `sdk/`: Python SDK.
- `test/`: Backend tests.

## 3. Build Instructions

### Backend (Python)
The project uses **uv** for dependency management.

1. **Setup Environment**:
   ```bash
   uv sync --python 3.13 --all-extras
   uv run python3 download_deps.py
   ```

2. **Run Server**:
   - **Pre-requisite**: Start dependent services (MySQL, ES/Infinity, Redis, MinIO).
     ```bash
     docker compose -f docker/docker-compose-base.yml up -d
     ```
   - **Launch**:
     ```bash
     source .venv/bin/activate
     export PYTHONPATH=$(pwd)
     bash docker/launch_backend_service.sh
     ```

### Frontend (TypeScript/React)
Located in `web/`.

1. **Install Dependencies**:
   ```bash
   cd web
   npm install
   ```

2. **Run Dev Server**:
   ```bash
   npm run dev
   ```
   Runs on port 8000 by default.

### Docker Deployment
To run the full stack using Docker:
```bash
cd docker
docker compose -f docker-compose.yml up -d
```

## 4. Testing Instructions

### Backend Tests
- **Run All Tests**:
  ```bash
  uv run pytest
  ```
- **Run Specific Test**:
  ```bash
  uv run pytest test/test_api.py
  ```

### Frontend Tests
- **Run Tests**:
  ```bash
  cd web
  npm run test
  ```

## 5. Coding Standards & Guidelines
- **Python Formatting**: Use `ruff` for linting and formatting.
  ```bash
  ruff check
  ruff format
  ```
- **Frontend Linting**:
  ```bash
  cd web
  npm run lint
  ```
- **Pre-commit**: Ensure pre-commit hooks are installed.
  ```bash
  pre-commit install
  pre-commit run --all-files
  ```

## 6. Lofyer Fork Customizations

This fork (`v*.*.*-lofyer` branches) carries the customizations below on top of
upstream tags. When rebasing onto a new upstream tag (e.g. creating
`v0.25.7-lofyer` from `v0.25.7`), re-apply these instead of blindly
cherry-picking, since upstream rewrites these files frequently and conflicts are
expected. The list of authoritative commits lives in git history; this section
is the canonical description of intent.

### 6.1 Disable DashScope green-net content inspection (Tongyi-Qianwen)
Add header `X-DashScope-DataInspection: {"input":"disable","output":"disable"}`
to all Alibaba Cloud / DashScope calls. Use `setdefault` so a user-supplied
header is never overridden.
- `rag/llm/chat_model.py`: in `LiteLLMBase` completion-args builder, set the
  header for `SupportedLiteLLMProvider.Tongyi_Qianwen` and `.Dashscope`.
- `rag/llm/embedding_model.py` (`QWenEmbed.encode` / `encode_queries`): pass
  `extra_headers` into every `dashscope.TextEmbedding.call`.
- `rag/llm/rerank_model.py` (`QWenRerank.similarity`): pass `extra_headers` into
  `dashscope.TextReRank.call`; also surface `resp.message`/`resp.code` in the
  error message instead of `resp.text`.

### 6.2 Apply Qwen3 thinking-off policy on streaming & tool-call paths
Upstream's `_apply_model_family_policies` injects
`extra_body={"enable_thinking": False}` for `qwen3*` only on non-stream chat.
Extend it so streaming and tool-call paths get the same treatment:
- `rag/llm/chat_model.py` `Base.<streaming>`: call
  `_apply_model_family_policies(..., backend="base")` and merge the returned
  policy kwargs into `request_kwargs`.
- `rag/llm/chat_model.py` `LiteLLMBase` completion-args builder: call
  `_apply_model_family_policies(..., backend="litellm", provider=self.provider)`,
  then merge `policy_extra_body` into any existing `extra_body` (preserve
  caller-set keys like OpenRouter provider routing) and `setdefault` the rest.

### 6.3 Qwen embedding network-error retry
`rag/llm/embedding_model.py` `QWenEmbed`: add `_safe_call(**kwargs)` that wraps
`dashscope.TextEmbedding.call` and returns `None` on network exceptions (Errno
101, DNS failures, timeouts) so the existing retry loop retries instead of
crashing. Guard all `resp` checks with `resp is None`. Keep calls inside the
upstream `_dashscope_native_api_url_scope` context manager.

### 6.4 Add `qwen3.6-plus` to the LLM factory
`conf/llm_factories.json`: under the Tongyi-Qianwen factory, add a `qwen3.6-plus`
chat entry (tags `LLM,CHAT,1M,IMAGE2TEXT`, `max_tokens` 1000000,
`is_tools` true), next to `qwen3.5-plus`.

### 6.5 Docker deployment overrides
- `docker/docker-compose.yml`: in both `ragflow` and `ragflow-admin` (or
  equivalent) services, bind-mount the customized files into the image so a
  rebuild is not required:
  - `../conf/llm_factories.json:/ragflow/conf/llm_factories.json`
  - `../rag/llm/chat_model.py:/ragflow/rag/llm/chat_model.py`
  - `../rag/llm/embedding_model.py:/ragflow/rag/llm/embedding_model.py`
  - `../rag/llm/rerank_model.py:/ragflow/rag/llm/rerank_model.py`
- `docker/.env`:
  - `SVR_WEB_HTTP_PORT=7080`, `SVR_WEB_HTTPS_PORT=7443` (avoid host 80/443).
  - Enable sandbox: uncomment `SANDBOX_ENABLED=1` and
    `COMPOSE_PROFILES=${COMPOSE_PROFILES},sandbox`. (Note: upstream dropped
    `SANDBOX_HOST`; do not re-add it.)

