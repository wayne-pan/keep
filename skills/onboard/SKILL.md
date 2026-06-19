---
name: keep:onboard
version: "1.0"
triggers: ["/keep:onboard"]
description: >
  First-run personalization wizard. TRIGGER when: user says /keep:onboard, first
  session, or asks to set up preferences. Do NOT trigger for: editing existing
  preferences (point user to ~/.claude/rules/personal.md), general config questions.
---

# Onboard — First-Run Personalization Wizard

## Steps

1. **Check flag**: If `~/.claude/mem/onboarded` exists, say "Already onboarded. Edit ~/.claude/rules/personal.md to update preferences." and stop.

2. **Collect preferences** via AskUserQuestion:
   - Name (or alias) for personalization
   - Primary languages/frameworks (multi-select: Python, TypeScript, Go, Rust, Java, Other)
   - Project patterns: solo/team, open-source/private, mono-repo/poly-repo
   - Verbosity: concise (terse) vs detailed (explanations)
   - Preference for Chinese/English responses (if applicable)

3. **Write `~/.claude/rules/personal.md`**:
```markdown
## Personal Preferences
- Name: {name}
- Languages: {languages}
- Projects: {pattern}
- Verbosity: {verbosity}
- Language: {response_lang}
```

4. **Create flag file**: `touch ~/.claude/mem/onboarded`

5. **Confirm**: "Preferences saved. Run /keep:onboard again to update."

## Notes
- If user declines or skips, still create flag file with defaults
- Don't overwrite existing personal.md — merge new values
- All fields optional; defaults: name="", languages=["Python"], pattern="solo", verbosity="concise"

## Examples

**Good onboard flow**:
```
1. User runs /keep:onboard for first time
2. ~/.claude/mem/onboarded does NOT exist → proceed
3. AskUserQuestion collects: name=Pan, languages=[Python, TypeScript],
   pattern=solo, verbosity=concise, response_lang=中文
4. Write ~/.claude/rules/personal.md with collected values
5. touch ~/.claude/mem/onboarded
6. Confirm: "Preferences saved."
```

**Bad onboard flow**:
```
1. User runs /keep:onboard (already completed last week)
2. ~/.claude/mem/onboarded exists
3. WRONG: skip the check, ask all questions again, overwrite personal.md
RIGHT: detect flag, say "Already onboarded. Edit ~/.claude/rules/personal.md
       to update preferences." and stop immediately.
```

**Edge case — user skips mid-wizard**:
```
- Still create ~/.claude/mem/onboarded (so wizard doesn't re-trigger)
- Write personal.md with defaults plus any collected answers
- Confirm: "Skipped with defaults. Run /keep:onboard again to update."
```
