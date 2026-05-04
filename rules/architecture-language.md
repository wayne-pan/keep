# Architecture Language

Use these terms exactly. Don't substitute "component," "service," "API," or "boundary."

## Terms

**Module** — Anything with interface + implementation. Scale-agnostic: function, class, package, or tier-slice. _Avoid_: unit, component, service.

**Interface** — Everything a caller must know: type signature, invariants, ordering, error modes, config, performance. _Avoid_: API, signature (too narrow).

**Implementation** — Body of code inside a module. Distinct from Adapter: a thing can be a small adapter + large implementation (Postgres repo) or vice versa (in-memory fake).

**Depth** — Leverage at the interface: behaviour per unit of surface area. Deep = much behind small interface. Shallow = interface nearly as complex as implementation.

**Seam** — Place to alter behaviour without editing that place. Where interface lives. _Avoid_: boundary (overloaded with DDD).

**Adapter** — Concrete thing satisfying an interface at a seam. Describes role, not substance.

**Leverage** — What callers get from depth. One implementation pays across N call sites + M tests.

**Locality** — What maintainers get from depth. Change concentrates in one place; fix once, fixed everywhere.

## Principles

- Depth is a property of the interface, not implementation. Deep modules can have internal seams.
- Deletion test: delete the module. If complexity vanishes, it was a pass-through. If it reappears across N callers, it earned its keep.
- Interface is the test surface. If you test past it, the module shape is wrong.
- One adapter = hypothetical seam. Two adapters = real one. Don't seam unless something varies.

## Dependency Categories

| Category | Example | Testing |
|----------|---------|---------|
| In-process | Pure computation | Merge modules, no adapter |
| Local-substitutable | SQLite for Postgres | Test with stand-in, internal seam |
| Remote but owned | Your own services | Port at seam, HTTP prod + in-memory test |
| True external | Third-party | Injected port, mock in tests |
