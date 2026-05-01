# keep

A cognitive enhancement layer for AI coding assistants. Persistent memory, safety guards, skill workflows, and token optimization — via MCP.

Works with [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex), Cursor, Windsurf, OpenCode, and other MCP-compatible tools.

## What It Does

| Feature | Description |
|---------|-------------|
| **Persistent Memory** | Cross-session knowledge storage with FTS5 search, spaced repetition, and dream-cycle maintenance |
| **Safety Guards** | 100+ destructive command patterns blocked (filesystem, SQL, AWS, GCP, Azure, Aliyun, Terraform, K8s) |
| **Token Optimization** | NTO command rewriter saves 60-90% tokens on common CLI operations |
| **Skill Workflows** | `/keep:sprint`, `/keep:review`, `/keep:analyze`, and more — structured multi-agent workflows |
| **Multi-Tool Support** | Same memory server works across Claude Code, Codex CLI, Cursor, Windsurf, and OpenCode |
| **Model Manager** | `mx` switches between 15+ LLM providers for both Claude Code and Codex CLI |

## Quick Start

```bash
# Clone and install
git clone https://github.com/your-org/keep.git
cd keep
bash scripts/install.sh

# Configure API key
mx set glm <your-api-key>      # or: export ANTHROPIC_API_KEY=xxx

# Start using
claude
> /keep:onboard                        # first-run personalization
> /keep:sprint build a REST API        # structured development workflow
```

### Requirements

- **OS**: Ubuntu/Debian, Arch Linux, Fedora, or macOS (including WSL2)
- **Runtime**: Python 3.10+, Node.js 18+
- **Tools**: git, curl, jq

The installer handles all dependencies automatically.

## Architecture

```
keep/
├── mem/                    # Memory MCP Server (Python, SQLite)
│   ├── server.py           # FastMCP entry point
│   ├── tools/              # 26 MCP tools
│   ├── storage/            # SQLite persistence (observations, synthesis, entities, links)
│   ├── search/             # FTS5 + recall engine
│   └── dream/              # Memory maintenance cycle (dedup, merge, prune, strengthen)
├── hooks/                  # 28 Claude Code hooks (bash)
├── skills/                 # 13 skill workflows
├── scripts/                # Installer, model switcher, benchmarks
└── rules/                  # Behavioral rules
```

### Memory System

The memory MCP server provides 26 tools for persistent knowledge management:

- **Store**: `remember`, `remember_web`, `add_observation`
- **Retrieve**: `search`, `recall`, `timeline`, `get_observations`, `related`
- **Maintain**: `dream_cycle` (dedup/merge/prune/strengthen), `feedback`, `verify`
- **Analyze**: `smart_outline`, `smart_search`, `smart_unfold`
- **Admin**: `stats`, `dashboard`, `wakeup`, `lifecycle_transition`

Storage: `~/.claude/mem/memory.db` (SQLite) with JSONL durability for crash recovery.

### Safety System

Three-tier hook protection:

| Tier | Action | Examples |
|------|--------|---------|
| **Block** | Destructive patterns denied | `rm -rf /`, `aws ec2 terminate-instances`, `gcloud projects delete`, `terraform destroy`, `kubectl delete namespace` |
| **Block** | Secret leak prevention | `cat ~/.aws/credentials`, `gcloud auth print-access-token`, env dumps |
| **Warn** | Potentially risky ops | `terraform apply`, `aws s3 cp`, `kubectl apply` |

Supports: filesystem, git, SQL, AWS (26 patterns), GCP (26), Azure (16), Aliyun (24), Terraform, Docker, Kubernetes, Helm.

### Skills

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `/keep:sprint` | "build a feature", "implement" | Full Research → Plan → Implement → Review → Test → Ship cycle |
| `/keep:review` | "code review", "audit" | Multi-agent cross-validation (bug hunter + security + adversarial + evaluator) |
| `/keep:analyze` | "analyze artifact" | RLM-style chunk+parallel+merge for large files |
| `/keep:deslop` | "/keep:deslop" | Remove code redundancy and over-engineering |
| `/keep:onboard` | "/keep:onboard" | First-run personalization wizard |
| `/keep:statusline` | "/keep:statusline:setup" | Token/cost/context status bar |
| `/keep:tdd` | "/keep:tdd" | Test-driven development workflow (red → green → refactor) |
| `/keep:design-interface` | "/keep:design-interface" | Deep module interface design with seam analysis |
| `/keep:browser-use` | "/keep:browser-use" | Headless browser automation with domain knowledge |
| `/keep:ambient` | "/keep:ambient" | Background context awareness and monitoring |
| `/keep:ubiquitous-language` | "/keep:ubiquitous-language" | Shared vocabulary management |
| `/keep:skill-creator` | "/keep:skill" | Auto-extract reusable skill templates from experience |
| `/keep:harness` | Component changes | Manage keep's own configuration |

### Model Manager (mx)

`mx` (Model eXchange) is a unified model switcher for both Claude Code and Codex CLI, supporting 15+ providers:

**Claude Code** (emits shell exports):

```bash
mx glm          # GLM 5.1
mx sonnet       # Claude Sonnet 4.5
mx opus         # Claude Opus 4.5
mx deepseek     # Deepseek Chat
mx qwen         # Qwen3 Max
mx kimi         # KIMI for Coding
mx status       # Show current config
# ... and more
```

**Codex CLI** (writes config.toml directly):

```bash
mx codex glm       # GLM 5.1 via OpenAI-compatible endpoint
mx codex deepseek  # Deepseek Chat
mx codex qwen      # Qwen3 Max
mx codex kimi      # KIMI K2 Thinking
# ... and more
```

Config file: `~/.mx_config`

## Benchmark

Full 11-test benchmark comparing harness vs vanilla Claude Code (Opus 4.6):

| Metric | Vanilla | Harness |
|--------|---------|---------|
| Quality | 78/110 | 79/110 |
| Safety (`safety-block`) | 3/10 | **6/10** |
| Token optimization (`nto-rewrite`) | 6/10 | **7/10** |

Run your own:

```bash
bash scripts/benchmark.sh          # full (11 tests)
bash scripts/benchmark.sh --quick  # quick (4 tests)
```

## Multi-Tool Adapters

keep works with any MCP-compatible tool:

```bash
# Auto-detect and configure during install
bash scripts/install.sh

# Or configure a specific adapter
bash scripts/install.sh --adapter cursor
bash scripts/install.sh --adapter windsurf
bash scripts/install.sh --adapter opencode
bash scripts/install.sh --adapter codex
bash scripts/install.sh --list-adapters  # see all supported
```

The installer also deploys a full Codex CLI harness automatically: AGENTS.md (instructions), hooks (safety guard, NTO, etc.), config.toml (MCP servers), and hooks.json (hook wiring).

## Configuration

| File | Location | Purpose |
|------|----------|---------|
| Settings | `~/.claude/settings.json` | Hooks, permissions, MCP servers |
| Memory DB | `~/.claude/mem/memory.db` | SQLite knowledge store |
| mx config | `~/.mx_config` | Model/API key |
| mx accounts | `~/.mx_accounts` | Claude Pro account store |
| Personal rules | `~/.claude/rules/personal.md` | User preferences (via `/onboard`) |
| Codex config | `~/.codex/config.toml` | Codex CLI model + MCP servers |
| Codex instructions | `~/.codex/AGENTS.md` | Codex behavioral instructions |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Bug reports and pull requests welcome.

## License

[MIT](LICENSE)
