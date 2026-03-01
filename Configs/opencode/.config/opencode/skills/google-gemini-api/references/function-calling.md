# Function Calling

> **Source URL**: https://ai.google.dev/gemini-api/docs/function-calling  
> **Last Crawled**: 2026-03-02  
> **Related**: https://ai.google.dev/gemini-api/docs/live-tools

## Overview

Function calling allows Gemini models to invoke external functions you define. The model generates structured function calls based on user queries, enabling integration with APIs, databases, and custom logic.

## When to Use

- Integrating with external APIs
- Database queries and operations
- Calculations and data processing
- Accessing real-time information
- Multi-step workflows

## Basic Usage

### Python
```python
from google import genai
from google.genai import types

client = genai.Client()

# Define function
def get_weather(location: str) -> str:
    """Get weather for a location."""
    # Implementation here
    return f"Weather in {location}: Sunny, 22°C"

# Configure tool
tool = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="get_weather",
            description="Get the current weather for a location",
            parameters=types.Schema(
                type="object",
                properties={
                    "location": types.Schema(
                        type="string",
                        description="City name, e.g., London"
                    )
                },
                required=["location"]
            )
        )
    ]
)

# Generate with tool
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="What's the weather in London?",
    config=types.GenerateContentConfig(
        tools=[tool]
    )
)

# Check for function calls
if response.function_calls:
    function_call = response.function_calls[0]
    if function_call.name == "get_weather":
        result = get_weather(**function_call.args)
        print(result)
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Define function
async function getWeather(location: string): Promise<string> {
  return `Weather in ${location}: Sunny, 22°C`;
}

// Generate with tool
const response = await ai.models.generateContent({
  model: "gemini-3-flash-preview",
  contents: "What's the weather in London?",
  config: {
    tools: [{
      functionDeclarations: [{
        name: "get_weather",
        description: "Get the current weather for a location",
        parameters: {
          type: "object",
          properties: {
            location: {
              type: "string",
              description: "City name, e.g., London"
            }
          },
          required: ["location"]
        }
      }]
    }]
  }
});

// Handle function call
if (response.functionCalls) {
  const functionCall = response.functionCalls[0];
  if (functionCall.name === "get_weather") {
    const result = await getWeather(functionCall.args.location);
    console.log(result);
  }
}
```

### Go
```go
import "google.golang.org/genai"

ctx := context.Background()
client, err := genai.NewClient(ctx, nil)

// Define tool
tool := &genai.Tool{
    FunctionDeclarations: []*genai.FunctionDeclaration{
        {
            Name:        "get_weather",
            Description: "Get the current weather for a location",
            Parameters: &genai.Schema{
                Type: "object",
                Properties: map[string]*genai.Schema{
                    "location": {
                        Type:        "string",
                        Description: "City name, e.g., London",
                    },
                },
                Required: []string{"location"},
            },
        },
    },
}

resp, err := client.Models.GenerateContent(ctx, "gemini-3-flash-preview",
    genai.Text("What's the weather in London?"),
    &genai.GenerateContentConfig{
        Tools: []*genai.Tool{tool},
    })
```

## Multi-turn Function Calling

```python
# Python - Complete conversation flow
chat = client.chats.create(
    model="gemini-3-flash-preview",
    config=types.GenerateContentConfig(tools=[tool])
)

# User query
response = chat.send_message("What's the weather in London?")

# Model requests function call
if response.function_calls:
    function_call = response.function_calls[0]
    result = get_weather(**function_call.args)
    
    # Send result back to model
    response = chat.send_message(
        types.Content(
            role="function",
            parts=[types.Part(function_response=types.FunctionResponse(
                name=function_call.name,
                response={"result": result}
            ))]
        )
    )
    print(response.text)  # Final response
```

## Parallel Function Calls

Gemini can call multiple functions in parallel:

```python
# Python
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents="What's the weather in London, Paris, and Tokyo?",
    config=types.GenerateContentConfig(tools=[weather_tool])
)

# Handle multiple function calls
if response.function_calls:
    results = []
    for function_call in response.function_calls:
        result = get_weather(**function_call.args)
        results.append({
            "name": function_call.name,
            "result": result
        })
```

## Advanced Schema Types

```python
# Complex object parameters
tool = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="create_order",
            description="Create a new order",
            parameters=types.Schema(
                type="object",
                properties={
                    "items": types.Schema(
                        type="array",
                        items=types.Schema(
                            type="object",
                            properties={
                                "product_id": types.Schema(type="string"),
                                "quantity": types.Schema(type="integer"),
                                "price": types.Schema(type="number")
                            }
                        )
                    ),
                    "shipping_address": types.Schema(
                        type="object",
                        properties={
                            "street": types.Schema(type="string"),
                            "city": types.Schema(type="string"),
                            "country": types.Schema(type="string")
                        }
                    ),
                    "priority": types.Schema(
                        type="string",
                        enum=["low", "medium", "high"]
                    )
                }
            )
        )
    ]
)
```

## Tool Choice

Force or disable function calling:

```python
# Force specific function
config=types.GenerateContentConfig(
    tools=[tool],
    tool_config=types.ToolConfig(
        function_calling_config=types.FunctionCallingConfig(
            mode="ANY",  # or "NONE", "AUTO"
            allowed_function_names=["get_weather"]
        )
    )
)
```

## Best Practices

1. **Clear descriptions**: Describe functions and parameters precisely
2. **Type safety**: Use proper JSON schema types
3. **Error handling**: Handle function execution errors gracefully
4. **Validation**: Validate arguments before executing
5. **Timeouts**: Set timeouts for external API calls
6. **Rate limiting**: Implement rate limiting for expensive operations

## Limitations

- Maximum 128 functions per request
- Function name length: max 64 characters
- Nested object depth: max 5 levels
- Total schema size: max 32k tokens

## Debugging

```python
# Print function call details
print(f"Function: {function_call.name}")
print(f"Arguments: {function_call.args}")

# Check model's reasoning
print(response.candidates[0].content.parts)
```

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/function-calling
