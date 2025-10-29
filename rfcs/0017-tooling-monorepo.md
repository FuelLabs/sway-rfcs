
# RFC: Forc Tooling Monorepo Split
- **Feature Name:** `forc_tooling_monorepo`
- **Start Date:** 2025-10-29
- **RFC PR:** [FuelLabs/sway-rfcs#0017](https://github.com/FuelLabs/sway-rfcs/pull/0017)

---
## Summary
The Sway repository currently hosts the compiler, language-aware tooling, and all client-facing `forc` binaries under a single workspace and synchronized release cycle. This RFC proposes establishing a dedicated **`forc-tooling` monorepo** for client and infrastructure tooling, while keeping compiler-adjacent binaries (`swayfmt`, `sway-lsp`, and the forthcoming `sway-doc`) within the Sway repository.

The new repository would:
- Ship wrapper binaries (`forc-fmt`, `forc-lsp`, `forc-doc`, `forc-migrate`) and operational tooling such as `forc-node`, `forc-client`, `forc-crypto`, and `forc-wallet`
- Allow **independent release cadences** and changelogs for each crate
- Eliminate heavy dependencies (e.g. `fuel-core`) from compiler builds
- Maintain a unified developer experience through `forc`, `fuelup`, `fuel.nix`, and nightly distributions.

---
## Motivation
Today, compiler and tooling teams share a single monorepo. Every workspace member must publish in lockstep, and compiler CI is burdened by dependencies from operational tooling (notably `fuel-core` via `forc-node`). This coupling inflates build times and increases breakage risk.

A split enables:
- Faster, independent iteration on operational binaries such as `forc-node`, `forc-client`, and `forc-wallet`
- A leaner compiler pipeline, isolated from infrastructure dependencies
- Continued tight coupling where it’s valuable (e.g. AST-aware utilities like `swayfmt` and `sway-lsp`)

This design balances **agility for the tooling team** and **stability for compiler developers**, while preserving a cohesive ecosystem for end users.

## Current Architecture
| Repository    | Category     | Components                                                                                                                                         |
| ------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sway`        | Binaries     | `forc`, `forc-pkg`, `forc-tracing`, `forc-test`, `forc-util`                                                                                       |
| `sway`        | Plugins      | `forc-client`, `forc-crypto`, `forc-debug`, `forc-doc`, `forc-fmt`, `forc-lsp`, `forc-mcp`, `forc-migrate`, `forc-node`, `forc-publish`, `forc-tx` |
| `sway`        | Applications | `swayfmt`, `sway-lsp`                                                                                                                              |
| `forc-wallet` | Binary       | `forc-wallet`                                                                                                                                      |

`forc-fmt` and `forc-lsp` are thin wrappers; the real implementations live in `swayfmt` and `sway-lsp`, which directly depend on compiler ASTs. Keeping those AST-aware binaries inside Sway ensures compiler changes are validated in CI and remain in lockstep.

Under the proposed architecture:
- Wrapper binaries like `forc-fmt`, `forc-lsp`, and `forc-doc`, `forc-migrate` move to the **tooling monorepo**, delegating functionality to compiler crates.
- New internal crates such as `sway-doc` or `sway-migrate` can follow this same pattern: core implementation in Sway, lightweight CLI in the tooling repo.
- `forc-wallet` joins the new monorepo, allowing the existing standalone repository to be retired.

### Distribution
Currently, `sway-nightly-binaries` publishes `forc`, `fuel-core`, and `forc-wallet`. Post-split, it will source `forc-wallet` and other operational tooling artefacts from the new monorepo. Both `fuel.nix` and `fuelup` will update paths to reference the correct origins while preserving atomic toolchain installs.

---
## Guide-Level Explanation
From a user’s perspective, nothing changes — `forc` still provides the same subcommands.  
Internally, however:
- `forc-fmt`, `forc-lsp`, `forc-migrate` and `forc-doc` delegate to compiler-maintained crates (`swayfmt`, `sway-lsp`, `sway-migrate`, `sway-doc`).
- Operational tools (`forc-node`, `forc-client`, `forc-crypto`, `forc-wallet`) are built and released from the new **`forc-tooling`** repo.
- Each crate has its own changelog and versioning cadence.
- `fuelup` and `fuel.nix` handle dual sources transparently.

### Repository Boundaries
| Repository       | Responsibility                                  | Notes                                                                                                                            |
| ---------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **Sway**         | Compiler, language services, AST-aware binaries | Publishes `swayfmt`, `sway-lsp`, `sway-doc`, `sway-migrate` , and related libraries consumed by tooling wrappers                 |
| **Forc-tooling** | CLI wrappers and operational tools              | Hosts `forc-fmt`, `forc-lsp`, `forc-doc`, `forc-node`, `forc-client`, `forc-crypto`, `forc-wallet`, and tracing/deploy utilities |

Both repos maintain independent CI pipelines:
- **Sway CI:** Compiler validation and language tooling regression tests
- **Tooling CI:** End-to-end integration and compiler compatibility checks

### Release Pipeline
- Tooling crates publish independently via the `forc-tooling` CI pipeline.
- Compatibility is tracked via a shared `compatibility.toml`, mirrored across both repos.
- `fuelup` reads dual manifests and installs atomic toolchains from separate channels.
- `fuel.nix` gains new inputs to pin compiler and tooling revisions independently.
---
## Implementation Plan
1. **Discovery and Alignment** — confirm scope, inventory binaries, define compatibility contract.
2. **Bootstrap `forc-tooling`** — scaffold repo, establish CI, port coding standards, pilot with `forc-wallet`.
3. **Migrate Operational Tooling** — move `forc-node`, `forc-client`, `forc-crypto`, and tracing crates; drop heavy deps from Sway.
4. **Introduce Wrapper Crates** — create `forc-fmt`, `forc-lsp`, and `forc-doc` delegating to compiler crates.
5. **Adapt Distribution Tooling** — update manifests, `fuelup`, `fuel.nix`, and nightly pipelines.
6. **Rollout and Monitoring** — release beta builds, collect telemetry, compare CI metrics, and refine docs.

---
## Drawbacks
- Multi-repo coordination increases overhead for cross-cutting changes.
- Temporary CI churn during migration.

---
## Rationale and Alternatives
- **Status quo:** Simpler, but slow CI, forced lockstep releases, and coupling between compiler and operational tooling.
- **Partial extraction:** Moving only heavy dependencies (e.g. `forc-node`) reduces build load but leaves version coupling.
- **Full split:** Moving everything out of Sway (including AST-aware crates) breaks compiler CI feedback and risks incompatibility.

The proposed **hybrid model** preserves compiler-tooling cohesion where it matters and autonomy where it doesn’t.

---
## Prior Art
- **Rust:** separates `rustc` and `cargo` lifecycles.
- **Tokio:** demonstrates multi-crate monorepos with per-crate semantic versioning.
- **Fuel precedent:** `forc-wallet` already lives outside Sway successfully.
- **Fuelup:** already installs multi-source components cohesively.

---
## Unresolved Questions
How does this affect documentation? If we move tooling docs over to the new monorepo then upstream documentation tools will need to be reconfigured to pull from this new source.