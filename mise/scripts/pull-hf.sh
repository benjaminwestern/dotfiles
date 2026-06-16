#!/usr/bin/env bash
# pull-hf — Download a HuggingFace GGUF model for use with llama.cpp.
#
# Usage:
#   pull-hf <hf_repo> <gguf_filename> [local_name]
#
# Examples:
#   pull-hf bartowski/gemma-4-e4b-it-GGUF gemma-4-e4b-it-Q4_K_M.gguf
#   pull-hf bartowski/gemma-4-e4b-it-GGUF gemma-4-e4b-it-Q4_K_M.gguf my-gemma-e4b
#   pull-hf MaziyarPanahi/Llama-3.1-8B-Instruct-GGUF Llama-3.1-8B-Instruct-Q4_K_M.gguf
#
# Requires: hf (mise-managed via [bootstrap.packages])

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: pull-hf <hf_repo> <gguf_filename> [local_name]"
    echo ""
    echo "  hf_repo       HuggingFace repository (e.g. bartowski/gemma-4-e4b-it-GGUF)"
    echo "  gguf_filename GGUF file to download from that repo"
    echo "  local_name    (optional) Local directory name. Defaults to filename without .gguf"
    echo ""
    echo "Examples:"
    echo "  pull-hf bartowski/gemma-4-e4b-it-GGUF gemma-4-e4b-it-Q4_K_M.gguf"
    echo "  pull-hf unsloth/Llama-3.2-3B-Instruct-GGUF Llama-3.2-3B-Instruct-Q4_K_M.gguf llama3.2-3b"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

HF_REPO="$1"
GGUF_FILE="$2"
LOCAL_NAME="${3:-${GGUF_FILE%.gguf}}"

MODEL_DIR="${HOME}/.models/${LOCAL_NAME}"
mkdir -p "$MODEL_DIR"

if [ ! -f "${MODEL_DIR}/${GGUF_FILE}" ]; then
    echo -e "${YELLOW}Downloading ${GGUF_FILE} from ${HF_REPO}...${NC}"
    hf download "$HF_REPO" "$GGUF_FILE" --local-dir "$MODEL_DIR"
else
    echo -e "${GREEN}${GGUF_FILE} already present in ${MODEL_DIR}${NC}"
fi

MODEL_PATH="${MODEL_DIR}/${GGUF_FILE}"

if [ ! -f "$MODEL_PATH" ]; then
    echo -e "${RED}Error: Downloaded file not found at ${MODEL_PATH}${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Done! Model downloaded to:${NC} ${MODEL_PATH}"
echo ""
echo -e "Serve with: ${YELLOW}llama-server -m ${MODEL_PATH} --port 4096${NC}"
echo -e "Chat with:  ${YELLOW}llama-cli -m ${MODEL_PATH} -p 'Hello!'${NC}"
echo -e "In Pi:      ${YELLOW}/model${NC} to select the OpenAI-compatible endpoint (after configuring it)"
