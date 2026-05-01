---
name: keep:analyze
version: "1.0"
triggers: ["/keep:analyze", "/keep:analyze artifact", "/keep:large file", "/keep:process large", "/keep:chunk analysis"]
routes_to: ["sprint"]
description: >
  Analyze large artifacts using RLM-style chunk+parallel+merge pipeline.
  TRIGGER when: user asks to analyze a large file/codebase/log, or when an artifact
  is too large for single-context processing. Combines KV store, JSON contracts,
  recursion guard, and token chunking into a complete pipeline.
resources: ['subagents', 'mind']
---

# Analyze Large Artifact

RLM-shaped pipeline for processing artifacts that exceed single-context capacity.

## Pipeline

### Step 1: Estimate & Strategy

```bash
strategy=$(token-strategy <file>)
tokens=$(token-estimate <file>)
echo "Artifact: <file> (~${tokens} tokens) -> strategy: $strategy"
```

| Strategy | Action |
|----------|--------|
| `direct` | Read file directly, single-pass analysis |
| `chunk` | Split into chunks, parallel sub-agent analysis, merge |
| `reject` | Warn user — artifact too large, suggest manual splitting |

### Step 2: Chunk (if needed)

```bash
if [ "$strategy" = "chunk" ]; then
  chunks=($(token-chunk <file>))
  echo "Split into ${#chunks[@]} chunks"
fi
```

### Step 3: Parallel Sub-agent Analysis

For each chunk, dispatch a sub-agent with the JSON contract:

```
"Analyze this artifact chunk [N/TOTAL]. Focus on: [analysis goal].
Return JSON: {summary: str, confidence: 0-1, findings: [...], deeper_question: str|null, status: done|need_more|error}"
```

Sub-agents write results to KV store:
```bash
kv-set "chunk-${N}-result" "<sub-agent output>"
```

**Recursion control**:
- `recursion-enter` before dispatching each sub-agent
- `recursion-exit` after sub-agent completes
- If `deeper_question` is non-null AND recursion depth < cap -> spawn child sub-agent

### Step 4: Merge

Read all chunk results from KV store:
```bash
for key in $(kv-ls | grep chunk-); do
  kv-get "$key"
done
```

Synthesize findings across chunks. Deduplicate and rank by confidence.

### Step 5: Optional Synthesis Agent

If findings are complex or contradictory, spawn a synthesis sub-agent:
```
"You have findings from N analysis chunks. Synthesize into a coherent report.
Deduplicate findings. Rank by confidence. Highlight contradictions.
Return JSON: {summary, confidence, findings, deeper_question, status}"
```

## Output Format

```
## Analysis Report
- Artifact: <file> (<tokens> tokens, <N> chunks)
- Strategy: direct|chunk|reject
- Confidence: <aggregate 0-1>

### Findings
1. [severity] <finding> (confidence: 0.X, source: chunk N)

### Synthesis
<merged analysis>

### Follow-up
- <deeper questions from sub-agents, if any>
```

## Shortcuts

| User says | What to do |
|-----------|-----------|
| `/keep:analyze <file>` | Full pipeline on file |
| `/keep:analyze quick <file>` | Direct read (skip chunking, <30k tokens only) |
| `/keep:analyze deep <file>` | Force chunking + synthesis agent |

## Safety

- Respect recursion cap (default: 3) — never spawn unbounded sub-agents
- Token estimation is approximate (bytes/4) — add 20% safety margin
- If a chunk sub-agent returns `status: error`, skip it and continue with remaining chunks
- Never pass raw sub-agent output to user — always synthesize first
