---
name: keep:onboard
triggers: ["/keep:onboard"]
description: First-run personalization wizard. TRIGGER when: user says /keep:onboard, first session, or asks to set up preferences.
---

# Onboard — First-Run Personalization Wizard

TRIGGER when: user says /keep:onboard, first session, or asks to set up preferences.

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
