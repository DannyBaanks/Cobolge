# Cobolge v2.0 — Motores Malbolge Classic & Unshackled (3^19) en GnuCOBOL 3.2

[![Version](https://img.shields.io/badge/version-2.0-blue.svg)](https://github.com/DannyBaanks/Cobolge)
[![GnuCOBOL](https://img.shields.io/badge/GnuCOBOL-3.2%2B-orange.svg)](https://gnucobol.sourceforge.io/)
[![Tests](https://img.shields.io/badge/tests-PASS-brightgreen.svg)]()

Motor de Malbolge Classic y Unshackled (3^19) implementado en GnuCOBOL 3.2 con shim C de baja latencia compatible con arquitecturas LP64 y LLP64.

Miembro de la **Flota de Consenso Multi-Oráculo v2.0** del ecosistema Malbolge de ISyCo junto a Zigbolge v2.0, Rustbolge v2.0 y Fortranbolge v2.0.

## Contrato de ejecución

```bash
cobolge <program.mal> [max_steps] [--snapshot-out f] [--resume f] [--json] < input
```

Con `--json`, la salida del programa se emite por `stdout` con encuadre LF; el reporte final de telemetría de la máquina se emite como JSON compacto por `stderr`.

## Compilación

### Linux (GnuCOBOL / gcc)

```bash
mkdir -p bin
cobc -free -x -O2 -o bin/cobolge src/cobolge.cob c/shim.c
```

### Windows (MSYS2 UCRT64)

```powershell
cobc -free -x -O2 -o bin/cobolge.exe src/cobolge.cob c/shim.c
```

## Verificación

El fixture canónico Classic (`tests/fixtures/hello_classic.mal`) ejecuta exactamente `Hello, world.` en 48 pasos, finalizando con registros `a=19758, c=85, d=63`, estado `HALTED` y causa `VInstruction`.

El snapshot en paso 17 es bit-exacto respecto al fixture canónico con SHA-256:
`29372aad12caa5afd340328d6c9afb51408a3a60a477bda94a671a0dd79a2fe4`.

### Suite de pruebas

- **Linux (bash):** `./tests/run_tests.sh`
- **Windows (PowerShell):** `powershell -File tests/run_tests.ps1`

## Unshackled 3^19

El runtime completo de 19 trits está implementado en `src/cobolge19.cob` con su codec posicional en `src/cobolge19_codec.cob`.
