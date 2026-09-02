#!/bin/bash
set -euo pipefail

OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://127.0.0.1:7777/v1}"
OPENAI_API_KEY="${OPENAI_API_KEY:-sk-hp-8b9a9b105d00e6bc601d65a7e1fcd924b34dc374f951c81a}"
# Catalog slug or prefix of openai_id from GET /v1/models (before the instance suffix).
LLM_MODEL="${LLM_MODEL:-qwen-qwen2-5-coder-7b-7b46f1f9}"

MODELS_JSON=$(curl -sk "$OPENAI_BASE_URL/models" \
  -H "Authorization: Bearer $OPENAI_API_KEY")
echo "$MODELS_JSON" | jq

RESOLVED_MODEL=$(echo "$MODELS_JSON" | jq -r --arg m "$LLM_MODEL" '
  [.data[]
   | select(.id == $m or (.id | startswith($m + "-")))]
  | .[0].id // empty
')
if [[ -z "$RESOLVED_MODEL" ]]; then
  echo "error: no loaded model matches LLM_MODEL=$LLM_MODEL" >&2
  echo "       loaded ids:" >&2
  echo "$MODELS_JSON" | jq -r '.data[].id' >&2
  exit 1
fi
echo "Using model: $RESOLVED_MODEL" >&2

CHAT_BODY=$(jq -n --arg model "$RESOLVED_MODEL" '{
  model: $model,
  messages: [{role: "user", content: "Explain what MLX is in one line."}]
}')
CHAT_JSON=$(curl -sk "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "$CHAT_BODY")
echo "$CHAT_JSON" | jq
if echo "$CHAT_JSON" | jq -e '.error' >/dev/null; then
  exit 1
fi

STREAM_BODY=$(jq -n --arg model "$RESOLVED_MODEL" '{
  model: $model,
  messages: [{role: "user", content: "Count to 5."}],
  stream: true
}')
curl -sk -N "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "$STREAM_BODY"
