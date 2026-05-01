# Changelog

All notable changes to keep are documented here.

## [Unreleased] - 2025-04-29

### Added

- **RLM Infrastructure Primitives** (yoyo-evolve Phase 1)
  - KV store for sub-agent shared state (`scripts/kv-store.sh`)
  - JSON contract for structured sub-agent returns
  - Recursion depth tracker with configurable cap (`scripts/recursion-guard.sh`)
  - Token-aware chunking utility (`scripts/token-chunk.sh`)
- **Hook Enhancements**
  - Constitutional file verification via SHA256 hashes (`hooks/constitutional-check.sh`)
  - MCP tool result caching (`hooks/tool-cache.sh`)
  - Boundary nonce for external input safety (`scripts/nonce-wrap.sh`)
  - Cloud safety patterns: AWS (26), GCP (26), Azure (16), Aliyun (24), Terraform, K8s/Helm
  - Cloud credential leak prevention (AWS, GCP, Azure, Aliyun)
- **Skill & Workflow Enhancements**
  - 4-stage quality gate in sprint (Format → Build → Test → Lint)
  - Independent evaluator agent in `/review` (Step 3.7)
  - Checkpoint-restart for sprints (`scripts/sprint-checkpoint.sh`)
  - Three-layer state classification for memory (immutable / append-only / overwritable)
- **Integration**
  - `/analyze` skill — RLM-style chunk+parallel+merge pipeline for large artifacts
- **Documentation**
  - English README.md
  - ARCHITECTURE.md (English)
  - CONTRIBUTING.md, SECURITY.md, CHANGELOG.md
  - MIT LICENSE

### Changed

- `rules/core.md` — Added JSON contract, recursion cap, nonce wrapping, state classification rules
- `hooks/safety-guard.sh` — Added 100+ cloud destructive patterns and cloud credential leak patterns
- `skills/sprint/SKILL.md` — Added quality gate, checkpoint-resume, KV store lifecycle, JSON contracts
- `skills/review/SKILL.md` — Added JSON contract in subagent prompts, independent evaluator agent
- `scripts/install.sh` — Added deployment of new hooks and utility scripts
