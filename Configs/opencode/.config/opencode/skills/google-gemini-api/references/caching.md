# Context Caching

> **Source URL**: https://ai.google.dev/gemini-api/docs/caching  
> **Last Crawled**: 2026-03-02  
> **Related**: https://ai.google.dev/gemini-api/docs/long-context

## Overview

Context caching allows you to cache large contexts (system instructions, documents, etc.) and reuse them across multiple requests. This significantly reduces costs and latency for repeated queries with the same context.

## When to Use

- Large system instructions that don't change
- Reference documents used across multiple queries
- Few-shot examples that remain constant
- Any repeated context over 32k tokens

## Cost Benefits

- **Storage cost**: Charged per hour for cached content
- **Input savings**: Cached tokens cost significantly less than fresh input tokens
- **Break-even**: Caching is cost-effective after ~4-5 queries with the same context

## Basic Usage

### Python
```python
from google import genai
from google.genai import types

client = genai.Client()

# Create cached content
cached_content = client.caches.create(
    model="gemini-3-flash-preview",
    config=types.CreateCachedContentConfig(
        contents="Large system instruction or document...",
        system_instruction="Optional system instruction",
        ttl="3600s"  # Time-to-live in seconds (1 hour)
    )
)

# Use cached content in generation
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="User query here",
    config=types.GenerateContentConfig(
        cached_content=cached_content.name
    )
)
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Create cached content
const cachedContent = await ai.caches.create({
  model: "gemini-3-flash-preview",
  config: {
    contents: "Large system instruction or document...",
    ttl: "3600s"
  }
});

// Use cached content
const response = await ai.models.generateContent({
  model: "gemini-3-flash-preview",
  contents: "User query here",
  config: {
    cachedContent: cachedContent.name
  }
});
```

### Go
```go
import "google.golang.org/genai"

ctx := context.Background()
client, err := genai.NewClient(ctx, nil)

// Create cached content
cachedContent, err := client.Caches.Create(ctx, "gemini-3-flash-preview", &genai.CreateCachedContentConfig{
    Contents: "Large system instruction or document...",
    TTL: "3600s",
})

// Use cached content
resp, err := client.Models.GenerateContent(ctx, "gemini-3-flash-preview", 
    genai.Text("User query here"),
    &genai.GenerateContentConfig{
        CachedContent: cachedContent.Name,
    })
```

## Managing Cached Content

### List Cached Content
```python
# Python
for cache in client.caches.list():
    print(f"{cache.name}: {cache.expire_time}")
```

### Update TTL
```python
# Python
client.caches.update(
    name=cached_content.name,
    config=types.UpdateCachedContentConfig(
        ttl="7200s"  # Extend to 2 hours
    )
)
```

### Delete Cached Content
```python
# Python
client.caches.delete(name=cached_content.name)
```

## Configuration Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `contents` | string | The content to cache |
| `system_instruction` | string | Optional system instruction to include |
| `ttl` | string | Time-to-live (e.g., "3600s", "2h") |
| `expire_time` | timestamp | Explicit expiration time (alternative to ttl) |

## Best Practices

1. **Minimum size**: Only cache content over 32k tokens
2. **TTL selection**: Set based on expected query frequency
3. **Reuse strategy**: Share cache across related queries
4. **Cache naming**: Use descriptive names for management
5. **Monitoring**: Track cache hit rates and costs

## Limitations

- Minimum cacheable content: 32k tokens
- Maximum TTL: 1 hour (configurable)
- Cache is regional
- Not available for all model versions

## Pricing

- Cache storage: ~$0.50 per 1M tokens per hour
- Cached input tokens: ~50% cheaper than fresh tokens
- See official pricing page for current rates

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/caching
