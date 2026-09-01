#!/bin/bash

export OPENAI_BASE_URL=https://127.0.0.1:7777/v1
export OPENAI_API_KEY=sk-hp-2055437c1c4cc50259926bfa3c9644b93115d949fde3fb33

curl -sk "$OPENAI_BASE_URL/models" \
  -H "Authorization: Bearer $OPENAI_API_KEY" | jq

curl -sk "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "google-gemma-4-e4b-it",
    "messages": [{"role": "user", "content": "Explain what MLX is in one line."}]
  }' | jq