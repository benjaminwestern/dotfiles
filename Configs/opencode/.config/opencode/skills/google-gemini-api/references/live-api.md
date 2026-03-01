# Live API

> **Source URL**: https://ai.google.dev/gemini-api/docs/live  
> **Last Crawled**: 2026-03-02  
> **Related**: https://ai.google.dev/gemini-api/docs/live-guide, https://ai.google.dev/gemini-api/docs/live-tools, https://ai.google.dev/gemini-api/docs/live-session, https://ai.google.dev/gemini-api/docs/ephemeral-tokens

## Overview

The Live API provides real-time bidirectional streaming between your application and Gemini models. It supports streaming text, audio, and video with low latency, enabling interactive applications like voice assistants and real-time video analysis.

## When to Use

- Voice assistants and conversational AI
- Real-time video analysis
- Live transcription
- Interactive streaming applications
- Multi-modal real-time interactions

## Key Features

- **Bidirectional streaming**: Send and receive data in real-time
- **Audio streaming**: Real-time speech input and output
- **Video streaming**: Live video frame analysis
- **Low latency**: Optimized for interactive use cases
- **Session management**: Maintain context across interactions

## Basic Usage

### Python
```python
from google import genai
from google.genai import types
import asyncio

client = genai.Client()

async def live_session():
    # Start live session
    async with client.aio.live.connect(
        model="gemini-3-flash-preview",
        config=types.LiveConnectConfig(
            response_modalities=["TEXT"]  # or ["AUDIO"]
        )
    ) as session:
        # Send message
        await session.send("Hello, how are you?")
        
        # Receive streaming response
        async for response in session.receive():
            print(response.text, end="")

asyncio.run(live_session())
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

async function liveSession() {
  const session = await ai.live.connect({
    model: "gemini-3-flash-preview",
    config: {
      responseModalities: ["TEXT"]
    }
  });

  // Send message
  await session.send("Hello, how are you?");

  // Receive streaming response
  for await (const response of session.receive()) {
    console.log(response.text);
  }
}

liveSession();
```

## Audio Streaming

### Python
```python
import asyncio
from google import genai
from google.genai import types

async def audio_chat():
    async with client.aio.live.connect(
        model="gemini-3-flash-preview",
        config=types.LiveConnectConfig(
            response_modalities=["AUDIO"],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name="Aoede"
                    )
                )
            )
        )
    ) as session:
        # Stream audio input
        await session.send_audio(audio_chunk)
        
        # Receive audio response
        async for response in session.receive():
            if response.audio:
                play_audio(response.audio)
```

## Video Streaming

```python
import cv2
import asyncio
from google import genai

async def video_analysis():
    cap = cv2.VideoCapture(0)
    
    async with client.aio.live.connect(
        model="gemini-3-flash-preview",
        config=types.LiveConnectConfig(
            response_modalities=["TEXT"]
        )
    ) as session:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
                
            # Send video frame
            await session.send_video_frame(frame)
            
            # Receive analysis
            async for response in session.receive():
                print(response.text)
```

## Session Management

### Creating Sessions
```python
# Sessions are created per connection
# Each session maintains its own context
```

### Session Configuration
```python
config = types.LiveConnectConfig(
    response_modalities=["TEXT", "AUDIO"],
    system_instruction="You are a helpful assistant",
    temperature=0.7,
    max_output_tokens=1024
)
```

## Ephemeral Tokens

For client-side applications, use ephemeral tokens to avoid exposing API keys:

### Server (Generate Token)
```python
from google import genai

client = genai.Client()

# Generate ephemeral token for client
token = client.tokens.create(
    model="gemini-3-flash-preview",
    config=types.CreateTokenConfig(
        ttl="3600s",
        scopes=["live.connect"]
    )
)
```

### Client (Use Token)
```javascript
const ai = new GoogleGenAI({ ephemeralToken: tokenFromServer });
const session = await ai.live.connect({ model: "gemini-3-flash-preview" });
```

## Tool Use in Live API

```python
async def session_with_tools():
    async with client.aio.live.connect(
        model="gemini-3-flash-preview",
        config=types.LiveConnectConfig(
            response_modalities=["TEXT"],
            tools=[
                types.Tool(
                    function_declarations=[
                        types.FunctionDeclaration(
                            name="get_weather",
                            description="Get weather for a location",
                            parameters=types.Schema(
                                type="object",
                                properties={
                                    "location": types.Schema(type="string")
                                }
                            )
                        )
                    ]
                )
            ]
        )
    ) as session:
        await session.send("What's the weather in London?")
        
        async for response in session.receive():
            if response.function_calls:
                # Handle function call
                result = await handle_function_call(response.function_calls[0])
                await session.send_function_result(result)
            else:
                print(response.text)
```

## Configuration Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `response_modalities` | list | ["TEXT"], ["AUDIO"], or both |
| `system_instruction` | string | System prompt |
| `temperature` | float | 0.0 to 1.0 |
| `max_output_tokens` | int | Maximum response length |
| `tools` | list | Function declarations |
| `speech_config` | object | Voice configuration for audio |

## Best Practices

1. **Connection reuse**: Keep sessions open for related interactions
2. **Audio buffering**: Buffer audio chunks for smooth playback
3. **Error handling**: Handle connection drops gracefully
4. **Rate limiting**: Monitor streaming rate limits
5. **Resource cleanup**: Always close sessions properly

## Limitations

- Concurrent sessions limited by quota
- Audio format: PCM 16-bit, 16kHz
- Video format: JPEG frames
- Session timeout: 30 minutes of inactivity

## Pricing

- Live API uses standard token pricing
- Input/output tokens billed at standard rates
- No additional streaming fees

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/live
