#!/bin/bash

export OPENAI_BASE_URL=https://127.0.0.1:<port>/v1
export OPENAI_API_KEY=<insert your api key here>

curl -sk "$OPENAI_BASE_URL/models" \
  -H "Authorization: Bearer $OPENAI_API_KEY" | jq

curl -sk "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community-nvidia-nemotron-3-nano-4b-4bit",
    "messages": [{"role": "user", "content": "Explain what MLX is in one line."}]
  }' | jq

curl -sk -N "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mlx-community-nvidia-nemotron-3-nano-4b-4bit",
    "messages": [{"role": "user", "content": "Count to 5."}],
    "stream": true
  }'