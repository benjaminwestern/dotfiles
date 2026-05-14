# Model-scoped system prompts

`zz-model-system.ts` appends Markdown from this directory to Pi's system prompt only when the current selected model matches the file name.

Pi models are matched by the normal Pi model identity:

```text
<provider>/<model-id>
```

The extension reads those values from `ctx.model.provider` and `ctx.model.id`. For example, if the selected model shown in Pi is:

```text
openai-codex/gpt-5.5
```

then:

```text
provider = openai-codex
model-id = gpt-5.5
```

Lookup order for each configured directory is:

1. `all.md` — every model
2. `<provider>.md` — every model from that provider
3. `<provider>/all.md` — every model from that provider, directory style
4. `<provider>/index.md` — every model from that provider, directory style
5. `<provider>/<model-id>.md` — exact model ID; slashes in the model ID may be real subdirectories
6. `<provider>/<model-id-with-slashes-as-__>.md` — exact model ID with `/` replaced by `__`
7. `<provider>__<model-id-with-slashes-as-__>.md` — flat exact-model file

Examples:

```text
model-system/
├── all.md                                  # every model
├── openai-codex.md                         # every openai-codex model
├── openai-codex/all.md                     # every openai-codex model, directory style
├── openai-codex/gpt-5.5.md                 # exact openai-codex/gpt-5.5
├── google/gemini-3-pro-preview.md          # exact google/gemini-3-pro-preview
└── fireworks/accounts/fireworks/routers/kimi-k2p6-turbo.md
```

For model IDs that contain `/`, you can either mirror the slash path or use `__` as a safe filename separator:

```text
# selected model: fireworks/accounts/fireworks/routers/kimi-k2p6-turbo
model-system/fireworks/accounts/fireworks/routers/kimi-k2p6-turbo.md
model-system/fireworks/accounts__fireworks__routers__kimi-k2p6-turbo.md
model-system/fireworks__accounts__fireworks__routers__kimi-k2p6-turbo.md
```

Project-specific prompts can live in `.pi/model-system/` and are layered from outermost ancestor to nearest project, after global prompts.

The extension registers no commands. It hot-loads matching files on every user turn, immediately before the provider request is built.

After changing prompt files, run `/reload` or start a new Pi process so the extension code/resources are refreshed. The Markdown files themselves are read fresh by the hook each turn.
