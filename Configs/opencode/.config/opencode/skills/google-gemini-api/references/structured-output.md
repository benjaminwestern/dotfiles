# Structured Output

> **Source URL**: https://ai.google.dev/gemini-api/docs/structured-output  
> **Last Crawled**: 2026-03-02

## Overview

Structured output allows you to generate valid JSON that conforms to a specified schema. This ensures type-safe, machine-readable responses for integration with applications and databases.

## When to Use

- API responses requiring specific formats
- Data extraction and parsing
- Configuration generation
- Form filling and validation
- Any use case needing consistent, parseable output

## Basic Usage

### Python with Pydantic
```python
from google import genai
from google.genai import types
from pydantic import BaseModel

client = genai.Client()

# Define schema with Pydantic
class Recipe(BaseModel):
    name: str
    ingredients: list[str]
    instructions: list[str]
    prep_time_minutes: int
    servings: int

# Generate structured output
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Generate a recipe for chocolate chip cookies",
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=Recipe
    )
)

# Parse result
import json
recipe = Recipe(**json.loads(response.text))
print(recipe.name)
print(recipe.ingredients)
```

### Python with Dict Schema
```python
# Define schema as dict
schema = {
    "type": "object",
    "properties": {
        "name": {"type": "string"},
        "ingredients": {
            "type": "array",
            "items": {"type": "string"}
        },
        "prep_time_minutes": {"type": "integer"}
    },
    "required": ["name", "ingredients"]
}

response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Generate a recipe",
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=schema
    )
)
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Define schema
const recipeSchema = {
  type: "object",
  properties: {
    name: { type: "string" },
    ingredients: {
      type: "array",
      items: { type: "string" }
    },
    instructions: {
      type: "array",
      items: { type: "string" }
    },
    prepTimeMinutes: { type: "integer" },
    servings: { type: "integer" }
  },
  required: ["name", "ingredients", "instructions"]
};

const response = await ai.models.generateContent({
  model: "gemini-3-flash-preview",
  contents: "Generate a recipe for chocolate chip cookies",
  config: {
    responseMimeType: "application/json",
    responseSchema: recipeSchema
  }
});

const recipe = JSON.parse(response.text);
console.log(recipe.name);
```

### Go
```go
import "google.golang.org/genai"

ctx := context.Background()
client, err := genai.NewClient(ctx, nil)

// Define schema
schema := &genai.Schema{
    Type: "object",
    Properties: map[string]*genai.Schema{
        "name": {Type: "string"},
        "ingredients": {
            Type: "array",
            Items: &genai.Schema{Type: "string"},
        },
        "prep_time_minutes": {Type: "integer"},
    },
    Required: []string{"name", "ingredients"},
}

resp, err := client.Models.GenerateContent(ctx, "gemini-3-flash-preview",
    genai.Text("Generate a recipe for chocolate chip cookies"),
    &genai.GenerateContentConfig{
        ResponseMIMEType: "application/json",
        ResponseSchema:   schema,
    })
```

## JSON Schema Types

### Primitive Types
```json
{
  "type": "object",
  "properties": {
    "name": {"type": "string"},
    "age": {"type": "integer"},
    "score": {"type": "number"},
    "active": {"type": "boolean"}
  }
}
```

### Arrays
```json
{
  "type": "object",
  "properties": {
    "tags": {
      "type": "array",
      "items": {"type": "string"}
    },
    "matrix": {
      "type": "array",
      "items": {
        "type": "array",
        "items": {"type": "number"}
      }
    }
  }
}
```

### Nested Objects
```json
{
  "type": "object",
  "properties": {
    "person": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "address": {
          "type": "object",
          "properties": {
            "street": {"type": "string"},
            "city": {"type": "string"}
          }
        }
      }
    }
  }
}
```

### Enums
```json
{
  "type": "object",
  "properties": {
    "priority": {
      "type": "string",
      "enum": ["low", "medium", "high"]
    },
    "status": {
      "type": "string",
      "enum": ["pending", "active", "completed"]
    }
  }
}
```

### Optional Fields
```json
{
  "type": "object",
  "properties": {
    "required_field": {"type": "string"},
    "optional_field": {"type": "string"}
  },
  "required": ["required_field"]
}
```

## Advanced Patterns

### List Extraction
```python
class Person(BaseModel):
    name: str
    age: int

class PeopleList(BaseModel):
    people: list[Person]

response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Extract people from: John is 30, Jane is 25",
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=PeopleList
    )
)

people = PeopleList(**json.loads(response.text))
for person in people.people:
    print(f"{person.name}: {person.age}")
```

### Enum Extraction
```python
from enum import Enum

class Sentiment(str, Enum):
    POSITIVE = "positive"
    NEGATIVE = "negative"
    NEUTRAL = "neutral"

class Analysis(BaseModel):
    text: str
    sentiment: Sentiment
    confidence: float

response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="Analyze: I love this product!",
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=Analysis
    )
)
```

## Error Handling

```python
import json

try:
    response = client.models.generate_content(...)
    data = json.loads(response.text)
    
    # Validate with Pydantic
    recipe = Recipe(**data)
except json.JSONDecodeError as e:
    print(f"Invalid JSON: {e}")
except ValidationError as e:
    print(f"Schema validation failed: {e}")
```

## Best Practices

1. **Use Pydantic**: For type safety and validation
2. **Clear descriptions**: Describe fields in schema
3. **Examples**: Include examples for complex fields
4. **Required fields**: Explicitly mark required fields
5. **Enum values**: Use enums for categorical data
6. **Error handling**: Always validate output
7. **Schema size**: Keep schemas under 32k tokens

## Limitations

- Maximum schema size: 32k tokens
- JSON only (no XML or YAML)
- Nested depth limit: 10 levels
- Cannot generate recursive schemas

## Debugging

```python
# Print raw response
print(response.text)

# Check for parsing errors
try:
    data = json.loads(response.text)
except json.JSONDecodeError as e:
    print(f"Parse error: {e}")
    print(f"Raw: {response.text}")
```

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/structured-output
