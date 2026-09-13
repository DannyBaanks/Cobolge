# Cobolge

Classic Malbolge engine implemented in GnuCOBOL 3.2.

## Contract

```text
cobolge <program.mal> [max_steps] [--snapshot-out f] [--resume f] [--json] < input
```

With `--json`, raw program output is written to stdout with one framing LF;
the final machine report is written as compact JSON to stderr.

## Verification

The canonical Classic fixture passes with `Hello, world.`, 48 steps, final
registers `a=19758, c=85, d=63`, status `HALTED`, and halt reason
`VInstruction`.

The step-17 snapshot is byte-identical to the canonical fixture with SHA-256
`29372AAD12CAA5AFD340328D6C9AFB51408A3A60A477BDA94A671A0DD79A2FE4`.

See `tests/run_tests.ps1` for the repeatable checks.

## Unshackled 3^19

The complete local 3^19 runtime is implemented in `src/cobolge19.cob`.
`src/cobolge19_codec.cob` is its small standalone positional codec probe.
The minimum `ubO`/`Z` execution gate passes; broad differential corpus coverage
remains pending.
