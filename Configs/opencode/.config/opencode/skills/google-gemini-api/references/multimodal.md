# Multimodal

> **Source URL**: https://ai.google.dev/gemini-api/docs/text-generation  
> **Last Crawled**: 2026-03-02 > **Related**: https://ai.google.dev/gemini-api/docs/image-understanding, https://ai.google.dev/gemini-api/docs/document-processing

## Overview

Gemini models are natively multimodal, meaning they can process and understand text, images, video, audio, and documents in a single request. This enables rich interactions like analyzing images, understanding videos, and processing PDFs.

## Supported Modalities

- **Text** - Standard text input/output
- **Images** - JPEG, PNG, WebP, HEIC, HEIF
- **Video** - MP4, MOV, MPEG, MPGA, WEBM
- **Audio** - MP3, WAV, OGG, FLAC, AAC
- **Documents** - PDF (treated as images)

## Image Understanding

### Python
```python
from google import genai
from google.genai import types
import base64

client = genai.Client()

# Load image
with open("image.jpg", "rb") as f:
    image_data = f.read()

# Generate with image
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        "Describe this image in detail",
        types.Part.from_bytes(data=image_data, mime_type="image/jpeg")
    ]
)
print(response.text)
```

### JavaScript/TypeScript
```typescript
import { GoogleGenAI } from "@google/genai";
import fs from "fs";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Load image
const imageData = fs.readFileSync("image.jpg");

const response = await ai.models.generateContent({
  model: "gemini-3-flash-preview",
  contents: [
    "Describe this image in detail",
    {
      inlineData: {
        data: imageData.toString("base64"),
        mimeType: "image/jpeg"
      }
    }
  ]
});

console.log(response.text);
```

### Multiple Images
```python
# Python - Compare multiple images
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        "Compare these two images and list the differences:",
        types.Part.from_bytes(data=image1_data, mime_type="image/jpeg"),
        types.Part.from_bytes(data=image2_data, mime_type="image/jpeg")
    ]
)
```

## Video Understanding

### Python
```python
# Upload video file
video_file = client.files.upload(file="video.mp4")

# Wait for processing
import time
while video_file.state == "PROCESSING":
    time.sleep(5)
    video_file = client.files.get(name=video_file.name)

# Generate with video
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        "Summarize the key events in this video",
        video_file
    ]
)
```

### Video Frames Extraction
```python
import cv2

# Extract frames from video
cap = cv2.VideoCapture("video.mp4")
frames = []
frame_count = 0

while True:
    ret, frame = cap.read()
    if not ret:
        break
    
    # Extract 1 frame per second
    if frame_count % int(cap.get(cv2.CAP_PROP_FPS)) == 0:
        _, buffer = cv2.imencode(".jpg", frame)
        frames.append(buffer.tobytes())
    
    frame_count += 1

cap.release()

# Analyze frames
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        "Describe what happens in these video frames:",
        *[types.Part.from_bytes(data=f, mime_type="image/jpeg") for f in frames[:10]]
    ]
)
```

## Audio Processing

### Python
```python
# Upload audio file
audio_file = client.files.upload(file="audio.mp3")

# Wait for processing
while audio_file.state == "PROCESSING":
    time.sleep(5)
    audio_file = client.files.get(name=audio_file.name)

# Transcribe and analyze
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        "Transcribe this audio and summarize the main points",
        audio_file
    ]
)
```

## Document Processing (PDF)

### Python
```python
# Upload PDF
pdf_file = client.files.upload(file="document.pdf")

# Wait for processing
while pdf_file.state == "PROCESSING":
    time.sleep(5)
    pdf_file = client.files.get(name=pdf_file.name)

# Extract information
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        "Extract all tables from this document and convert to markdown format",
        pdf_file
    ]
)
```

## Combined Multimodal Example

```python
# Analyze image with context
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[
        """Analyze this technical diagram and:
        1. Identify all components
        2. Explain how they connect
        3. Suggest improvements
        """,
        types.Part.from_bytes(data=diagram_data, mime_type="image/png")
    ]
)
```

## File API

Large files must be uploaded via the File API:

### Upload File
```python
# Upload with progress
video_file = client.files.upload(
    file="large_video.mp4",
    config=types.UploadFileConfig(
        mime_type="video/mp4",
        name="my_video"
    )
)

print(f"File uploaded: {video_file.name}")
print(f"URI: {video_file.uri}")
```

### List Files
```python
for file in client.files.list():
    print(f"{file.name}: {file.display_name} ({file.size_bytes} bytes)")
```

### Get File
```python
file_info = client.files.get(name="files/abc123")
print(f"State: {file_info.state}")  # PROCESSING or ACTIVE
```

### Delete File
```python
client.files.delete(name="files/abc123")
```

## Media Resolution

Control how media is processed:

```python
response = client.models.generate_content(
    model="gemini-3-flash-preview",
    contents=[prompt, image],
    config=types.GenerateContentConfig(
        media_resolution="HIGH"  # or "LOW", "MEDIUM"
    )
)
```

| Resolution | Use Case |
|------------|----------|
| `LOW` | Faster processing, lower detail |
| `MEDIUM` | Balanced quality and speed |
| `HIGH` | Maximum detail, slower |

## File Requirements

| Type | Max Size | Max Duration |
|------|----------|--------------|
| Images | 20 MB | - |
| Video | 2 GB | 1 hour |
| Audio | 200 MB | ~2 hours |
| PDF | 50 MB | 1,000 pages |

## Best Practices

1. **Resize images**: Large images are automatically resized; preprocess for control
2. **Extract key frames**: For long videos, extract representative frames
3. **File cleanup**: Delete files after use to manage storage
4. **Batch uploads**: Upload files in parallel for efficiency
5. **Error handling**: Check file state before using
6. **MIME types**: Always specify correct MIME types

## Limitations

- Maximum images per request: 3,600 (varies by model)
- Video/audio must be uploaded via File API if >20MB
- Processing time increases with media size
- Some models have different multimodal capabilities

---

**Recrawl Source**: https://ai.google.dev/gemini-api/docs/text-generation
