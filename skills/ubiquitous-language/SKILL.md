---
name: keep:ubiquitous-language
version: "1.0"
triggers: ["/keep:ubiquitous language", "/keep:glossary", "/keep:terminology", "/keep:domain terms", "/keep:domain model", "/keep:DDD", "/keep:define terms", "/keep:ubiquitous"]
description: >
  Extract a DDD-style ubiquitous language glossary from the current conversation,
  flagging ambiguities and proposing canonical terms. Saves to UBIQUITOUS_LANGUAGE.md.
  TRIGGER when: user wants to define domain terms, build a glossary, harden terminology,
  create a ubiquitous language, or mentions "domain model" or "DDD".
  Do NOT trigger for: general coding tasks, file edits, or when user doesn't ask about terms.
resources: []
---

# Ubiquitous Language

Extract and formalize domain terminology from the current conversation into a consistent glossary, saved to a local file.

## Process

1. **Scan the conversation** for domain-relevant nouns, verbs, and concepts
2. **Identify problems**:
   - Same word used for different concepts (ambiguity)
   - Different words used for the same concept (synonyms)
   - Vague or overloaded terms
3. **Propose a canonical glossary** with opinionated term choices
4. **Write to `UBIQUITOUS_LANGUAGE.md`** in the working directory
5. **Output a summary** inline in the conversation

## Output Format

Write a `UBIQUITOUS_LANGUAGE.md` file with this structure:

```md
# Ubiquitous Language

## [Domain cluster 1]

| Term        | Definition                                              | Aliases to avoid      |
| ----------- | ------------------------------------------------------- | --------------------- |
| **Order**   | A customer's request to purchase one or more items      | Purchase, transaction |

## [Domain cluster 2]

| Term         | Definition                                  | Aliases to avoid       |
| ------------ | ------------------------------------------- | ---------------------- |
| **Customer** | A person or organization that places orders | Client, buyer, account |

## Relationships

- An **Order** produces one or more **Invoices**
- An **Invoice** belongs to exactly one **Customer**

## Example dialogue

> **Dev:** "When a **Customer** places an **Order**, do we create the **Invoice** immediately?"
> **Domain expert:** "No — an **Invoice** is only generated once a **Fulfillment** is confirmed."

## Flagged ambiguities

- "account" was used to mean both **Customer** and **User** — these are distinct concepts.
```

## Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others as aliases to avoid.
- **Flag conflicts explicitly.** If a term is used ambiguously, call it out in "Flagged ambiguities" with a clear recommendation.
- **Only include terms relevant for domain experts.** Skip module names or class names unless they have meaning in the domain language. Before adding a term, ask: is this a concept unique to this project, or a general programming concept? Only the former belongs.
- **Keep definitions tight.** One sentence max. Define what it IS, not what it does.
- **Show relationships.** Use bold term names and express cardinality where obvious.
- **Group terms into multiple tables** when natural clusters emerge (by subdomain, lifecycle, or actor). If all terms belong to a single cohesive domain, one table is fine.
- **Write an example dialogue.** A short conversation (3-5 exchanges) between a dev and a domain expert that demonstrates how the terms interact naturally and clarifies boundaries between related concepts.

## Re-running

When invoked again in the same conversation:

1. Read the existing `UBIQUITOUS_LANGUAGE.md`
2. Incorporate any new terms from subsequent discussion
3. Update definitions if understanding has evolved
4. Re-flag any new ambiguities
5. Rewrite the example dialogue to incorporate new terms
