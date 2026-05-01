---
name: keep:tdd
version: "1.0"
triggers: ["/keep:tdd", "/keep:test-driven", "/keep:red-green-refactor", "/keep:test first", "/keep:write tests first"]
description: >
  Test-driven development with red-green-refactor loop. TRIGGER when: user wants to
  build features or fix bugs using TDD, mentions "red-green-refactor", "/keep:test first",
  "TDD", or asks for test-driven development. Uses vertical tracer bullets, not
  horizontal slicing. Do NOT trigger for: general testing questions, running existing tests.
resources: ['subagents']
---

# Test-Driven Development

## Philosophy

**Core principle**: Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means. Warning sign: your test breaks when you refactor, but behavior hasn't changed.

Uses the vocabulary from [rules/architecture-language.md](../../rules/architecture-language.md) — **module**, **interface**, **seam**, **adapter**, **depth**, **leverage**, **locality**.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things rather than user-facing behavior
- Tests become insensitive to real changes
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test -> one implementation -> repeat.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED->GREEN: test1->impl1
  RED->GREEN: test2->impl2
  RED->GREEN: test3->impl3
  ...
```

## Workflow

### 1. Planning

Before writing any code:

- [ ] Confirm with user what interface changes are needed
- [ ] Confirm which behaviors to test (prioritize — you can't test everything)
- [ ] Identify opportunities for **deep modules** (small interface, deep implementation)
- [ ] Design interfaces for testability (accept dependencies, don't create them)
- [ ] List the behaviors to test (not implementation steps)
- [ ] Get user approval on the plan

Ask: "What should the public interface look like? Which behaviors are most important to test?"

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior -> test fails
GREEN: Write minimal code to pass -> test passes
```

This is your tracer bullet — proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test -> fails
GREEN: Minimal code to pass -> passes
```

Rules:
- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

### 4. Refactor

After all tests pass, look for refactor candidates:

- [ ] Extract duplication
- [ ] **Deepen modules** (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

## Mocking Guidelines

Mock at **system boundaries** only:

| Mock these | Don't mock these |
|-----------|-----------------|
| External APIs (payment, email) | Your own classes/modules |
| Databases (prefer test DB when possible) | Internal collaborators |
| Time/randomness | Anything you control |
| File system (sometimes) | Pure functions |

**Designing for mockability**: Pass external dependencies in (dependency injection), not created internally. Prefer SDK-style interfaces (specific functions per operation) over generic fetchers.

## Deep Modules in TDD

A **deep module** has a small interface hiding significant complexity. A **shallow module** has a large interface with thin implementation.

When designing test interfaces:

- Can I reduce the number of methods?
- Can I simplify the parameters?
- Can I hide more complexity inside?

The **deletion test**: imagine deleting the module. If complexity reappears across N callers, the module was earning its keep. If complexity vanishes, it was a pass-through.

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```

## Seam Discipline

- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't introduce a port unless at least two adapters are justified (typically production + test).
- A deep module can have **internal seams** (private to its implementation, used by its own tests) as well as the **external seam** at its interface. Don't expose internal seams through the interface just because tests use them.

## Testing Strategy: Replace, Don't Layer

- Old unit tests on shallow modules become waste once tests at the deepened module's interface exist — delete them.
- Write new tests at the deepened module's interface. The **interface is the test surface**.
- Tests assert on observable outcomes through the interface, not internal state.
- Tests should survive internal refactors — they describe behaviour, not implementation.
