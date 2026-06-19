---
name: keep:ubiquitous-language
version: "1.1"
triggers: ["/keep:ubiquitous language", "/keep:glossary", "/keep:terminology", "/keep:domain terms", "/keep:domain model", "/keep:DDD", "/keep:define terms", "/keep:ubiquitous", "/keep:harden terms"]
routes_to: ["grilling"]
description: >
  Build and sharpen a DDD-style ubiquitous language glossary for the project.
  TRIGGER when: user wants to define domain terms, build a glossary, harden
  terminology, create a ubiquitous language, mentions "domain model", "DDD", or
  when any skill detects a fuzzy/ambiguous/conflicting term mid-conversation
  (inline mode). Two modes: batch (one-shot extraction) and inline (active
  discipline — update the glossary the moment a term sharpens, not later).
  Do NOT trigger for: general coding tasks, file edits unrelated to terminology,
  or module/class names that have no domain meaning.
resources: ['mind']
---

# Ubiquitous Language

Build and sharpen the project's domain glossary. **A shared, canonical vocabulary is the highest-leverage token optimization available**: every consistent term saves 20 words of explanation downstream, every name aligned with the glossary makes the codebase navigable, every sharpened concept saves the agent thinking budget.

Uses vocabulary from `rules/architecture-language.md` for the *meta*-terms (module, interface, seam, adapter); this skill is for the *domain* terms (Order, Customer, Fulfillment, etc.).

## Two Modes

Pick by context:

| Mode | When | What it does |
|------|------|--------------|
| **inline** (default for long sessions) | Any conversation about the domain; another skill hits a fuzzy term | Update the glossary **the moment** a term sharpens — no batching |
| **batch** (default for first extraction) | User invokes `/keep:ubiquitous-language` directly with no existing glossary, or asks for "extract the glossary" | One-shot scan → propose canonical glossary → write to file |

**Inline is the discipline.** Batch is the bootstrap. Once a glossary exists, every subsequent terminology decision should land inline — delay loses the context that made the decision make sense.

## File Layout

| Layout | When | Files |
|--------|------|-------|
| **single** | One cohesive domain | `UBIQUITOUS_LANGUAGE.md` in working dir |
| **multi** | Several subdomains (e.g. monorepo, multi-service) | `UBIQUITOUS_LANGUAGE.md` at root acts as index + `docs/glossary/<subdomain>.md` per cluster |

The **single** layout is the default. Promote to **multi** only when a single table grows past ~40 terms or when two subdomains have minimally overlapping vocabularies. Don't pre-split.

## Inline Mode — Active Discipline

Run this loop continuously while any other skill is active in a domain conversation:

### 1. Detect sharpening events

A term sharpens when any of these happens:

- The user corrects your usage ("actually, 'Fulfillment' means the post-shipment state, not the act of shipping")
- Two terms collide ("is a 'Subscriber' the same as a 'Customer' here?")
- A vague term gets pinned down ("by 'active user' we mean: logged in within 30 days AND has a paid plan")
- Code contradicts the current glossary (`grep` finds three spellings of the same concept)
- You coin a term mid-explanation and it sticks

### 2. Update immediately (no batching)

- [ ] Read the current `UBIQUITOUS_LANGUAGE.md`
- [ ] Add or revise the term **in this turn**, not at session end
- [ ] If revising: note the supersession in "Revision history" (`Order` previously meant X, now means Y — superseded YYYY-MM-DD because Z)
- [ ] Re-flag any new ambiguities the change creates downstream
- [ ] Confirm the change in one line: `_Updated UBIQUITOUS_LANGUAGE.md: <Term> sharpened to <definition>._`

### 3. ADR gate (propose an ADR only when ALL three are true)

A terminology decision becomes an ADR **only** when:

1. **Hard to reverse** — the term is encoded in a public interface, schema, persisted state, or cross-cutting convention. Renaming later would touch many call sites.
2. **Background required** — someone returning to this code without you would be confused why this term was chosen without context.
3. **Real trade-off** — there was a genuine alternative that you rejected for a non-obvious reason.

When all three hold: write `docs/adr/NNNN-<slug>.md` using the project's ADR format (ask if none exists). **One ADR per decision. Do not batch.**

When fewer than three hold: the glossary entry alone is enough — an ADR would be ceremony.

### 4. Distinguish consuming vs changing

- **Consuming** the glossary (any skill, one-line habit): read `UBIQUITOUS_LANGUAGE.md` for canonical names before using a term; cite it as `UBIQUITOUS_LANGUAGE.md:<Term>`.
- **Changing** the glossary: that's this skill's job. Don't silently coin new terms in another skill — route here.

## Batch Mode — First Extraction

Use when no glossary exists yet, or the user explicitly asks for a fresh pass.

### 1. Scan the conversation

For domain-relevant nouns, verbs, and concepts. **Only include terms with domain meaning** — skip generic programming terms (cache, queue, handler) unless the project gives them a specific meaning. Before adding a term, ask: is this a concept unique to this project, or a general programming concept? Only the former belongs.

### 2. Identify problems

- Same word used for different concepts (ambiguity)
- Different words used for the same concept (synonyms)
- Vague or overloaded terms
- Terms used in code but never defined

### 3. Propose canonical glossary

Opinionated. Pick the best term, list the others as aliases to avoid.

### 4. Write to file

Use the output format below.

### 5. Output a summary

Inline in the conversation.

## Output Format

Write `UBIQUITOUS_LANGUAGE.md` with this structure:

```md
# Ubiquitous Language

_Last updated: YYYY-MM-DD_

## [Domain cluster 1]

| Term        | Definition                                              | Aliases to avoid      |
| ----------- | ------------------------------------------------------- | --------------------- |
| **Order**   | A customer's request to purchase one or more items      | Purchase, transaction |

## Relationships

- An **Order** produces one or more **Invoices**
- An **Invoice** belongs to exactly one **Customer**

## Example dialogue

> **Dev:** "When a **Customer** places an **Order**, do we create the **Invoice** immediately?"
> **Domain expert:** "No — an **Invoice** is only generated once a **Fulfillment** is confirmed."

## Flagged ambiguities

- "account" was used to mean both **Customer** and **User** — these are distinct concepts.

## Revision history

- 2026-06-18: **Fulfillment** sharpened from "shipping event" to "post-shipment state until delivery confirmed". Supersedes prior definition.
```

For **multi** layout: the root `UBIQUITOUS_LANGUAGE.md` becomes an index pointing at `docs/glossary/<subdomain>.md` files; each subdomain file uses the single-layout structure above. Don't pre-build the multi layout — promote from single when the threshold (40+ terms or two subdomains with minimal overlap) actually hits.

## Rules

- **Be opinionated.** Pick the best term, list others as aliases to avoid.
- **Flag conflicts explicitly.** Ambiguity → call out in "Flagged ambiguities" with a clear recommendation.
- **Only domain-meaningful terms.** Skip module/class names unless they carry domain semantics.
- **One-sentence definitions.** Define what it IS, not what it DOES.
- **Show relationships.** Bold term names, express cardinality where obvious.
- **Group into clusters** when natural (subdomain, lifecycle, actor). Single table is fine if cohesive.
- **Example dialogue.** 3-5 exchanges between dev and domain expert that exercise the terms and clarify boundaries.
- **Revision history.** Append-only. Never silently rewrite a definition — supersede it with a dated entry.

## Anti-Patterns

- ❌ **Batching inline updates.** "I'll update the glossary at the end of the session" — you will forget, and the decision's context will be gone.
- ❌ **Skipping the ADR gate** when a hard-to-reverse decision lands. The glossary entry alone leaves the *why* invisible.
- ❌ **Proposing ADRs for trivial terminology.** An ADR per synonym swap is ceremony.
- ❌ **Importing general programming terms** (cache, queue, batch) as if they were domain terms.
- ❌ **Renaming a term without a revision-history entry.** Future readers will think the glossary was always this way.

## Re-running (batch mode)

When invoked again:

1. Read the existing `UBIQUITOUS_LANGUAGE.md`
2. Incorporate new terms from subsequent discussion
3. Update definitions if understanding evolved (with revision-history entries)
4. Re-flag new ambiguities
5. Rewrite the example dialogue to incorporate new terms

## Composability

- **grilling** (deep mode) calls this skill inline to harden terminology as decisions land.
- **design-interface** reads this skill's output before naming interface elements.
- **tdd** Phase 1 (Planning) reads this skill's output to use canonical names in test descriptions.
- **skill-forge** Leading Words rule reuses both this glossary and `rules/architecture-language.md` when drafting new skills.
