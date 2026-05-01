# Interaction Patterns

Reusable UI mechanics — patterns for handling specific interaction types across any site. Orthogonal to domain knowledge: this is "how to do X" not "how to use site Y".

## Pattern Files

Each file covers one interaction type with:
- **Problem**: what makes this interaction tricky
- **Strategy**: general approach
- **browser-use commands**: concrete command sequence
- **Fallback**: what to try when the strategy fails

## Usage

When you encounter a tricky UI element (iframe, shadow DOM, dynamic dropdown, etc.), check this directory first. If you develop a new pattern during a session, add it here.
