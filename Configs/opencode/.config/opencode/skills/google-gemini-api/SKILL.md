---
name: google-gemini-api
description: Use this skill when building applications with Gemini models, Gemini API, working with multimodal content (text, images, audio, video), implementing function calling, using structured outputs, or needing current model specifications. Covers SDK usage (google-genai for Python, @google/genai for JavaScript/TypeScript, com.google.genai:google-genai for Java, google.golang.org/genai for Go), model selection, and API capabilities.
license: MIT
compatibility: opencode
author: OpenCode
version: 1.0.0
tags:
  - gemini
  - google-ai
  - genai
  - multimodal
  - function-calling
  - structured-output
  - embeddings
  - rest-api
metadata:
  category: ai-development
  language: multi
  scope: api-integration
  complexity: intermediate
  installation:
    python: pip install google-genai
    node: npm install @google/genai
    go: go get google.golang.org/genai
    java: com.google.genai:google-genai (see Maven Central for latest version)
  dependencies:
    - Python: google-genai
    - Node.js: @google/genai
    - Go: google.golang.org/genai
    - Java: com.google.genai:google-genai
  related_skills: []
  use_cases:
    - Building chat applications
    - Processing multimodal content (text, images, audio, video)
    - Implementing function calling
    - Generating structured JSON outputs
    - Creating embeddings for semantic search
    - Building batch processing pipelines
    - Implementing real-time streaming with Live API
    - Optimizing costs with context caching
  prerequisites:
    - Google AI Studio API key or GCP project with Vertex AI enabled
  references:
    - caching: references/caching.md - Context caching for cost optimization
    - batching: references/batching.md - Batch processing for large-scale operations
    - live-api: references/live-api.md - Real-time streaming and bidirectional communication
    - function-calling: references/function-calling.md - Function calling patterns and tools
    - structured-output: references/structured-output.md - JSON schema and type-safe outputs
    - embeddings: references/embeddings.md - Text embeddings and semantic search
    - multimodal: references/multimodal.md - Images, audio, video, document processing
    - error-handling: references/error-handling.md - Error handling, retries, and rate limits
    - rest-api: references/rest-api.md - Direct REST API usage
---

# Google Gemini API Skill

## Overview

The Gemini API provides access to Google's most advanced AI models. Key capabilities include:
- **Text generation** - Chat, completion, summarization
- **Multimodal understanding** - Process images, audio, video, and documents
- **Function calling** - Let the model invoke your functions
- **Structured output** - Generate valid JSON matching your schema
- **Code execution** - Run Python code in a sandboxed environment
- **Context caching** - Cache large contexts for efficiency
- **Embeddings** - Generate text embeddings for semantic search
- **Batch processing** - Process large volumes asynchronously
- **Live API** - Real-time bidirectional streaming

## Current Gemini Models

| Model | Context | Best For |
|-------|---------|----------|
| `gemini-3-pro-preview` | 1M tokens | Complex reasoning, coding, research |
| `gemini-3-flash-preview` | 1M tokens | Fast, balanced performance, multimodal |
| `gemini-3-pro-image-preview` | 65k / 32k tokens | Image generation and editing |

> [!IMPORTANT]
> Models like `gemini-2.5-*`, `gemini-2.0-*`, `gemini-1.5-*` are legacy and deprecated. Use the new models above.

## SDKs

| Language | Package | Install |
|----------|---------|---------|
| **Python** | `google-genai` | `pip install google-genai` |
| **JavaScript/TypeScript** | `@google/genai` | `npm install @google/genai` |
| **Go** | `google.golang.org/genai` | `go get google.golang.org/genai` |
| **Java** | `com.google.genai:google-genai` | See Maven Central for latest version |

> [!WARNING]
> Legacy SDKs `google-generativeai` (Python) and `@google/generative-ai` (JS) are deprecated. Migrate to the new SDKs above.

## Quick Start

### Python
```python
from google import genai

client = genai.Client()
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Explain quantum computing"
)
print(response.text)
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({});
const response = await ai.models.generateContent({
  model: "gemini-3-flash-preview",
  contents: "Explain quantum computing"
});
console.log(response.text);
```

### Go
```go
package main

import (
	"context"
	"fmt"
	"log"
	"google.golang.org/genai"
)

func main() {
	ctx := context.Background()
	client, err := genai.NewClient(ctx, nil)
	if err != nil {
		log.Fatal(err)
	}

	resp, err := client.Models.GenerateContent(
		ctx,
		"gemini-3-flash-preview",
		genai.Text("Explain quantum computing"),
		nil,
	)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println(resp.Text)
}
```

### Java
```java
import com.google.genai.Client;
import com.google.genai.types.GenerateContentResponse;

public class GenerateTextFromTextInput {
  public static void main(String[] args) {
    Client client = new Client();
    GenerateContentResponse response =
        client.models.generateContent(
            "gemini-3-flash-preview",
            "Explain quantum computing",
            null);

    System.out.println(response.text());
  }
}
```

### REST API
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": [{
      "parts":[{
        "text": "Explain quantum computing"}]
      }]
    }'
```

## API spec (source of truth)

**Always use the latest REST API discovery spec as the source of truth for API definitions:**

- **v1beta** (default): `https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta`  
  Use this unless the integration is explicitly pinned to v1.
- **v1**: `https://generativelanguage.googleapis.com/$discovery/rest?version=v1`  
  Use only when the integration is specifically set to v1.

## Documentation

**llms.txt URL**: `https://ai.google.dev/gemini-api/docs/llms.txt`

Fetch this index to discover available documentation pages (in `.md.txt` format).

### Key Documentation Pages

- [Models](https://ai.google.dev/gemini-api/docs/models.md.txt)
- [Google AI Studio quickstart](https://ai.google.dev/gemini-api/docs/ai-studio-quickstart.md.txt)
- [Nano Banana image generation](https://ai.google.dev/gemini-api/docs/image-generation.md.txt)
- [Function calling](https://ai.google.dev/gemini-api/docs/function-calling.md.txt)
- [Structured outputs](https://ai.google.dev/gemini-api/docs/structured-output.md.txt)
- [Text generation](https://ai.google.dev/gemini-api/docs/text-generation.md.txt)
- [Image understanding](https://ai.google.dev/gemini-api/docs/image-understanding.md.txt)
- [Embeddings](https://ai.google.dev/gemini-api/docs/embeddings.md.txt)
- [Interactions API](https://ai.google.dev/gemini-api/docs/interactions.md.txt)
- [SDK migration guide](https://ai.google.dev/gemini-api/docs/migrate.md.txt) 

Here is their documentation:
https://ai.google.dev/gemini-api/docs

They have a python, go, js, java, C# and REST API methods

## Reference Documentation

| Reference | File | Contents | Source URL |
|-----------|------|----------|------------|
| Context Caching | `references/caching.md` | Cache large contexts for cost optimization and repeated queries | https://ai.google.dev/gemini-api/docs/caching |
| Batch Processing | `references/batching.md` | Process large volumes asynchronously with batch jobs | https://ai.google.dev/gemini-api/docs/batch-api |
| Live API | `references/live-api.md` | Real-time streaming, bidirectional communication, audio/video streaming | https://ai.google.dev/gemini-api/docs/live |
| Function Calling | `references/function-calling.md` | Define and invoke functions, tool definitions, parallel calls | https://ai.google.dev/gemini-api/docs/function-calling |
| Structured Output | `references/structured-output.md` | JSON schemas, type-safe outputs, Pydantic integration | https://ai.google.dev/gemini-api/docs/structured-output |
| Embeddings | `references/embeddings.md` | Text embeddings, semantic search, vector operations | https://ai.google.dev/gemini-api/docs/embeddings |
| Multimodal | `references/multimodal.md` | Images, audio, video, document processing | https://ai.google.dev/gemini-api/docs/text-generation |
| Error Handling | `references/error-handling.md` | Error types, retry strategies, rate limits | https://ai.google.dev/gemini-api/docs/rate-limits |
| REST API | `references/rest-api.md` | Direct REST API usage, authentication, endpoints | https://ai.google.dev/api |

**When to load references:**
- Optimizing costs with repeated context → Load `caching.md`
- Processing large datasets → Load `batching.md`
- Building real-time applications → Load `live-api.md`
- Integrating with external tools → Load `function-calling.md`
- Needing type-safe outputs → Load `structured-output.md`
- Building search/retrieval systems → Load `embeddings.md`
- Working with non-text content → Load `multimodal.md`
- Handling API failures → Load `error-handling.md`
- Using REST directly → Load `rest-api.md`

## Environment Setup

### API Key (Google AI Studio)
```bash
export GEMINI_API_KEY="your-api-key"
```

### Google Cloud (Vertex AI)
```bash
export GOOGLE_CLOUD_PROJECT="your-project-id"
export GOOGLE_CLOUD_LOCATION="us-central1"
# Uses Application Default Credentials (ADC)
```

### Python Client Initialization
```python
from google import genai

# Using API key
client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

# Using Vertex AI
client = genai.Client(vertexai=True, project="your-project", location="us-central1")
```

### Node.js Client Initialization
```typescript
import { GoogleGenAI } from "@google/genai";

// Using API key
const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Using Vertex AI
const ai = new GoogleGenAI({ vertexai: true, project: "your-project", location: "us-central1" });
```

### Go Client Initialization
```go
import "google.golang.org/genai"

// Using API key
client, err := genai.NewClient(ctx, &genai.ClientConfig{
    APIKey: os.Getenv("GEMINI_API_KEY"),
})

// Using Vertex AI
client, err := genai.NewClient(ctx, &genai.ClientConfig{
    Backend: genai.BackendVertexAI,
    Project: "your-project",
    Location: "us-central1",
})
```

## Best Practices

1. **Use the new SDKs** - Migrate from legacy SDKs urgently
2. **Implement retry logic** - Handle transient failures gracefully
3. **Use structured output** - For type-safe responses
4. **Cache large contexts** - For cost optimization with repeated queries
5. **Batch large volumes** - For efficient processing
6. **Handle rate limits** - Implement exponential backoff
7. **Validate inputs** - Ensure content meets safety guidelines
8. **Monitor token usage** - Track costs and optimize prompts
9. **Use appropriate models** - Match model capabilities to use case
10. **Quote special characters** - In REST API requests

## Common Patterns

### Streaming Responses
```python
# Python
for chunk in client.models.generate_content_stream(
    model="gemini-3-flash-preview",
    contents="Tell me a long story"
):
    print(chunk.text, end="")
```

```typescript
// TypeScript
const response = await ai.models.generateContentStream({
  model: "gemini-3-flash-preview",
  contents: "Tell me a long story"
});
for await (const chunk of response) {
  console.log(chunk.text);
}
```

### Multi-turn Chat
```python
# Python
chat = client.chats.create(model="gemini-3-flash-preview")
response = chat.send_message("Hello!")
response = chat.send_message("What's the weather?")
```

### System Instructions
```python
# Python
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Explain quantum computing",
    config=types.GenerateContentConfig(
        system_instruction="You are a helpful physics professor."
    )
)
```

## Troubleshooting

### Common Issues

1. **API key not working** - Verify key is from Google AI Studio, not legacy
2. **Model not found** - Use current model names (gemini-3-*), not legacy
3. **Rate limit exceeded** - Implement retry with exponential backoff
4. **Content blocked** - Check safety settings and content policy
5. **Token limit exceeded** - Use context caching or truncate content
6. **Structured output invalid** - Validate JSON schema and add examples

### Debug Mode
```python
# Python - Enable HTTP logging
import logging
logging.basicConfig(level=logging.DEBUG)
```

```bash
# cURL - Verbose output
curl -v "https://generativelanguage.googleapis.com/v1beta/models/..."
```

## Recrawling Documentation

To update this skill with the latest documentation:

1. **Main docs index**: https://ai.google.dev/gemini-api/docs
2. **API reference**: https://ai.google.dev/api
3. **llms.txt index**: https://ai.google.dev/gemini-api/docs/llms.txt
4. **REST API spec (v1beta)**: https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta

Use the skill-crawler skill with playwright-cli to recrawl:
```bash
playwright-cli open https://ai.google.dev/gemini-api/docs --persistent
playwright-cli snapshot --filename=gemini-docs-main.yaml
# ... navigate and capture specific pages
playwright-cli close
```

---

For detailed information on specific topics, load the relevant reference files from the `references/` directory.
