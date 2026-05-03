#!/usr/bin/env bash
# pull-hf — Import any HuggingFace GGUF model into Ollama for use with Pi.
#
# Usage:
#   pull-hf <hf_repo> <gguf_filename> [ollama_model_name]
#
# Examples:
#   pull-hf bartowski/gemma-4-e4b-it-GGUF gemma-4-e4b-it-Q4_K_M.gguf
#   pull-hf bartowski/gemma-4-e4b-it-GGUF gemma-4-e4b-it-Q4_K_M.gguf my-gemma-e4b
#   pull-hf MaziyarPanahi/Llama-3.1-8B-Instruct-GGUF Llama-3.1-8B-Instruct-Q4_K_M.gguf
#
# Requires: hf (brew install hf) and ollama (brew install ollama)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: pull-hf <hf_repo> <gguf_filename> [ollama_model_name]"
    echo ""
    echo "  hf_repo            HuggingFace repository (e.g. bartowski/gemma-4-e4b-it-GGUF)"
    echo "  gguf_filename      GGUF file to download from that repo"
    echo "  ollama_model_name  (optional) Name for the model in Ollama. Defaults to the filename without .gguf"
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
OLLAMA_NAME="${3:-${GGUF_FILE%.gguf}}"

MODEL_DIR="${HOME}/.ollama-models/${HF_REPO#*/}"
mkdir -p "$MODEL_DIR"

echo -e "${YELLOW}Downloading ${GGUF_FILE} from ${HF_REPO}...${NC}"
hf download "$HF_REPO" "$GGUF_FILE" --local-dir "$MODEL_DIR"

MODEL_PATH="${MODEL_DIR}/${GGUF_FILE}"

if [ ! -f "$MODEL_PATH" ]; then
    echo -e "${RED}Error: Downloaded file not found at ${MODEL_PATH}${NC}"
    exit 1
fi

echo -e "${YELLOW}Importing into Ollama as '${OLLAMA_NAME}'...${NC}"

# Create temporary Modelfile with image support enabled
TMP_MODELFILE=$(mktemp)
cat > "$TMP_MODELFILE" << MODELEOF
FROM ${MODEL_PATH}
MODELEOF

ollama create "$OLLAMA_NAME" -f "$TMP_MODELFILE"
rm -f "$TMP_MODELFILE"

echo ""
echo -e "${GREEN}Done! Model '${OLLAMA_NAME}' is now available in Ollama.${NC}"
echo -e "Verify: ${YELLOW}ollama list${NC}"
echo -e "Test:   ${YELLOW}ollama run ${OLLAMA_NAME} 'Hello, who are you?'${NC}"
echo -e "In Pi:  ${YELLOW}/model${NC} to select it (after adding to ~/.pi/agent/models.json)"
echo ""
echo -e "${YELLOW}To add this model to Pi, add to ~/.pi/agent/models.json under the ollama provider:${NC}"
echo "  { \"id\": \"${OLLAMA_NAME}\", \"input\": [\"text\", \"image\"] }"
