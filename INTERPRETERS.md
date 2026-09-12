# Interpreter genealogy

Cobolge is an independent GnuCOBOL implementation of Classic Malbolge. Its
machine semantics were checked against the existing Javolge reference and the
reporter backends in `malbolge-differential`; this records verification edges,
not source-code ancestry.

## Current evidence

The `hello_classic.mal` comparison is `CONSISTENT` across Rustbolge,
Swiftbolge, Javolge, and Cobolge:

```text
steps=48  a=19758  c=85  d=63  output="Hello, world."
```

Cobolge's step-17 snapshot also matches the canonical fixture byte-for-byte.
