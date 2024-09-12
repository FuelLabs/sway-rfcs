- Feature Name: changes-lifecycle
- Start Date: 2024-08-05
- RFC PR: [FuelLabs/sway-rfcs#41](https://github.com/FuelLabs/sway-rfcs/pull/41)

# Summary

[summary]: #summary

This RFC is a guide on how to introduce changes following the compiler release lifecycle.

# Motivation

[motivation]: #motivation

To maximize user experience when updating the compiler, we need a guide on how to introduce changes.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

The compiler will follow a "rolling release" scheme, which means that periodically (to be specified) a
new version will be released.

This means that as soon as the compiler reaches version "1.0.0", the next **version** will be "1.1.0"; and
after that and if needed, the next **patch** would be "1.1.1".

The only changes that will trigger "patches" are:

1. Urgent security fixes;
2. Fixing bugs that render "stable" functionality unusable;

## Release Notes

To track all release notes, a special file named `ReleaseNotes.md` will be created in the repository's root directory.

When a version is being launched, for example, `1.10` a new section `1.11-nightly` will be created empty. From this time on, all new PRs will create a new item under the "next version", `1.11-nightly` in this example.

Each item will follow the template:

```
# Version 1.11-nightly

## Forc

### Added
### Changed
### Deprecated
### Removed
### Fixed
### Security

## Tools

...

## Sway

...

## Standard Libraries

...

# Version 1.10

...
```

Inside each section, items will follow the template of a user friendly one line description and a link to the PR.

```
- Index operator using Index trait [#6356](https://github.com/FuelLabs/sway/pull/6356)
```

Given that all PRs will touch this file, to avoid conflicts and decrease the experience when merging them, we will use "git custom merge driver" ([https://git-scm.com/docs/gitattributes#\_defining_a_custom_merge_driver](https://git-scm.com/docs/gitattributes#_defining_a_custom_merge_driver)).

This allows a custom merge strategy to a specific file using ".gitattributes".

```
ReleaseNotes.md merge=union
```

## Breaking changes

A breaking change is a difference in functionality from the previous version of the compiler that may require an update to Sway code in order for it to compile.

The following changes are defined to be breaking changes and will need to follow the process of being gated by feature flags.

1. Code without deprecated warning to be flagged as an error;
2. ABI JSON properties to be removed or have their type changed;
3. Binary encoding that will break how SDK (and others) communicate with the compiler, including:
   - How scripts/predicates accept arguments on `main`;
   - How scripts/predicates return data from `main`;
   - How the `contract method selector` is encoded;
   - How `contract method` arguments are encoded;
   - How `log` data is encoded;
   - How `message` data is encoded;
4. IR changes;
5. Receipt parsers to break;
6. When a compiler feature or a standard library produces different behavior for the same code (semantic changes);
7. When `storage` is impacted. Particularly addresses.

## Feature flags

Any complex change that needs to be gated will follow these steps.

1. A specific GitHub issue labeled with `feature-*` and `track-feature`. This issue should be the umbrella for everything related to this feature;
2. A preliminary PR enabling the feature flag should be created and linked to the umbrella issue; This PR will enable the feature flag `--experimental <comma-separated-list>` on all tools.
3. As many PRs will be created and merged as normal;
4. A chapter inside `Sway Unstable Book` will be created and updated as needed;
5. When the feature is ready, a closing PR will be created and wait until the feature flag is enabled by default.
6. On a later date, the feature flag can be removed making the feature the default behavior of the compiler.

Once the feature is merged into `master`, it will not be possible to "turn off" the feature. In the same sense
that it is not possible to "turn off" a "match expression" or any other language feature.

If the feature contains some configuration or choice, the "default" value will be the default, and other options
will be available, but it cannot be turned off.

## Conditional compilation

There are cases where conditional compilation will be needed. For these cases, each experimental feature will also have a corresponding `#[cfg(...)]`, like the example below:

```sway
#[cfg(experimental_new_encoding = false)]
const CONTRACT_ID = 0x14ed3cd06c2947248f69d54bfa681fe40d26267be84df7e19e253622b7921bbe;
#[cfg(experimental_new_encoding = true)]
const CONTRACT_ID = 0x316c03d37b53eaeffe22c2d2df50d675e2b2ee07bd8b73f852e686129aeba462;
```

# Enabling features on Sway

Features can be enabled inside the `Forc.toml` file:

```toml
experimental = ["...", "..."]
```

or using the CLI

```
> forc ... --experimental some_feature,another_feature
> forc ... --no-experimental some_feature,another_feature
```

or even using environment variables

```
> FORC_EXPERIMENTAL=some_feature,another_feature forc ...
> FORC_NO_EXPERIMENTAL=some_feature,another_feature forc ...
```

The order matters so for example if `feature_a` is turned on on `test.toml`, it can be turned off by the CLI or by environment variables.

If a feature is not turned on by `forc.toml`, it can still be turned on by the CLI and environment variables.

A special token `*` will mean "all features" in the sense that all features can be turned on or turned off.

```
> forc ... --experimental *
```

This is specially useful to control which features are enabled

```
> forc .. --no-experimental * --experimental some_feature
```

These flags also need to be enabled programmatically by any compiler driver, like tests.

Unlike `Rust` we will not support features inside Sway code like the example below, because some features will span across multiple tools. That would demand `forc` to parse, or ask the Sway compiler if a feature is enabled or not.

```sway
#![enable(some_experimental_feature)]
```

## Unstable book

The idea of an unstable book is to be a repository of documentation, decisions, or even a devlog of the feature.
Its unstructured nature is intentional and serves the purpose of unburdening developers to keep an update and formal
documentation of a feature that will likely change.

Ideally, each chapter will have a link to the GitHub issue, discussions, references and whatever else is necessary
to allow stakeholders to give feedback on the new feature.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This section contains the suggested guide on how to introduce changes to different parts of the compiler and associated tools.

## `sway-features` crate

A new crate named `sway-features` will be created and will contain **ALL** features and their metadata. The best suggestion is a macro to define features where enums, documentation, etc., will be generated.

This macro also needs to generate code for the errors and warnings related to each error.

Features will be parsed in this order:

```rust
let mut features = ExperimentalFeatures::default();
features.parse_from_toml();
features.parse_from_cli();
features.parse_from_environment_variables();
```

This means that environment variables overwrite CLI arguments, which overwrite TOML configuration.

If a feature requires or allows new configurations, these configurations should be optional, and as soon as confirmed the feature is enabled, it should verify if the required configuration is available.

```
> forc ... --experimental a_feature --a-feature-option 1
```

## Lexer and Parser

To allow as user-friendly error messages as possible, in all possible cases, we want both the lexer and the parser to parse the new syntax even with the feature off.

After that, the lexer and the parser will mark that an experimental feature was lexed/parsed; and a check will guarantee that no disabled experimental was parsed.

The error message will have a message explaining that the feature is experimental and a GitHub link for more details on the stabilization lifecycle.

```rust
// always parse new syntax
let new_syntax = parse_new_syntax();
if ctx.experimental.is_disabled(Features::NEW_FEATURE) {
   handler.emit_error(...);
}
```

## Formatting

Formatting should always format new syntax, even when the flag is off. To avoid breaking other parts of the code, or even worse, removing code.

## LSP

LSP can take advantage of specific error messages, and suggest users to enable the corresponding feature.

## CST, AST, and Typed Tree

All trees must always support new features, which means that new nodes will always exist. Their specific behavior, desugaring, etc., will be gated by the experimental feature.

More specifically, this means that variants should not be behind compiler flags.

## Tests

To allow these experimental features to be tested, it is necessary to specify which configurations each test must run.
Today, by default, a test runs with the "default compiler configuration", but it is necessary to allow tests to
run with any combination of compiler configuration.

To allow complete tests of any compiler configuration, any configuration that today resides inside `test.toml`
needs to be configured for each configuration.

An example is the `encoding v1` which has different inputs and outputs from `encoding v0` when testing a script
that takes arguments.

The easiest way to approach this seems to be to support multiple `test.toml` with a suffix to differentiate them.

```
test.toml
test.feature_a.toml
```

To avoid duplications `test.feature_a.toml` can inherit properties from `test.toml`.
And some new properties can be created to allow the configuration of the compiler:

```
[environment_variables]
SOME_VAR = "1"

[forc]
cli = "--experimental feature_a,feature_b"
```

The same strategy can be used for snapshot tests. We can use multiple `snapshot.toml` and create different
snapshots using the file suffix. So `snapshot.feature_a.toml` will generate `snapshot@feature_a.snap`.

# Drawbacks

[drawbacks]: #drawbacks

This will increase the complexity of the compiler. Not all flags used to compile end up in the JSON ABI, or other outputs. Which can make reproducibility harder.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

There are only two other alternatives, which we consider the worst options:

1. Keep experimental features in branches;
2. Keep experimental features behind compiler flags (conditional compilation);

The first one normally creates more problems than it solves. "Integration hell" becomes a reality sooner than later.
The second does not decrease the complexity of the code, and it decreases the testability of features, given that they will not be in the "release binary".

# Prior art

[prior-art]: #prior-art

These are the sources and stacks used as motivation for this RFC.

## How `rustc` does it

https://rustc-dev-guide.rust-lang.org/implementing_new_features.html#stability-in-code

1. Open a tracking issue;
2. Pick a name for the feature gate;
3. Add the feature gate to the compiler code;
4. If the feature gate is not set, you should either maintain the pre-feature behavior or raise an error, depending on what makes sense;
5. Add a test to ensure the feature cannot be used without a feature gate;
6. Add a section to the unstable book;
7. Write a lot of tests for the new feature;
8. Get your PR reviewed and land it.
9. Add a section to the unstable book;

## changeset

https://github.com/changesets/changesets

## keepachangelog

Changes will categorized following https://keepachangelog.com/en/1.1.0/

# Unresolved questions

[unresolved-questions]: #unresolved-questions

## Where should we save "release notes"?

1. In files inside the repo? - Saving in files sounds like the best approach, but if we use the same file, all PRs will conflict. To avoid this we can do like `changeset` and use random names.
2. In GitHub PR descriptions? - This is the easiest approach, but it can be cumbersome to recover these messages.
3. In git commit messages? - Given that the commit message is "created" when the PR is merged, there is no way to guarantee that "release notes" will exist or be "parseable" when we need them.
   - https://git-cliff.org/

## Should new warnings be considered breaking changes?

1. Normally warnings should not be considered breaking changes, because they do not break anything.
2. On the other hand, if the team treats warnings as errors, new warnings will break CIs, and demand
   developers' attention. Not all fixes are trivial and can demand bigger code changes than the user would expect
   from a minor update from the compiler.

## How to deal with "contract id"?

Should we consider contract ID changes to be breaking changes?

# Future possibilities

[future-possibilities]: #future-possibilities
