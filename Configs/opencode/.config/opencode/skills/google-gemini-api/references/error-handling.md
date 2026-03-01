# Error Handling

> **Source URL**: https://ai.google.dev/gemini-api/docs/rate-limits  
> **Last Crawled**: 2026-03-02  
> **Related**: https://ai.google.dev/gemini-api/docs/troubleshooting, https://ai.google.dev/gemini-api/docs/billing

## Overview

Proper error handling ensures your application gracefully handles API failures, rate limits, and other issues. This guide covers common errors, retry strategies, and best practices.

## Common Error Types

| Error | Status Code | Description |
|-------|-------------|-------------|
| Invalid API Key | 400 | Authentication failed |
| Rate Limit | 429 | Too many requests |
| Quota Exceeded | 429 | Daily quota reached |
| Invalid Request | 400 | Malformed request |
| Model Not Found | 404 | Invalid model name |
| Content Filter | 400 | Content blocked by safety |
| Server Error | 500/503 | Temporary service issue |

## Rate Limits

### Current Limits (as of March 2026)

| Model | Requests/Min | Tokens/Min | Daily Requests |
|-------|--------------|------------|----------------|
| gemini-3-flash-preview | 2,000 | 4M | 50,000 |
| gemini-3-pro-preview | 1,000 | 2M | 25,000 |

> Note: Limits vary by tier. Check https://ai.google.dev/gemini-api/docs/rate-limits for current limits.

### Rate Limit Headers

```python
# Python - Check rate limit headers
response = client.models.generate_content(...)

# Headers available in raw response
print(f"Remaining: {response.headers.get('x-ratelimit-remaining')}")
print(f"Reset: {response.headers.get('x-ratelimit-reset')}")
```

## Retry Strategies

### Exponential Backoff

```python
import time
import random
from google.genai import errors

def generate_with_retry(client, model, contents, max_retries=5):
    for attempt in range(max_retries):
        try:
            return client.models.generate_content(
                model=model,
                contents=contents
            )
        except errors.APIError as e:
            if e.code == 429:  # Rate limit
                # Exponential backoff with jitter
                wait = (2 ** attempt) + random.uniform(0, 1)
                print(f"Rate limited. Waiting {wait:.2f}s...")
                time.sleep(wait)
            elif e.code in [500, 502, 503]:  # Server errors
                wait = (2 ** attempt)
                print(f"Server error. Waiting {wait}s...")
                time.sleep(wait)
            else:
                raise  # Don't retry other errors
    
    raise Exception("Max retries exceeded")
```

### Using Tenacity Library

```python
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
from google.genai import errors

@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=4, max=60),
    retry=retry_if_exception_type((errors.APIError, errors.ServerError))
)
def generate_content(client, model, contents):
    return client.models.generate_content(
        model=model,
        contents=contents
    )
```

## Error Handling Examples

### Python
```python
from google import genai
from google.genai import errors

client = genai.Client()

try:
    response = client.models.generate_content(
        model="gemini-3-flash-preview",
        contents="Generate content"
    )
    print(response.text)
    
except errors.InvalidAPIKeyError:
    print("Error: Invalid API key. Check your credentials.")
    
except errors.RateLimitError as e:
    print(f"Rate limit hit. Retry after: {e.retry_after} seconds")
    
except errors.QuotaExceededError:
    print("Error: Daily quota exceeded. Upgrade your plan or wait.")
    
except errors.ContentFilterError as e:
    print(f"Content blocked: {e.message}")
    print(f"Safety ratings: {e.safety_ratings}")
    
except errors.ServerError as e:
    print(f"Server error: {e.code}. Retry recommended.")
    
except errors.APIError as e:
    print(f"API error: {e.code} - {e.message}")
    
except Exception as e:
    print(f"Unexpected error: {e}")
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI, APIError } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

try {
  const response = await ai.models.generateContent({
    model: "gemini-3-flash-preview",
    contents: "Generate content"
  });
  console.log(response.text);
  
} catch (error) {
  if (error instanceof APIError) {
    switch (error.code) {
      case 400:
        console.error("Invalid request:", error.message);
        break;
      case 429:
        console.error("Rate limited. Retry after:", error.retryAfter);
        break;
      case 500:
      case 503:
        console.error("Server error, retry recommended");
        break;
      default:
        console.error(`API error ${error.code}:`, error.message);
    }
  } else {
    console.error("Unexpected error:", error);
  }
}
```

## Content Safety Handling

```python
from google import genai
from google.genai import types

client = genai.Client()

# Configure safety settings
safety_settings = [
    types.SafetySetting(
        category="HARM_CATEGORY_HARASSMENT",
        threshold="BLOCK_MEDIUM_AND_ABOVE"
    ),
    types.SafetySetting(
        category="HARM_CATEGORY_HATE_SPEECH",
        threshold="BLOCK_MEDIUM_AND_ABOVE"
    ),
]

try:
    response = client.models.generate_content(
        model="gemini-3-flash-preview",
        contents="Potentially sensitive content",
        config=types.GenerateContentConfig(
            safety_settings=safety_settings
        )
    )
    
    # Check if content was blocked
    if response.prompt_feedback.block_reason:
        print(f"Content blocked: {response.prompt_feedback.block_reason}")
        
except errors.ContentFilterError as e:
    print(f"Safety filter triggered: {e}")
```

## Circuit Breaker Pattern

```python
from enum import Enum
import time

class CircuitState(Enum):
    CLOSED = "closed"      # Normal operation
    OPEN = "open"         # Failing, reject requests
    HALF_OPEN = "half_open"  # Testing if recovered

class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout=60):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failure_count = 0
        self.state = CircuitState.CLOSED
        self.last_failure_time = None
    
    def call(self, func, *args, **kwargs):
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time > self.timeout:
                self.state = CircuitState.HALF_OPEN
            else:
                raise Exception("Circuit breaker is OPEN")
        
        try:
            result = func(*args, **kwargs)
            self.on_success()
            return result
        except Exception as e:
            self.on_failure()
            raise e
    
    def on_success(self):
        self.failure_count = 0
        self.state = CircuitState.CLOSED
    
    def on_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN

# Usage
cb = CircuitBreaker(failure_threshold=3, timeout=60)

try:
    response = cb.call(
        client.models.generate_content,
        model="gemini-3-flash-preview",
        contents="Hello"
    )
except Exception as e:
    print(f"Request failed: {e}")
```

## Token Counting for Rate Limiting

```python
# Pre-flight token count
token_response = client.models.count_tokens(
    model="gemini-3-flash-preview",
    contents="Your input content here"
)

print(f"Input tokens: {token_response.total_tokens}")

# Check if within limits
if token_response.total_tokens > 100000:  # Your threshold
    print("Warning: Large request, may hit limits")
```

## Best Practices

1. **Always use retries**: Implement exponential backoff
2. **Handle 429s gracefully**: Respect rate limits
3. **Monitor quotas**: Track usage to avoid surprises
4. **Log errors**: Include error codes and messages
5. **Circuit breakers**: Prevent cascade failures
6. **Fallback strategies**: Degrade gracefully
7. **Test failures**: Simulate errors in testing

## Debugging

```python
# Enable verbose logging
import logging
logging.basicConfig(level=logging.DEBUG)

# Check response metadata
response = client.models.generate_content(...)
print(f"Usage: {response.usage_metadata}")
print(f"Model: {response.model_version}")
```

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/rate-limits
