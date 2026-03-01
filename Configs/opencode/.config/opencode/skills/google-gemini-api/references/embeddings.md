# Embeddings

> **Source URL**: https://ai.google.dev/gemini-api/docs/embeddings  
> **Last Crawled**: 2026-03-02

## Overview

Embeddings convert text into numerical vectors that capture semantic meaning. These vectors enable semantic search, clustering, recommendation systems, and similarity comparisons.

## When to Use

- Semantic search
- Document clustering
- Recommendation systems
- Text classification
- Duplicate detection
- Semantic similarity

## Available Models

| Model | Dimensions | Description |
|-------|------------|-------------|
| `text-embedding-004` | 768 | Latest embedding model |
| `embedding-001` | 768 | Legacy model (deprecated) |

## Basic Usage

### Python
```python
from google import genai

client = genai.Client()

# Generate embedding for single text
response = client.models.embed_content(
    model="text-embedding-004",
    contents="The quick brown fox jumps over the lazy dog"
)

# Access embedding vector
embedding = response.embeddings[0].values
print(f"Embedding dimensions: {len(embedding)}")
print(f"First 5 values: {embedding[:5]}")
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

const response = await ai.models.embedContent({
  model: "text-embedding-004",
  contents: "The quick brown fox jumps over the lazy dog"
});

const embedding = response.embeddings[0].values;
console.log(`Dimensions: ${embedding.length}`);
```

### Go
```go
import "google.golang.org/genai"

ctx := context.Background()
client, err := genai.NewClient(ctx, nil)

resp, err := client.Models.EmbedContent(ctx, "text-embedding-004",
    genai.Text("The quick brown fox jumps over the lazy dog"),
    nil)

embedding := resp.Embeddings[0].Values
fmt.Printf("Dimensions: %d\n", len(embedding))
```

## Batch Embeddings

### Python
```python
# Generate embeddings for multiple texts
texts = [
    "Machine learning is fascinating",
    "Deep learning is a subset of ML",
    "Neural networks mimic the brain"
]

response = client.models.embed_content(
    model="text-embedding-004",
    contents=texts
)

for i, embedding in enumerate(response.embeddings):
    print(f"Text {i}: {len(embedding.values)} dimensions")
```

### REST API
```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=$API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "content": {
      "parts":[{
        "text": "The quick brown fox jumps over the lazy dog"
      }]
    }
  }'
```

## Similarity Calculation

```python
import numpy as np

def cosine_similarity(a, b):
    """Calculate cosine similarity between two vectors."""
    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))

# Generate embeddings
def get_embedding(text):
    response = client.models.embed_content(
        model="text-embedding-004",
        contents=text
    )
    return response.embeddings[0].values

# Compare texts
text1 = "Machine learning is fascinating"
text2 = "Deep learning is a subset of ML"
text3 = "I love pizza"

emb1 = get_embedding(text1)
emb2 = get_embedding(text2)
emb3 = get_embedding(text3)

print(f"Similarity (ML related): {cosine_similarity(emb1, emb2):.4f}")
print(f"Similarity (unrelated): {cosine_similarity(emb1, emb3):.4f}")
```

## Semantic Search

```python
class DocumentStore:
    def __init__(self):
        self.documents = []
        self.embeddings = []
    
    def add_document(self, text):
        response = client.models.embed_content(
            model="text-embedding-004",
            contents=text
        )
        self.documents.append(text)
        self.embeddings.append(response.embeddings[0].values)
    
    def search(self, query, top_k=3):
        # Get query embedding
        response = client.models.embed_content(
            model="text-embedding-004",
            contents=query
        )
        query_emb = response.embeddings[0].values
        
        # Calculate similarities
        similarities = [
            cosine_similarity(query_emb, doc_emb)
            for doc_emb in self.embeddings
        ]
        
        # Get top matches
        top_indices = np.argsort(similarities)[-top_k:][::-1]
        return [(self.documents[i], similarities[i]) for i in top_indices]

# Usage
store = DocumentStore()
store.add_document("Machine learning uses algorithms to learn from data")
store.add_document("Python is a popular programming language")
store.add_document("Deep learning uses neural networks")

results = store.search("artificial intelligence", top_k=2)
for doc, score in results:
    print(f"Score: {score:.4f} - {doc}")
```

## Task Types

Different task types optimize embeddings for specific use cases:

```python
# Semantic search (query vs document)
response = client.models.embed_content(
    model="text-embedding-004",
    contents="search query",
    config=types.EmbedContentConfig(
        task_type="RETRIEVAL_QUERY"  # or "RETRIEVAL_DOCUMENT"
    )
)

# Classification
response = client.models.embed_content(
    model="text-embedding-004",
    contents="text to classify",
    config=types.EmbedContentConfig(
        task_type="CLASSIFICATION"
    )
)

# Clustering
response = client.models.embed_content(
    model="text-embedding-004",
    contents="text to cluster",
    config=types.EmbedContentConfig(
        task_type="CLUSTERING"
    )
)
```

| Task Type | Use Case |
|-----------|----------|
| `RETRIEVAL_QUERY` | Search queries |
| `RETRIEVAL_DOCUMENT` | Documents to be searched |
| `SEMANTIC_SIMILARITY` | General similarity |
| `CLASSIFICATION` | Text classification |
| `CLUSTERING` | Document clustering |

## Vector Databases Integration

### Pinecone
```python
import pinecone

# Initialize Pinecone
pc = pinecone.Pinecone(api_key="your-pinecone-key")
index = pc.Index("my-index")

# Upsert embeddings
vectors = [
    ("id1", embedding1, {"text": "document 1"}),
    ("id2", embedding2, {"text": "document 2"}),
]
index.upsert(vectors=vectors)

# Query
results = index.query(vector=query_embedding, top_k=5)
```

### ChromaDB
```python
import chromadb

client = chromadb.Client()
collection = client.create_collection("my_collection")

# Add documents
collection.add(
    embeddings=[embedding1, embedding2],
    documents=["doc1", "doc2"],
    ids=["id1", "id2"]
)

# Query
results = collection.query(
    query_embeddings=[query_embedding],
    n_results=5
)
```

## Best Practices

1. **Normalize vectors**: For cosine similarity, normalize embeddings
2. **Batch requests**: Process multiple texts in one request
3. **Task types**: Use appropriate task types for better results
4. **Caching**: Cache embeddings for static content
5. **Dimensionality**: 768 dimensions is standard for text-embedding-004
6. **Storage**: Use vector databases for large-scale applications

## Limitations

- Maximum input length: 8,000 tokens
- Rate limits apply (see error-handling.md)
- Only text embeddings (no multimodal embeddings)

## Pricing

- Billed per 1,000 tokens of input text
- See official pricing page for current rates

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/embeddings
