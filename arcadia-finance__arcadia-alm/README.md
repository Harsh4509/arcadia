# Arcadia ALM

ALM vaults for Aerodrome V3 (Metadex) concentrated-liquidity pools.

## Setup

```sh
npm ci --ignore-scripts
forge build
forge test
```

Run Foundry from the repository root. Invoked as `forge test --root <path>` from elsewhere, the fuzz and
invariant counterexample caches are written under the shell's working directory rather than under `--root`,
where they are keyed by test contract name and shared with any other project rooted there.

Node 22 or newer and Foundry 1.8.1 are required. Dependencies are managed through `package.json`; the two Metadex packages are pinned to commits on their `contest` branches.
