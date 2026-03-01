# REST API

> **Source URL**: https://ai.google.dev/api  
> **Last Crawled**: 2026-03-02  
> **API Spec**: https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta

## Overview

The Gemini REST API provides direct HTTP access to Gemini models. Use the REST API when SDKs are not available or for specific integration requirements.

## Base URLs

| Version | URL |
|---------|-----|
| v1beta | `https://generativelanguage.googleapis.com/v1beta` |
| v1 | `https://generativelanguage.googleapis.com/v1` |

## Authentication

### API Key (Header)
```bash
curl -H "X-Goog-Api-Key: $API_KEY" \
  https://generativelanguage.googleapis.com/v1beta/models
```

### API Key (Query Parameter)
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY"
```

### OAuth 2.0 (Vertex AI)
```bash
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  https://us-central1-aiplatform.googleapis.com/v1/projects/PROJECT/locations/us-central1/publishers/google/models/gemini-3-flash-preview:generateContent
```

## Core Endpoints

### List Models
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=$API_KEY"
```

Response:
```json
{
  "models": [
    {
      "name": "models/gemini-3-flash-preview",
      "version": "001",
      "displayName": "Gemini 3 Flash Preview",
      "description": "Fast and versatile model",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ]
    }
  ]
}
```

### Generate Content
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": {
      "role": "user",
      "parts": {
        "text": "Explain quantum computing in simple terms"
      }
    },
    "generationConfig": {
      "temperature": 0.7,
      "maxOutputTokens": 1024,
      "topP": 0.95,
      "topK": 40
    }
  }'
```

### Stream Generate Content
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": {
      "parts": {
        "text": "Tell me a long story"
      }
    }
  }'
```

### Count Tokens
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:countTokens?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": {
      "parts": {
        "text": "The quick brown fox"
      }
    }
  }'
```

### Embed Content
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "content": {
      "parts": {
        "text": "The quick brown fox"
      }
    }
  }'
```

## Multimodal Requests

### Image Input
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": {
      "role": "user",
      "parts": [
        {
          "text": "Describe this image"
        },
        {
          "inlineData": {
            "mimeType": "image/jpeg",
            "data": "'$(base64 -i image.jpg)'"
          }
        }
      ]
    }
  }'
```

### Multiple Images
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": {
      "parts": [
        {"text": "Compare these images"},
        {"inlineData": {"mimeType": "image/jpeg", "data": "BASE64_IMAGE_1"}},
        {"inlineData": {"mimeType": "image/jpeg", "data": "BASE64_IMAGE_2"}}
      ]
    }
  }'
```

## Request Schemas

### GenerateContentRequest
```json
{
  "contents": [Content],
  "tools": [Tool],
  "toolConfig": ToolConfig,
  "safetySettings": [SafetySetting],
  "generationConfig": GenerationConfig,
  "systemInstruction": Content
}
```

### GenerationConfig
```json
{
  "temperature": 0.7,
  "topP": 0.95,
  "topK": 40,
  "candidateCount": 1,
  "maxOutputTokens": 1024,
  "stopSequences": ["STOP"],
  "responseMimeType": "application/json",
  "responseSchema": Schema
}
```

### Content
```json
{
  "role": "user",
  "parts": [
    {
      "text": "string",
      "inlineData": {
        "mimeType": "image/jpeg",
        "data": "base64string"
      },
      "fileData": {
        "mimeType": "video/mp4",
        "fileUri": "gs://bucket/file"
      }
    }
  ]
}
```

## Response Format

### GenerateContentResponse
```json
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          {"text": "Response text here"}
        ]
      },
      "finishReason": "STOP",
      "safetyRatings": [
        {
          "category": "HARM_CATEGORY_HARASSMENT",
          "probability": "NEGLIGIBLE"
        }
      ],
      "tokenCount": 150
    }
  ],
  "usageMetadata": {
    "promptTokenCount": 10,
    "candidatesTokenCount": 150,
    "totalTokenCount": 160
  }
}
```

## File Upload

### Upload File
```bash
# Step 1: Initialize upload
curl "https://generativelanguage.googleapis.com/upload/v1beta/files?key=$API_KEY" \
  -H "X-Goog-Upload-Protocol: resumable" \
  -H "X-Goog-Upload-Command: start" \
  -H "X-Goog-Upload-Header-Content-Length: 1234567" \
  -H "X-Goog-Upload-Header-Content-Type: video/mp4" \
  -H "Content-Type: application/json" \
  -d '{"file": {"display_name": "my_video"}}'

# Step 2: Upload bytes (use upload_url from step 1)
curl "UPLOAD_URL" \
  -H "X-Goog-Upload-Protocol: resumable" \
  -H "X-Goog-Upload-Command: upload, finalize" \
  -H "Content-Length: 1234567" \
  --data-binary @video.mp4
```

## Batch Operations

### Create Batch Job
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:batchGenerateContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "requests": [
      {"contents": {"parts": [{"text": "Request 1"}]}},
      {"contents": {"parts": [{"text": "Request 2"}]}}
    ]
  }'
```

## Error Responses

### 400 Bad Request
```json
{
  "error": {
    "code": 400,
    "message": "Invalid request",
    "status": "INVALID_ARGUMENT"
  }
}
```

### 429 Rate Limit
```json
{
  "error": {
    "code": 429,
    "message": "Rate limit exceeded",
    "status": "RESOURCE_EXHAUSTED"
  }
}
```

## Python with Requests

```python
import requests
import os

API_KEY = os.environ["GEMINI_API_KEY"]
BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

def generate_content(prompt):
    url = f"{BASE_URL}/models/gemini-3-flash-preview:generateContent?key={API_KEY}"
    
    payload = {
        "contents": {
            "parts": [{"text": prompt}]
        }
    }
    
    response = requests.post(url, json=payload)
    response.raise_for_status()
    
    data = response.json()
    return data["candidates"][0]["content"]["parts"][0]["text"]

# Usage
result = generate_content("Explain REST APIs")
print(result)
```

## JavaScript/Node.js

```javascript
const fetch = require('node-fetch');

const API_KEY = process.env.GEMINI_API_KEY;
const BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';

async function generateContent(prompt) {
  const url = `${BASE_URL}/models/gemini-3-flash-preview:generateContent?key=${API_KEY}`;
  
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: {
        parts: [{ text: prompt }]
      }
    })
  });
  
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  
  const data = await response.json();
  return data.candidates[0].content.parts[0].text;
}

// Usage
generateContent('Explain REST APIs')
  .then(console.log)
  .catch(console.error);
```

## Best Practices

1. **Use SDKs when possible**: Simpler error handling and retry logic
2. **Handle errors**: Check status codes and response bodies
3. **Rate limiting**: Implement exponential backoff for 429s
4. **Security**: Never expose API keys in client-side code
5. **Timeouts**: Set appropriate request timeouts
6. **JSON encoding**: Properly escape special characters
7. **Base64 encoding**: For inline data (images, etc.)

---

**Recrawl Sources**:
- API Reference: https://ai.google.dev/api
- REST Spec: https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta
