# Review Checklists and Anti-Rationalizations

## Layered Review Protocol

Inspired by software test pyramid: mechanical checks first, subjective last.
Each layer has explicit pass criteria. All must pass.

### L1: Syntax & Basics (auto-scan)

Fast mechanical checks. Any failure = mandatory fix.

- [ ] All changed files pass syntax check (`bash -n`, `python3 -c "import ast..."`, `node --check`)
- [ ] No debug artifacts (`console.log`, `print("debug")`, `breakpoint()`, TODO/FIXME in changed lines)
- [ ] No hardcoded secrets or credentials
- [ ] Import paths valid (no broken imports)
- [ ] No dead code in diff (unreachable branches, unused variables)

**Pass**: Zero hits on all scans.

### L2: Logic & Patterns (structural review)

Check code behavior and patterns. Most findings live here.

- [ ] Off-by-one errors in loops, slicing, indexing
- [ ] Null/empty/undefined handling on all code paths
- [ ] Error handling covers actual failure modes (not just generic catch)
- [ ] Return values checked (not silently discarded)
- [ ] Race conditions in concurrent/shared state code
- [ ] Resource cleanup (file handles, connections, temp files)
- [ ] No copy-paste bugs (similar blocks with subtle differences)

**Pass**: All items verified, or explicitly documented why they don't apply.

### L3: Security & Depth (targeted audit)

Context-dependent deep checks. Focus on blast radius from Step 2.

- [ ] Injection: user input → SQL/query/command string? Parameterized?
- [ ] XSS: user input → HTML/response? Escaped?
- [ ] Auth: permission checks present where needed?
- [ ] Data exposure: sensitive data in logs, error messages, URLs?
- [ ] Dependencies: new imports vetted? Known vulnerabilities?
- [ ] Breaking changes: API contracts preserved for callers?
- [ ] Performance: N+1 queries, unbounded allocations, missing indexes?

**Pass**: All applicable items verified. N/A items explicitly noted.

### L4: Holistic Quality (final judgment)

Single pass reading the complete diff as a reviewer. Answer one question:

**"Would I approve this PR without hesitation?"**

- [ ] Change scope matches intent (no scope creep)
- [ ] Each change is atomic (one purpose per commit)
- [ ] Code reads naturally (no "what is this doing?" moments)
- [ ] Tests cover the happy path AND the failure path
- [ ] No better/simpler alternative exists for the same result

**Pass**: Confident yes to the core question. If any hesitation, identify what needs to change.

## Flat Checklist (Quick Reviews)

For small diffs (<20 lines), use this condensed version:

- [ ] Logic correctness
- [ ] Error handling
- [ ] Security (injection, XSS, secrets)
- [ ] Performance (N+1, allocations)
- [ ] Edge cases (null, empty, concurrent)
- [ ] Test coverage
- [ ] API contract (breaking changes)
- [ ] Code style consistency

## Anti-Patterns with Examples

### 1. Drive-by Refactoring

**Task:** Fix empty email crash

```diff
  def validate_user(data):
-     if not data.get('email'):
+     email = data.get('email', '').strip()
+     if not email or not email.strip():
          raise ValueError("Email required")
-     if '@' not in data['email']:
+     # "Improved" validation beyond the fix:
+     if '@' not in email or '.' not in email.split('@')[1]:
+         raise ValueError("Invalid email")
-     if not data.get('username'):
+     username = data.get('username', '').strip()
+     if not username or len(username) < 3:
+         raise ValueError("Username too short")
```

**Flag:** Username validation, length check, `.split('@')[1]` — none trace to "fix empty email crash."
**Rule:** Every changed line must trace to the user's request.

### 2. Speculative Abstraction

**Task:** Calculate a discount

```python
# ❌ Strategy pattern, config class, min/max purchase — 40 lines
class DiscountStrategy(ABC):
    @abstractmethod
    def calculate(self, amount: float) -> float: ...

class PercentageDiscount(DiscountStrategy): ...
class FixedDiscount(DiscountStrategy): ...

@dataclass
class DiscountConfig:
    strategy: DiscountStrategy
    min_purchase: float = 0.0
```

```python
# ✅ One function, 3 lines
def calculate_discount(amount: float, percent: float) -> float:
    return amount * (percent / 100)
```

**Flag:** If only one discount type exists, the abstraction is speculative.
**Rule:** No abstractions for single-use code. Add complexity when the requirement arrives, not before.

### 3. Silent Assumption

**Task:** "Export user data"

```python
# ❌ Assumes: all users, JSON file, all fields, local disk
def export_users():
    users = User.query.all()  # Privacy? Pagination?
    with open('users.json', 'w') as f:
        json.dump([u.to_dict() for u in users], f)  # All fields? Sensitive?
```

```python
# ✅ Surface assumptions before coding
# "Export" could mean: API endpoint, file download, background job.
# "Users" could mean: all, filtered, paginated.
# Clarify scope before writing code.
```

**Flag:** `query.all()`, hardcoded path, `to_dict()` without field filter — all unverified assumptions.
**Rule:** Uncertain? Stop and ask. State assumptions explicitly.

## Anti-Rationalizations for Review

| Rationalization | Reality |
|---|---|
| "The code looks fine" | Read it. Line by line. Confidence without evidence is just guessing. |
| "This is self-evident" | Then documenting it costs nothing. Skipping it risks everything. |
| "Edge case won't happen in practice" | It will. In production. At 3 AM. Check it anyway. |
| "It's just a small change" | Small changes cause the most incidents because reviewers skip them. |
| "Tests exist for this" | Run them. If you haven't seen them pass, they don't count. |
| "I don't need to check that file" | You do. Dependencies and callers are where bugs hide. |
| "This is how the existing code does it" | Existing code has bugs too. Don't propagate bad patterns. |
| "AI-generated code is probably fine" | AI code needs more scrutiny, not less. It's confident and plausible even when wrong. |
| "I'll flag it as low priority" | If you found it, it's worth a concrete fix or a concrete dismissal. Don't hedge. |
| "No security issues here" | Did you actually check? Injection, XSS, secrets, auth bypass — verify each explicitly. |
