# RAGFlow Instructions

Use this file as the local operating guide for the current codebase. Prefer the code and the current CLAUDE.md over any older convention or remembered project shape.

## Core stance
- Treat legacy code as liability, not as a compatibility target.
- Prefer deletion over shims, deprecated branches, wrapper APIs, and dual-track migration notes.
- If old and new implementations coexist, converge to one path unless an external contract forces compatibility.
- Remove dead tests, commented-out code, stale docs, and "move later" notes instead of preserving them.
- Reduce public surface area when a helper can be made private or internal.
- Keep refactors centered on the owning abstraction, not on adjacent compatibility layers.

## Current stack
- Backend: Python 3.13+, Quart-based API server, Peewee ORM, async workers.
- Frontend: React + TypeScript + Vite in `web/`.
- Go: the repository also has a substantial Go module for servers, ingestion, parser/runtime, CLI, and supporting services.
- Runtime services commonly include MySQL/PostgreSQL, Redis, MinIO, and Elasticsearch/Infinity/OpenSearch depending on configuration.

## Code layout to expect
- `api/`: Python API server entrypoints, blueprints, services, and database code.
- `rag/`: ingestion, retrieval, LLM integration, and graph RAG logic.
- `deepdoc/`: parsing and OCR.
- `agent/`: workflow canvas, components, tools, and templates.
- `cmd/`: Go entrypoints. `ragflow_main` is the main server/admin/ingestor binary surface; `ragflow-cli` is the CLI entrypoint.
- `internal/`: main Go application code. Important subtrees:
- `internal/agent/`: Go agent runtime, canvas execution, components, tool bindings, workflow helpers.
- `internal/cli/`: CLI parsing, HTTP transport, command execution, response formatting.
- `internal/dao/`: Go data-access layer and persistence-facing helpers.
- `internal/deepdoc/`: Go DeepDOC integrations, especially native-backed PDF/DOCX parsing.
- `internal/engine/`: search/index backends such as Elasticsearch and Infinity.
- `internal/entity/`: shared Go entities and model definitions.
- `internal/handler/`: HTTP handlers and route-facing request logic.
- `internal/ingestion/`: Go ingestion pipeline, canvas adapter, components, wiring, service orchestration.
- `internal/ingestion/component/`: stage implementations such as file/parser/chunker/tokenizer/extractor.
- `internal/ingestion/pipeline/`: DSL translation, canvas-driven execution, checkpoints, resume/run logic.
- `internal/parser/`: parser and chunk libraries used by ingestion and other Go paths.
- `internal/parser/parser/`: typed parse-result parsers for markdown/html/pdf/docx/xlsx/text and related families.
- `internal/parser/chunk/`: chunk operator library and DSL/typed execution helpers.
- `internal/service/`: higher-level business services used by handlers and server flows.
- `internal/storage/`: storage backends and in-memory test doubles.
- `internal/router/`: HTTP route registration.
- `internal/server/`: server bootstrap/config wiring.
- `internal/cpp/`: C++ sources used by native-backed Go features.
- `web/`: frontend application.
- `docker/`: local and production compose files.
- `sdk/` and `test/`: SDK and automated tests.

## Go-specific rules
- Treat `internal/ingestion`, `internal/parser`, and `internal/deepdoc` as actively refactored code. Prefer collapsing duplicate paths over preserving transitional wrappers.
- Do not add or preserve deprecated Go APIs just to ease migration inside the repo.
- Remove commented-out Go code instead of leaving recovery notes in place.
- Keep package comments and doc comments aligned with the current runtime path, not with migration history.

## Working rules
- Before editing, inspect the nearest code path that actually owns the behavior.
- Keep changes small and local unless the task is explicitly a broader refactor.
- Prefer one implementation path instead of preserving old and new versions side by side.
- Preserve behavior with focused tests when the behavior is still valid; do not keep tests that protect obsolete behavior.
- If a surface is only there for compatibility, remove it unless the user asks to keep it.
- Do not add new compatibility wording in comments or docs.

## Commands
### Backend
```bash
uv sync --python 3.13 --all-extras
uv run python3 ragflow_deps/download_deps.py
docker compose -f docker/docker-compose-base.yml up -d
source .venv/bin/activate
export PYTHONPATH=$(pwd)
bash docker/launch_backend_service.sh
uv run pytest
ruff check
ruff format
```

### Frontend
```bash
cd web
npm install
npm run dev
npm run build
npm run lint
npm run test
npm run type-check
```

### Go
```bash
uv run ragflow_deps/download_deps.py
bash build.sh --test ./path/to/package/...
bash build.sh --go
# or build specific binaries:
bash build.sh --all
```

## Validation preference
- Run the narrowest relevant test, lint, or build command after a change.
- For backend changes, prefer targeted pytest or ruff checks over full-suite runs.
- For frontend changes, prefer the touched-package lint, type-check, or test command.
- For Go changes, prefer package-scoped `bash build.sh --test ...` first.
- Do not default to raw `go test`, `go build`, or IDE Run/Debug for Go in this repo. They often miss the required CGO flags and native static libraries (`office_oxide`, `pdfium-static`, `pdf_oxide`) that `build.sh` wires correctly.
- If Go native builds fail, inspect `build.sh` and `internal/development.md` before changing code. Common environment issues are missing downloaded native deps and missing `lld` on Linux.

## Default review checklist
- Remove instead of retaining `deprecated`, `legacy`, or compatibility-only code.
- Collapse duplicate implementations to one path.
- Drop stale comments and documentation that describe a superseded design.
- Keep exported APIs only when the current code actually needs them.

## Lofyer Fork Customizations

This fork (`v*.*.*-lofyer` branches) carries the customizations below on top of
upstream tags. When rebasing onto a new upstream tag (e.g. creating
`v0.26.5-lofyer` from `v0.26.5`), re-apply these instead of blindly
cherry-picking, since upstream rewrites these files frequently and conflicts are
expected. The list of authoritative commits lives in git history; this section
is the canonical description of intent.

### 1. Disable DashScope green-net content inspection (Tongyi-Qianwen)
Add header `X-DashScope-DataInspection: {"input":"disable","output":"disable"}`
to all Alibaba Cloud / DashScope calls. Use `setdefault` so a user-supplied
header is never overridden.
- `rag/llm/chat_model.py`: in `LiteLLMBase._construct_completion_args`, set the
  header for `SupportedLiteLLMProvider.Tongyi_Qianwen` and `.Dashscope`.
- `rag/llm/embedding_model.py` (`QWenEmbed.encode` / `encode_queries`): pass
  `extra_headers` into every `dashscope.TextEmbedding.call`.
- `rag/llm/rerank_model.py` (`QWenRerank._compute_rank`): pass `extra_headers`
  into both `dashscope.TextReRank.call` branches.

### 2. Qwen embedding network-error retry
`rag/llm/embedding_model.py` `QWenEmbed`: add `_safe_call(**kwargs)` that wraps
`dashscope.TextEmbedding.call` and returns `None` on network exceptions (Errno
101, DNS failures, timeouts) so the existing retry loop retries instead of
crashing. Guard the `resp is None` case in the retry loop. Keep calls inside the
upstream `_dashscope_native_api_url_scope` context manager.

### 3. Docker deployment overrides
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
    `COMPOSE_PROFILES=${COMPOSE_PROFILES},sandbox`.

### 4. Docker image export/import helper
`docker/image.sh`: convenience script to save/load the RAGFlow images as tar
archives for offline transfer.

### Upstreamed (no longer re-applied as of v0.26.4)
- Qwen3 thinking-off policy now runs on streaming & tool-call paths upstream via
  `_apply_model_family_policies` at every call site.
- `qwen3.6-plus` is already present in `conf/llm_factories.json`.
