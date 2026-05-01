---
name: keep:ambient
version: "1.0"
triggers: ["/keep:ambient", "/keep:garden", "/keep:scout"]
description: >
  Ambient mode for memory maintenance and project health. Three sub-modes:
  Garden (memory consolidation), Scout (project health check), Work (process staged observations).
  Use when user says /keep:ambient, /keep:garden, /keep:scout, or wants to "maintain memory",
  "check project health", "tend the garden", "scout issues", or "process queue".
resources: ['mind', 'git', 'cron']
---

# Ambient Mode — Garden / Scout / Work

Three sub-modes for background maintenance. Pick based on trigger keyword or ask user which mode.

## Garden Mode (`/keep:garden`)

Tend the memory garden — consolidate, deduplicate, and strengthen observations.

### Steps

1. Run `dream_cycle(mode='full')` to execute full maintenance:
   - **Dedup**: merge duplicate observations
   - **Merge**: consolidate related observations into synthesis
   - **Prune**: remove low-salience overwritable observations
   - **Strengthen**: boost high-confidence truths

2. Review staged observations:
   ```
   review_queue(status='staged', limit=20)
   ```
   For each staged observation, decide: accept, reject, or leave for later.

3. Consolidate synthesis:
   - Check `search_synthesis()` for topics with low confidence
   - If new observations relate to weak synthesis, suggest re-processing

4. Report: observations processed, merged, pruned; synthesis topics strengthened.

## Scout Mode (`/keep:scout`)

Quick project health reconnaissance.

### Steps

1. Git status:
   ```bash
   git status --short
   git log --oneline -5
   ```

2. Stale memory count — observations not accessed in 30+ days:
   ```
   search(query="*", obs_type="discovery") → count old observations
   ```

3. Codebase marker scan (finds pending work items):
   ```bash
   grep -rPn "work-in-progress|blocked-by|incomplete" --include="*.py" --include="*.sh" --include="*.ts" | head -20
   ```
   Adapt patterns to match your project's convention (common markers: pending, blocked, revisit).

4. Review queue depth:
   ```
   review_queue(status='staged') → count
   ```

5. Report summary:
   - Branch status, uncommitted changes
   - Stale memory count, review queue depth
   - Top 5 pending work markers by recency
   - Recommended actions

## Work Mode (`/keep:ambient` default or explicit)

Process the highest-salience staged observation.

### Steps

1. Find highest-salience staged observation:
   ```
   review_queue(status='staged', limit=1)
   ```

2. Present the observation to user with context:
   - Title, narrative, concepts, related observations
   - Suggested action: accept, reject, or enhance

3. If user approves, execute with safety checks:
   - Verify the observation is actionable
   - Check for conflicts with existing knowledge (`related(id, depth=2)`)
   - Apply: `lifecycle_transition(id, 'accepted')`

4. If the observation represents a task, offer to execute it.

## CronCreate Scheduling Templates

Set up recurring ambient tasks. Note: recurring jobs auto-expire after 3 days.

```bash
# Garden: daily memory maintenance
/keep:garden → CronCreate: "3 9 * * *" (every morning ~9am)

# Scout: hourly health check
/keep:scout → CronCreate: "7 * * * *" (every hour)

# Work: process queue every 30 minutes
/keep:ambient → CronCreate: "*/30 * * * *" (every 30 min)
```

**Note**: All cron jobs expire after 3 days. Re-schedule at session start if needed.
