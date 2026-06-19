---
name: keep:teach
version: "1.0"
triggers: ["/keep:teach", "/keep:teach me", "/keep:learn", "/keep:lesson", "/keep:study", "/keep:tutorial"]
routes_to: ["grilling"]
description: >
  Teach the user a skill or concept over multiple sessions, using the current
  directory as a stateful teaching workspace. TRIGGER when: user says "/keep:teach",
  "teach me <topic>", "I want to learn <X>", "walk me through <concept>", or asks
  for a multi-session tutorial. Uses memory MCP for cross-session progress (learner
  profile, current lesson, gaps, spaced-repetition schedule). Differs from one-shot
  explanations: this is a curriculum, not an answer. Do NOT trigger for: quick
  factual questions (answer directly), or implementation tasks (use /keep:sprint).
resources: ['mind']
---

# Teach

Teach the user a skill or concept across multiple sessions. The current directory is the workspace — exercises, notes, and artifacts land here. Memory MCP holds the cross-session state: where the learner is, what they've mastered, what's due for review.

This skill turns keep's persistent memory infrastructure into a teaching loop. It is **not** a one-shot explanation engine — those are just conversations. `teach` is for things that take practice: a new language, a framework, a debugging discipline, a design pattern, an algorithm class.

## When to Teach vs Answer

| Request | Tool |
|---------|------|
| "What does `git rebase` do?" | Answer directly — one concept, one exchange |
| "Teach me Git over the next week" | `teach` — multi-session curriculum |
| "How do I write a unit test?" | Answer directly |
| "Teach me TDD" | `teach` — needs practice across N sessions |
| "Review my PR" | `/keep:review` |
| "Teach me how to review PRs" | `teach` — multi-session with real PRs as material |

If unsure, ask one question: _"Quick answer, or multi-session curriculum?"_

## Three-Part State (in memory)

Every learner has a profile in memory. Tagged `type=learning-profile`.

```
{
  learner: <handle>,
  topic: "<what we're learning>",
  level: novice | intermediate | advanced,
  learning_style: "examples-first" | "theory-first" | "hands-on" | "visual",
  current_lesson: <lesson id>,
  completed_lessons: [<lesson id>, ...],
  gaps: [<skill id>, ...],
  strengths: [<skill id>, ...],
  review_schedule: {
    <concept>: <next-review-date>,
    ...
  }
}
```

The memory entry is the single source of truth — the directory is the workspace, but the profile is the progress.

## Workflow

### Phase 1 — Profile (first session only)

If no profile exists in memory for this learner+topic:

- [ ] `mcp__mind__search "learning-profile <topic> <user>"` — confirm absence
- [ ] Ask **one** question: what's the goal? (e.g. "I want to ship a SaaS in this language", "I want to pass interview X", "I'm curious")
- [ ] Ask **one** question: starting level? (novice / intermediate / advanced — give criteria for each)
- [ ] Ask **one** question: learning style preference? (examples-first / theory-first / hands-on / visual — show what each means in practice)
- [ ] Create the workspace structure:

```
.teach/
├── PROFILE.md           # mirrors the memory entry, human-readable
├── NOTES/               # my session notes (concepts explained, analogies used)
├── EXERCISES/           # practice problems with solutions
└── REVIEW.md            # spaced-repetition queue
```

- [ ] `mcp__mind__remember` the profile (type=`learning-profile`, project=current)

**Done when:**

- [ ] Profile in memory + `.teach/PROFILE.md`
- [ ] Workspace directories created
- [ ] Goal / level / style recorded

### Phase 2 — Curriculum design (first session only)

Draft the lesson sequence:

```
Lesson 1: <foundational concept>
  Objective: <observable skill at end>
  Exercises: <N>
  Estimate: <minutes>
Lesson 2: <builds on 1>
  ...
Lesson N: <capstone — integrates all>
```

Rules:

- **Each lesson has one objective**: an observable skill ("can write a failing test for any pure function", not "understands testing").
- **Foundational first**: never introduce a concept that depends on an un-taught prerequisite.
- **Capstone integrates**: the last lesson should require combining 3+ prior concepts.
- **No more than 7±2 lessons**. If you need more, it's two curricula.

Write to `.teach/CURRICULUM.md`. Get user approval before Lesson 1.

**Done when:**

- [ ] Curriculum written
- [ ] User approves (or revises)
- [ ] Each lesson has a single objective

### Phase 3 — Resume (subsequent sessions)

At session start:

- [ ] `mcp__mind__search "learning-profile <topic> <user>"` — load profile
- [ ] Read `.teach/PROFILE.md` for human-readable state
- [ ] Check `review_schedule`: what concepts are due today? (spaced repetition)
- [ ] Identify `current_lesson` — is the learner ready to advance, or re-practice?

**Resume message** (echo to user):

```
Welcome back. You're on Lesson 3: <topic>.
Last session you mastered: <X>, struggled with: <Y>.
Today's review (spaced repetition): <concept A>, <concept B>.
Ready to start? Or want to revisit <Y> first?
```

### Phase 4 — Teach a lesson

For each lesson:

1. **Diagnose** — 1-2 quick questions to confirm prerequisites. If gaps, fill them before proceeding.
2. **Introduce** — one concept, framed by the learner's style:
   - examples-first: show 2-3 concrete instances before the abstraction
   - theory-first: state the rule, then derive examples
   - hands-on: pose a small problem, let them attempt, then teach from the attempt
   - visual: ASCII diagram / structure before prose
3. **Practice** — exercises scaled to current mastery. Start one notch below their ceiling; ramp.
4. **Feedback** — grade their attempt. Name what they did right, what they missed, why.
5. **Consolidate** — one-sentence summary of the lesson's core. Write to `.teach/NOTES/<lesson>.md`.
6. **Schedule review** — add the new concept to `review_schedule` with spaced repetition (SM-2-style intervals; see _Wozniak, SuperMemo SM-2 (1987)_ / Anki documentation):
   - First review: +1 day
   - If recalled: +3 days, then +7, +21, +60
   - If forgotten: reset to +1 day, note as a `gap`
   - **Procedural skills caveat**: SM-2 was validated on declarative memory (facts). For procedural skills (TDD, a language, a debug discipline), the early intervals should be **shorter and denser** — after the first +1d review, double the practice reps at the next interval rather than relying on the geometric growth. Skill consolidation needs repetition, not just time.

**Done when:**

- [ ] Learner can perform the lesson's objective without help
- [ ] Notes captured
- [ ] Review scheduled

### Phase 5 — Spaced repetition (start of each session)

For each concept due:

- [ ] Quick prompt: "Explain <concept> in your own words" or "Solve this one-liner exercise"
- [ ] If correct → advance the interval, mark as `strength`
- [ ] If incorrect → reset interval, add to `gaps`, schedule a refresher mini-lesson

Spaced repetition is the **second** most important part of this skill (after accurate diagnosis). Without it, learning decays.

### Phase 6 — Close session

- [ ] Update memory profile (`mcp__mind__remember` with new state)
- [ ] Update `.teach/PROFILE.md`
- [ ] Echo next steps: next lesson, due reviews, suggested practice

## Adaptation Rules

### If the learner is stuck

- **Don't advance.** Re-attempt the current lesson with:
  - A different framing (theory-first → examples-first)
  - A smaller sub-skill (decompose the objective)
  - An analogy to a known strength
- Record the struggle in `gaps` so future sessions don't paper over it.

### If the learner is bored

- **Skip ahead, but verify.** Jump to the next lesson, then pose a transfer task (novel problem requiring the skipped concepts). If they can solve it, skip permanently. If not, go back.
- Record as `strength` so you don't re-teach.

### If the learner asks a tangent question

- Answer briefly inline (don't derail the curriculum)
- Note it for a future lesson
- Resume the planned lesson

## Anti-Patterns

- ❌ **Skipping the profile.** Teaching without knowing the level wastes a session.
- ❌ **Long lectures.** One concept at a time, then practice. Attention spans aren't infinite.
- ❌ **Skipping spaced repetition.** Without review, learning decays. The schedule is load-bearing.
- ❌ **Advancing on time, not mastery.** "It's been a week, must be Lesson 5" — no. Advance when the objective is met.
- ❌ **Answering factual questions with a curriculum.** "What's a monad?" is one exchange, not a course.
- ❌ **No capstone.** The last lesson must integrate. A curriculum without integration is a list of facts.
- ❌ **Teaching in the repo.** Use `.teach/` workspace. Don't pollute the project with lesson artifacts.

## Resource Check

| Resource | How to check | Degraded mode |
|----------|-------------|---------------|
| `mind` | `mcp__mind__search` available | Required. Without memory, this skill cannot do cross-session teaching — fall back to one-shot explanation. |

## Composability

- **Input ← grilling**: a deep grilling session can surface "I want to learn this" — hand off to `teach`.
- **Output → tdd**: when teaching testing patterns, the exercises can become real test files (paired with `/keep:tdd` discipline).
- **Output → skill-forge**: if the learner develops a reusable practice, capture it via `/keep:skill-forge`.
- **Output → ubiquitous-language**: teaching a domain necessarily builds the glossary — keep them in sync.
- **Differs from grilling**: grilling interviews the user about a plan; teach interviews them about their understanding. Different goals, similar protocol.
