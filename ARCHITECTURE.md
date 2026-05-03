# keep — Project Architecture

> Cognitive enhancement layer for AI coding assistants: persistent memory, safety guards, skill system, automated workflows
> Supports Claude Code, Codex CLI, Cursor, Windsurf, and more

## Overview

keep is an enhancement system built for AI coding assistants. It provides persistent memory storage via MCP (Model Context Protocol), implements safety guards and command optimization through hooks, and orchestrates complex workflows via the skills system.

**Core value**: Enables Claude Code to retain knowledge across sessions, automatically optimize interactions, and execute commands safely.

| Metric | Value |
|--------|-------|
| Lines of code | ~12,000 |
| Files | 100+ |
| MCP Tools | 26 |
| Hooks | 28 |
| Skills | 13 |
| Dependencies | Only `mcp` (Python) |

## Directory Structure

```
keep/
├── mem/                    # Memory MCP Server
│   ├── server.py           # Entry point: FastMCP registers all tools
│   ├── tools/              # MCP tool layer (26 tools)
│   │   ├── memory_tools.py # Memory operations (search, remember, recall, forget...)
│   │   ├── code_tools.py   # Code analysis (smart_outline, smart_search, smart_unfold)
│   │   ├── admin_tools.py  # System management (dream_cycle, stats, wakeup, lifecycle, dashboard)
│   │   └── web_tools.py    # Web memory (remember_web)
│   ├── storage/            # Persistence layer
│   │   ├── database.py     # SQLite connection + Schema migration + decision_log table
│   │   ├── observations.py # Observation record CRUD (including dedup, density gate, merge, lifecycle)
│   │   ├── synthesis.py    # Knowledge synthesis (gbrain pattern)
│   │   ├── entities.py     # Entity extraction (files/functions/tools/errors)
│   │   ├── links.py        # Inter-observation relationship graph
│   │   └── working_memory.py # Working memory store
│   ├── search/             # Retrieval engine
│   │   ├── fts.py          # FTS5 full-text search + RRF ranking
│   │   ├── expansion.py    # Query expansion (synonyms/concepts)
│   │   ├── dedup.py        # Result deduplication
│   │   ├── recall.py       # Unified retrieval (FTS + entity + synthesis)
│   │   ├── hall.py         # Hallucination detection
│   │   └── wakeup.py       # MemPalace wake-up pattern
│   ├── dream/              # Dream cycle (memory maintenance)
│   │   └── cycle.py        # Dedup → Merge → Prune → Strengthen → Backfill → Promote
│   └── codeparse/          # Multi-language symbol parser
│       ├── parser.py       # Python/TS/JS/Shell/Go/Rust
│       ├── indexer.py      # Codebase indexing
│       ├── callgraph.py    # Call graph analysis
│       ├── clustering.py   # Module clustering
│       ├── registry.py     # Project registry
│       └── process.py      # Process management
├── hooks/                  # Claude Code Hooks (28)
│   ├── safety-guard.sh     # Safety guard (blocks destructive commands)
│   ├── nto-rewrite.sh      # Command optimizer (60-90% token savings)
│   ├── env-bootstrap.sh    # Environment snapshot generation
│   ├── audit-log.sh        # Operation audit log
│   ├── auto-format.sh      # Auto code formatting
│   ├── auto-verify.sh      # Post-edit auto verification
│   ├── checkpoint.sh       # Session checkpoint
│   ├── constitutional-check.sh # Constitutional checks after reads
│   ├── codedb-reindex.sh   # CodeDB reindex trigger
│   ├── no-todo-commit.sh   # Prevent TODO commits
│   ├── perceive.sh         # Environment perception
│   ├── scope-guard.sh      # Scope protection
│   ├── session-checkpoint.sh # Session state checkpoint
│   ├── session-stop-guard.sh # Session termination safety
│   ├── stop-event.sh       # Stop event handling
│   ├── tool-cache.sh       # Tool result caching
│   ├── validate-edit.sh    # Edit validation
│   ├── protect-files.sh    # Critical file protection
│   ├── pr-gate.sh          # PR quality gate
│   ├── post-bash-scan-secrets.sh # Post-command secret scanning
│   ├── update-code-map.sh  # Code map update
│   ├── pre-compact-instructions.sh # Compaction instructions
│   ├── todo-check.sh       # TODO check
│   ├── mem-record.sh       # Memory record trigger
│   ├── mem-session.sh      # Session memory management
│   ├── mem-precompact.sh   # Pre-compaction memory save
│   ├── review-queue-inject.sh # Pre-compaction review queue injection
│   └── sync-memory-rules.sh # Memory rules sync
├── skills/                 # Claude Code Skills (13)
│   ├── sprint/             # Sprint workflow (Research→Plan→Implement)
│   │   └── references/     # Sprint methodology docs (state machine, validation ladder, etc.)
│   ├── review/             # Cross-validation code review
│   │   └── references/     # Review methodology docs (blast radius, checklists, etc.)
│   ├── deslop/             # Code de-bloat optimization
│   ├── harness/            # Harness component management
│   ├── skill-forge/         # Skill auto-creation
│   ├── onboard/            # First-run personalization wizard
│   ├── statusline/         # Token/cost/context status bar
│   ├── analyze/            # RLM chunk+parallel+merge for large files
│   ├── tdd/                # Test-driven development workflow
│   ├── design-interface/   # Interface design skill
│   ├── ambient/            # Ambient awareness
│   ├── ubiquitous-language/ # Shared vocabulary management
│   └── browser-use/        # Headless browser automation
│       ├── domain-knowledge/ # Browser domain expertise
│       └── interaction-patterns/ # Dialogs, dropdowns, iframes, shadow DOM, etc.
├── scripts/                # Utility scripts
│   ├── install.sh          # One-click deployment (Claude Code + Codex CLI harness, auto adapter detection)
│   ├── mx.sh               # Unified model switcher for Claude Code & Codex CLI (v4.0.0, 15+ models)
│   ├── adapters/           # MCP adapter configs
│   │   ├── claude-code.json
│   │   ├── codex.json      # Codex CLI (TOML config format)
│   │   ├── cursor.json
│   │   ├── windsurf.json
│   │   ├── opencode.json
│   │   └── openclaw.json
│   ├── show.py             # Terminal dashboard (memory/dream/review/activity panels)
│   ├── statusline.py       # Token/cost/context status bar script
│   ├── benchmark.py        # Performance benchmarking
│   ├── benchmark.sh        # Benchmark runner
│   ├── backup.sh           # Config backup (~/.claude + ~/.codedb)
│   ├── gold_answers.py     # Benchmark reference answers
│   ├── bench-average.py    # Benchmark result aggregation
│   ├── callgraph.py        # Call graph visualization
│   ├── artifacts.py        # Artifact management
│   └── kv-store.sh, recursion-guard.sh, token-chunk.sh, etc. # Utility scripts
└── rules/                  # Behavior rules
    ├── core.md             # Core workflow and guardrails
    ├── format.md           # Response format rules
    ├── memory-protocol.md  # Memory graph relations protocol
    └── architecture-language.md # Shared architectural vocabulary
```

---

## 1. Memory System (mem/)

### 1.1 Architecture

```
Claude Code
    ↓ MCP Protocol
mem/server.py (FastMCP)
    ↓ Registration
┌─────────────────────────────────┐
│  Tools Layer (20 MCP Tools)     │
│  memory_tools | code_tools      │
│  admin_tools  | web_tools       │
└─────────┬───────────────────────┘
          ↓
┌─────────────────────────────────┐
│  Search Layer                   │
│  FTS5 + Query Expansion + Dedup │
│  Recall (unified) + Hall detect │
└─────────┬───────────────────────┘
          ↓
┌─────────────────────────────────┐
│  Storage Layer                  │
│  SQLite DB + JSONL durability   │
│  Observations + Synthesis       │
│  Entities + Links               │
└─────────────────────────────────┘
```

### 1.2 Data Model

**Observation Records (observations)**: Core storage unit

| Field | Type | Description |
|-------|------|-------------|
| id | INTEGER | Auto-increment primary key |
| session_id | TEXT | Source session |
| project | TEXT | Project identifier |
| type | TEXT | Type: discovery/solution/decision/web |
| title | TEXT | Title (required) |
| narrative | TEXT | Detailed description |
| facts | JSON | Fact list |
| concepts | JSON | Concept tags |
| files_read | JSON | Files/URLs read |
| files_modified | JSON | Files modified |
| salience | REAL | Importance (0-1) |
| ease_factor | REAL | Spaced repetition factor |
| verified | INTEGER | Human verification flag |
| content_hash | TEXT | SHA256 dedup |
| pattern_id | TEXT | MD5 deterministic dedup (16-char hex) |
| lifecycle | TEXT | Lifecycle: staged/accepted/rejected/archived |

**Decision Log (decision_log)**: Observation lifecycle change audit

| Field | Type | Description |
|-------|------|-------------|
| observation_id | INTEGER | Associated observation ID |
| from_state | TEXT | Previous state |
| to_state | TEXT | New state |
| reason | TEXT | Change reason |
| decided_by | TEXT | Decider: auto/human |
| decided_at | TEXT | Decision timestamp |

**Knowledge Synthesis (synthesis)**: Cross-session compiled truths

One record per topic, containing compiled synthesis knowledge and associated observation IDs.

**Entities**: Structured entities extracted from observations

Types: file, function, tool, error, command. Linked to observations via many-to-many entity_mentions.

**Relationship Graph (links)**: Directed relationships between observations

Supports the `related` tool for graph traversal (up to N hops).

### 1.3 Write Flow

```
remember(title, narrative, facts, concepts, ...)
    ↓
1. Density gate check (semantic density evaluation)
   ├── Content too sparse → reject (return 0)
   └── Passed ↓
2. Emotional salience evaluation (salience 0-1)
    ↓
3. Coreference resolution (replace pronouns/abbreviations)
    ↓
4. Two-tier deduplication
   ├── Tier 1: pattern_id exact match (MD5 of normalized content)
   │   └── Match → inline merge
   ├── Tier 2: Jaccard fuzzy match (>0.80 threshold)
   │   └── Match → inline merge
   └── No duplicate ↓
5. Generate summary + compute pattern_id
    ↓
6. Write to SQLite (lifecycle='staged') + JSONL persistence
    ↓
7. Update synthesis (compile per topic)
```

### 1.4 Retrieval Flow

```
search(query) → FTS5 full-text search → RRF ranking → dedup → return index

recall(query) → auto-route:
  ├── FTS search
  ├── Entity matching
  └── Synthesis knowledge → merge & rank

timeline(query) → timeline context (N entries before/after)

related(id, depth) → graph traversal (N-hop relationships)
```

### 1.5 Dream Cycle

Memory maintenance mechanism, supports multiple modes:

| Mode | Function |
|------|----------|
| `dedup` | Remove duplicate observations |
| `merge` | Merge related observations |
| `prune` | Prune stale/low-quality memories |
| `strengthen` | Strengthen compiled knowledge |
| `backfill_pattern_ids` | Backfill MD5 pattern_ids, merge exact duplicates |
| `promote_staged` | Auto-promote high-salience + verified staged observations |

Can be run all at once via `dream_cycle(mode='full')`, or with a specific single mode.

### 1.6 Spaced Repetition

Based on a SuperMemo SM-2 variant:
- `feedback(positive=true)` → ease_factor increases, next review delayed by 50%
- `feedback(positive=false)` → ease_factor decreases, memory deprioritized
- `verify()` → Mark as human-verified fact, boosts retrieval weight

### 1.7 Observation Lifecycle

Observations have structured lifecycle states; all state transitions are recorded to the `decision_log` table:

```
staged → accepted   (manual or auto approval)
staged → rejected   (manual rejection)
accepted → archived (archived)
rejected → accepted (restored)
```

- New observations default to `staged` state
- Dream cycle `promote_staged` auto-promotes observations with salience >= 0.7 that are verified
- `lifecycle_transition(id, new_state, reason, decided_by)` executes the transition and logs an audit trail
- `review_queue(status='staged')` shows observations pending review
- MCP resource `memory://review-queue` renders as Markdown

### 1.8 Deterministic Deduplication (pattern_id)

A two-tier deduplication mechanism based on content MD5:

1. **Tier 1 — Deterministic**: `pattern_id` = first 16 hex chars of MD5(normalized content)
   - Normalization: lowercase → strip → whitespace collapse
   - Exact matching of the same content expressed differently
2. **Tier 2 — Fuzzy**: Jaccard similarity > 0.80
   - Word-level overlap of title + narrative

Dream cycle `backfill_pattern_ids` backfills pattern_ids for legacy data and merges exact duplicates.

### 1.9 Storage Locations

- **Database**: `~/.claude/mem/memory.db` (SQLite)
- **Persistence log**: `~/.claude/mem/*.jsonl` (append-only, crash recovery)
- **Synthesis knowledge**: `~/.claude/mem/synthesis.jsonl`
- **Onboarding marker**: `~/.claude/mem/onboarded`
- **Personal preferences**: `~/.claude/rules/personal.md`

---

## 2. MCP Tool Inventory (26 tools)

### Memory Operations (memory_tools.py — 13 tools)

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `search` | FTS full-text search | query, limit, project |
| `timeline` | Timeline context | query or anchor |
| `get_observations` | Get details by ID | ids, detail |
| `add_observation` | Add observation (legacy interface) | title, narrative, facts |
| `remember` | Store memory (recommended) | title, narrative, concepts |
| `forget` | Delete memory | id |
| `recall` | Unified retrieval | query, limit |
| `related` | Relationship graph traversal | id, depth |
| `search_entities` | Entity search | query, entity_type |
| `search_synthesis` | Synthesis knowledge search | query |
| `feedback` | Feedback weight adjustment | id, positive |
| `verify` | Mark as human-verified | id |
| `smart_outline` | File structure outline | file_path |

### Code Analysis (code_tools.py — 3 tools)

| Tool | Purpose |
|------|---------|
| `smart_outline` | File symbol outline (functions/classes/methods, saves 4-15x tokens) |
| `smart_search` | AST symbol search |
| `smart_unfold` | Expand specific symbol source code |

### System Management (admin_tools.py — 9 tools)

| Tool | Purpose |
|------|---------|
| `dream_cycle` | Memory maintenance (dedup/merge/prune/strengthen/backfill_pattern_ids/promote_staged) |
| `stats` | System statistics (observation count/session count/DB size) |
| `wakeup` | Session start: load critical context (MemPalace pattern) |
| `lifecycle_transition` | Observation lifecycle transition (staged→accepted→archived) |
| `review_queue` | View observations pending review (filter by lifecycle state) |
| `decision_history` | View observation decision history |
| `onboard_status` | Check onboarding status |
| `dashboard` | Terminal dashboard (memory/dream/review/activity panels) |

### Web Memory (web_tools.py — 1 tool)

| Tool | Purpose |
|------|---------|
| `remember_web` | Store web page content as memory, auto-extract domain tags |

### MCP Resources

| Resource URI | Purpose |
|--------------|---------|
| `memory://review-queue` | Render staged observations as Markdown, with accept/reject prompts |

---

## 3. Hooks System (28 hooks)

Hooks execute before and after Claude Code tool calls, with no additional dependencies. The same hooks are also deployed to Codex CLI via `deploy_codex_harness()` in install.sh.

### Core Protection

| Hook | Trigger | Function |
|------|---------|----------|
| `safety-guard.sh` | PreToolUse(Bash) | Three-tier matching: 20 destructive patterns (deny), 14 secret patterns (deny), 9 warning patterns |
| `nto-rewrite.sh` | PreToolUse(Bash) | Command rewriting: `git status → --short --branch`, `git diff → --stat`, compact ls/find output |
| `scope-guard.sh` | PreToolUse(Write/Edit) | Prevent out-of-scope writes (files outside project) |
| `validate-edit.sh` | PostToolUse(Edit) | Validate file syntax after edits |
| `protect-files.sh` | PreToolUse(Write/Edit) | Protect critical files from being overwritten |
| `post-bash-scan-secrets.sh` | PostToolUse(Bash) | Scan command output for leaked secrets |

### Automation

| Hook | Trigger | Function |
|------|---------|----------|
| `auto-format.sh` | PostToolUse(Write/Edit) | Code formatting |
| `auto-verify.sh` | PostToolUse(Write/Edit) | Auto-run verification |
| `checkpoint.sh` | Event-triggered | Session state checkpoint |
| `update-code-map.sh` | PostToolUse(Write/Edit) | Update code map |
| `pr-gate.sh` | Event-triggered | PR quality gate |

### Memory Integration

| Hook | Trigger | Function |
|------|---------|----------|
| `mem-record.sh` | During session | Memory record trigger |
| `mem-session.sh` | Session start/end | Session-level memory management |
| `mem-precompact.sh` | Before context compaction | Save critical context before compaction |
| `review-queue-inject.sh` | PreCompact | Inject staged observation count reminder |
| `sync-memory-rules.sh` | Event-triggered | Memory rules sync |

### Other

| Hook | Trigger | Function |
|------|---------|----------|
| `env-bootstrap.sh` | Session start | Generate environment snapshot (OS/languages/tools/disk) |
| `audit-log.sh` | Tool call | Operation audit log |
| `perceive.sh` | Event-triggered | Environment perception |
| `session-stop-guard.sh` | Session end | Safe termination |
| `session-checkpoint.sh` | Session end | Session state checkpoint |
| `stop-event.sh` | Stop event | Stop event handling |
| `todo-check.sh` | Event-triggered | TODO compliance check |
| `no-todo-commit.sh` | Pre-commit | Prevent TODO commits |
| `pre-compact-instructions.sh` | Pre-compaction | Compaction retention instructions |
| `constitutional-check.sh` | PostToolUse(Read) | Constitutional compliance check |
| `codedb-reindex.sh` | PostToolUse(Write/Edit) | Trigger CodeDB reindex |
| `tool-cache.sh` | Pre/Post tool use | Cache tool results for duplicate calls |

### NTO Command Rewrite Examples

```
git status              → git status --short --branch
git diff                → git diff --stat
git log                 → git log --oneline
git add/stash/restore   → silent success output (echo ok)
ls -la                  → ls -1A | head -50
find .                  → add exclusion dirs + head limit
```

---

## 4. Skills System (13 skills)

Skills are reusable workflow templates, triggered via `/skill-name`.

### sprint — Sprint Workflow Orchestration

```
Trigger: /sprint, "build a feature", "implement"
Flow: Research → Plan → Implement → Verify
Features:
  - Sub-agent parallel execution
  - Inter-stage context compaction
  - Validation ladder (syntax→tests→functional)
```

Includes reference documentation:
- `state-machine.md` — State machine definition
- `subagent-strategy.md` — Sub-agent strategy
- `validation-ladder.md` — Validation ladder
- `context-engineering.md` — Context engineering
- `anti-rationalizations.md` — Anti-rationalization checks

### review — Cross-Validation Code Review

```
Trigger: /review, "code review", "audit"
Flow: Launch multiple sub-agents in parallel → review from different perspectives → synthesize findings
Features:
  - Multi-perspective review (security/correctness/performance/maintainability)
  - Blast radius analysis
  - Checklist-based verification
  - Routes to sprint on completion
```

### deslop — Code De-bloat

```
Trigger: /deslop
Function: Identify and eliminate redundancy, over-engineering, and unnecessary complexity in code
```

### harness — Harness Component Management

```
Trigger: When modifying hooks/rules/skills/settings.json
Function: Manage keep's own component configuration and updates
```

### skill-forge — Skill Auto-Creation

```
Trigger: /skill, after complex task completion, after iterative error resolution
Function: Automatically extract reusable skill templates from experience
```

### onboard — First-Run Personalization Wizard

```
Trigger: /onboard
Function: Interactively collect preferences (name/language/project patterns/verbosity)
Output: ~/.claude/rules/personal.md + ~/.claude/mem/onboarded marker file
```

### statusline — Token/Cost Status Bar

```
Trigger: /statusline:setup
Function: Display token usage, cost, and context utilization in the Claude Code status bar
```

### analyze — Large File Analysis

```
Trigger: /analyze, "analyze artifact"
Function: RLM-style chunk+parallel+merge for large files and codebases
```

### tdd — Test-Driven Development

```
Trigger: /tdd
Function: Structured TDD workflow (red→green→refactor)
```

### design-interface — Interface Design

```
Trigger: /design-interface
Function: Deep module interface design with seam analysis
```

### ambient — Ambient Awareness

```
Trigger: /ambient
Function: Background context awareness and environment monitoring
```

### ubiquitous-language — Shared Vocabulary

```
Trigger: /ubiquitous-language
Function: Manage a project-wide shared vocabulary for consistent terminology
```

### browser-use — Headless Browser Automation

```
Trigger: /browser-use
Function: Headless browser automation with domain knowledge and interaction patterns
Includes: domain-knowledge/, interaction-patterns/ (dialogs, dropdowns, iframes, shadow DOM, etc.)
```

---

## 5. Utility Scripts (scripts/)

### install.sh — One-Click Deployment

```bash
# Full installation
bash scripts/install.sh

# mx-only installation (model switcher)
bash scripts/install.sh --mx

# Adapter-only configuration
bash scripts/install.sh --adapter codex
bash scripts/install.sh --adapter cursor
bash scripts/install.sh --list-adapters  # see all supported

# Installation contents:
# 1. Python virtual environment + mcp dependency
# 2. MCP server config to ~/.claude/settings.json
# 3. Hooks deployed to ~/.claude/hooks/
# 4. Rules deployed to ~/.claude/rules/
# 5. Skills deployed to ~/.claude/skills/
# 6. NTO command optimizer
# 7. mx model switcher → ~/.local/bin/mx.sh
# 8. codedb code intelligence server
# 9. Codex CLI + harness (AGENTS.md, hooks, config.toml, hooks.json)
# 10. uv + browser-use (headless automation)
# 11. Terminal dashboard → ~/.claude/scripts/show.py
# 12. Auto adapter detection (Cursor/Windsurf/OpenCode/Codex/OpenClaw)
# 13. Smoke test verification
# 14. First-run prompt for /onboard
```

### show.py — Terminal Dashboard

```bash
# Terminal visualization
python3 scripts/show.py

# JSON output (programmatic use)
python3 scripts/show.py --json

# No-color mode
python3 scripts/show.py --no-color
```

Panels: MEMORY (observation count/synthesis/entities/lifecycle), DREAM (run count/last run), REVIEW (staged/rejected counts), ACTIVITY (14-day observations/day sparkline).

### mx.sh — Unified Model Switcher (v4.0.0)

Unified model switching for both **Claude Code** and **Codex CLI** across 15+ models/endpoints:

**Claude Code models** (via `mx <model>` or `mx claude <model>`):

| Command | Model | Endpoint |
|---------|-------|----------|
| `mx sonnet` / `mx s` | Claude Sonnet 4.5 | Anthropic official |
| `mx opus` / `mx o` | Claude Opus 4.5 | Anthropic official |
| `mx haiku` / `mx h` | Claude Haiku 4.5 | Anthropic official |
| `mx deepseek` / `mx ds` | Deepseek Chat | api.deepseek.com |
| `mx kimi` / `mx kimi2` | KIMI for Coding | api.kimi.com |
| `mx kimi-cn` | KIMI K2 Thinking | api.moonshot.cn |
| `mx qwen` | Qwen3 Max | dashscope.aliyuncs.com |
| `mx glm` | GLM 5.1 | open.bigmodel.cn |
| `mx seed` / `mx doubao` | Doubao Seed Code | ark.cn-beijing.volces.com |
| `mx longcat` / `mx lc` | LongCat Flash | api.longcat.chat |
| `mx minimax` / `mx mm` | MiniMax M2 | api.minimax.io |
| `mx litellm` | LiteLLM proxy | Custom BASE_URL |

**Codex CLI models** (via `mx codex <model>`):

| Command | Model | Endpoint |
|---------|-------|----------|
| `mx codex deepseek` | deepseek-chat | api.deepseek.com/v1 |
| `mx codex glm` | glm-5.1 | open.bigmodel.cn/api/paas/v4 |
| `mx codex kimi` | kimi-k2-thinking | api.moonshot.cn/v1 |
| `mx codex qwen` | qwen3-max | dashscope.aliyuncs.com |
| `mx codex longcat` | LongCat-Flash-Thinking | api.longcat.chat/v1 |
| `mx codex minimax` | MiniMax-M2 | api.minimax.io/v1 |
| `mx codex seed` | doubao-seed-code | ark.cn-beijing.volces.com |

Claude Code routing emits shell `export` statements (`eval "$(mx glm)"`); Codex CLI routing writes directly to `~/.codex/config.toml` with the appropriate `[model_providers]` section.

Other commands:
- `mx status` — View current Claude Code + Codex CLI configuration
- `mx config` — Edit config file (~/.mx_config)
- `mx set <provider> <key>` — Set API key
- `mx set env <KEY> <VALUE>` — Set arbitrary environment variable
- `mx save-account <name>` — Save Claude Pro account
- `mx switch-account <name>` — Switch account

### benchmark.py — Performance Benchmarking

```bash
# Full test (11 test cases)
python3 scripts/benchmark.py

# Quick test (4 core cases)
python3 scripts/benchmark.py --quick

# Multi-run stability test
python3 scripts/benchmark.py --runs 10 --keep

# Analyze results
python3 scripts/benchmark.py --analyze <dir>
python3 scripts/benchmark.py --compare <dir1> <dir2>
```

Test dimensions:

| Dimension | Test Items |
|-----------|------------|
| Comprehension | codebase-map, code-structure, cross-file-trace |
| Debugging | error-diagnosis, bug-review, code-review |
| Design | feature-plan |
| Safety | risk-assess, security-audit |
| Workflow | implementation-plan, sprint-plan |

Scored using Gold Answers (0-10 scale); reports include quality, token efficiency, stability (sigma), and pass@k metrics.

### backup.sh — Config Backup

```bash
bash scripts/backup.sh
# Backs up: ~/.claude/ + ~/.codedb/
# Output: /data/backup/workspace/claude-config-backup.tar.gz
# Excludes: .git, worktrees, *.db-shm, *.db-wal, logs
```

---

## 6. Benchmark 10-Round Baseline Data

Median results from 10 full test rounds using the Opus 4.6 model:

| Metric | Vanilla | Harness | Delta |
|--------|---------|---------|-------|
| Quality median | 9.0/10 | **10.0/10** | +1.0 |
| pass@10 | 101/110 | **104/110** | +3 |
| Token usage | 241K | **194K** | -19.6% |
| Cost-efficiency | 44.3 pts/$ | **59.5 pts/$** | +34% |
| Max variance | sigma=3.1 | sigma=1.8 | Harness more stable |

---

## 7. Installation and Usage

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
source ~/.bashrc
```

### Daily Usage

```bash
# Switch model (Claude Code)
mx glm                     # shorthand → eval "$(mx.sh glm)" via shell function
mx claude glm              # explicit Claude Code target

# Switch model (Codex CLI)
mx codex glm               # writes ~/.codex/config.toml directly

# Use memory tools in Claude Code
> Remember this finding: ...
> Search memory about X
> Save the content of this web page

# Run workflows
> /sprint implement user authentication
> /review src/auth.py
```

### Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| MCP config | `~/.claude/settings.json` | MCP server connection |
| Memory database | `~/.claude/mem/memory.db` | SQLite storage |
| mx config | `~/.mx_config` | Model/API keys |
| mx accounts | `~/.mx_accounts` | Claude Pro accounts |
| Environment vars | `~/.claude/env` | Shell environment config |
| Personal preferences | `~/.claude/rules/personal.md` | User preferences generated by /onboard |
| Onboarding marker | `~/.claude/mem/onboarded` | First-run marker file |
| Codex CLI config | `~/.codex/config.toml` | Codex model + MCP servers (TOML) |
| Codex instructions | `~/.codex/AGENTS.md` | Codex behavioral instructions |
| Codex hooks | `~/.codex/hooks.json` | Codex hook configuration |
| Cursor MCP | `~/.cursor/mcp.json` | Cursor adapter config |
| Windsurf MCP | `~/.windsurf/mcp.json` | Windsurf adapter config |

---

## 8. Design Philosophy

1. **Zero External Dependencies**: Core functionality depends only on the `mcp` Python package; SQLite is built-in
2. **Progressive Enhancement**: Base installation works out of the box; hooks/skills enabled as needed
3. **Cognitive Science Driven**: Spaced repetition, density gates, coreference resolution, memory palace, lifecycle management
4. **Safety First**: Three-tier safety guard, secret scanning, scope protection
5. **Token Efficiency**: NTO rewriter saves 60-90% tokens, smart_outline saves 4-15x
6. **Self-Improving Loop**: Dream cycle maintains memory, skills auto-create and improve
7. **Multi-Tool Compatibility**: Same mem server supports Claude Code, Codex CLI, Cursor, Windsurf, OpenCode
8. **Audit Traceability**: All lifecycle changes recorded to decision_log, supporting human/auto decision tracking
