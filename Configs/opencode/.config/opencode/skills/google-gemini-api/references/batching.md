# Batch Processing

> **Source URL**: https://ai.google.dev/gemini-api/docs/batch-api  
> **Last Crawled**: 2026-03-02  
> **Related**: https://ai.google.dev/gemini-api/docs/embeddings

## Overview

The Batch API allows you to process large volumes of requests asynchronously. Instead of making individual API calls, you submit a batch job that processes all requests in the background.

## When to Use

- Processing thousands of documents
- Generating embeddings for large datasets
- Bulk content generation
- Any workload with >1000 requests
- Non-real-time processing needs

## Benefits

- **Higher throughput**: Process millions of requests
- **Cost efficiency**: Reduced pricing for batch operations
- **No rate limiting**: Bypass standard rate limits
- **Async processing**: Submit and retrieve results later

## Basic Usage

### Python
```python
from google import genai
from google.genai import types

client = genai.Client()

# Create batch job
batch_job = client.batches.create(
    model="gemini-3-flash-preview",
    requests=[
        types.BatchGenerateContentRequest(
            contents="Process document 1..."
        ),
        types.BatchGenerateContentRequest(
            contents="Process document 2..."
        ),
        # ... more requests
    ]
)

# Check status
print(f"Job state: {batch_job.state}")

# Wait for completion and get results
import time
while batch_job.state == "RUNNING":
    time.sleep(10)
    batch_job = client.batches.get(name=batch_job.name)

# Retrieve results
results = client.batches.get(name=batch_job.name)
for result in results.results:
    print(result.text)
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Create batch job
const batchJob = await ai.batches.create({
  model: "gemini-3-flash-preview",
  requests: [
    { contents: "Process document 1..." },
    { contents: "Process document 2..." },
    // ... more requests
  ]
});

// Poll for completion
while (batchJob.state === "RUNNING") {
  await new Promise(resolve => setTimeout(resolve, 10000));
  batchJob = await ai.batches.get({ name: batchJob.name });
}

// Get results
console.log(batchJob.results);
```

### Go
```go
import "google.golang.org/genai"

ctx := context.Background()
client, err := genai.NewClient(ctx, nil)

// Create batch job
batchJob, err := client.Batches.Create(ctx, "gemini-3-flash-preview", &genai.BatchCreateConfig{
    Requests: []genai.BatchGenerateContentRequest{
        {Contents: "Process document 1..."},
        {Contents: "Process document 2..."},
    },
})

// Poll for completion
for batchJob.State == "RUNNING" {
    time.Sleep(10 * time.Second)
    batchJob, err = client.Batches.Get(ctx, batchJob.Name)
}
```

## Batch Embeddings

```python
# Python - Batch embeddings
batch_job = client.batches.create(
    model="text-embedding-004",
    requests=[
        types.BatchEmbedContentRequest(
            content="Text to embed 1"
        ),
        types.BatchEmbedContentRequest(
            content="Text to embed 2"
        ),
    ]
)
```

## Managing Batch Jobs

### List Jobs
```python
# Python
for job in client.batches.list():
    print(f"{job.name}: {job.state}")
```

### Cancel Job
```python
# Python
client.batches.cancel(name=batch_job.name)
```

### Delete Job
```python
# Python
client.batches.delete(name=batch_job.name)
```

## Input Formats

### JSONL File
```bash
# Prepare input file
cat > batch_input.jsonl << 'EOF'
{"contents": "Request 1"}
{"contents": "Request 2"}
{"contents": "Request 3"}
EOF

# Upload and submit
```

### Inline Requests
```python
# Up to 100,000 requests per batch
requests = [
    types.BatchGenerateContentRequest(contents=f"Process item {i}")
    for i in range(10000)
]
```

## Job States

| State | Description |
|-------|-------------|
| `QUEUED` | Job is queued for processing |
| `RUNNING` | Job is actively processing |
| `SUCCEEDED` | All requests completed successfully |
| `FAILED` | Job failed, check error details |
| `CANCELLED` | Job was cancelled |

## Best Practices

1. **Batch size**: Optimal at 10,000+ requests
2. **Error handling**: Check individual request results
3. **Polling interval**: Start with 10 seconds, adjust based on job size
4. **File input**: Use JSONL for very large batches
5. **Monitoring**: Track job status and handle failures

## Limitations

- Maximum requests per batch: 100,000
- Maximum input size per request: Model dependent
- Job expiration: Results kept for 7 days
- No real-time streaming in batch mode

## Pricing

- Batch operations: ~50% cheaper than synchronous
- No additional fees for batch processing
- See official pricing for current rates

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/batch-api
