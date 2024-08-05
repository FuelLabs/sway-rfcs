- Feature Name: (fill me in with a unique ident, `my_awesome_feature`)
- Start Date: (fill me in with today's date, YYYY-MM-DD)
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC intends to propose a scheme to track changes in the compiler. 

# Motivation

[motivation]: #motivation

The compiler needs a guide on how to introduce changes to improve developer experience every time a compiler is updated.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

## PR changes

Every PR will have a section named "Release Notes", which will contains a user friendly explanation of what the PR contains.

The compiler release notes **WILL** be the amalgamation of these section "as is".

## Feature flags

Any complex change that needed to be gated will need the following steps.

1 - A specific github issue labeled with `feature-*` and `track-feature`. This issue should be the umbrella for everything related with this feature;
2 - A preliminary PR enabling the feature flag should be created and linked in to the umbrella issue; This PR will enable the feature flag `--experimental <comma-separated-list>` on all tools.
3 - As many PRs will be created and merged an normal;
4 - When the feature is ready, a closing PR will be created and wait until the feature flag is enabled by default.
5 - On a later date, the feature flag can be removed making the feature the default behavior of the compiler. 

# Enabling features on `sway`

Features can be enabled inside the `Forc.toml` file:

```toml
experimental = ["...", "..."]
```

or using the CLI

```
> forc ... --experimental some_feature,another_feature
```

These flags also need to be enabled programmatically by any compiler driver, like tests.

Unlike `Rust` we will not support features inside sway code like the example below, because some features will span across multiple tools. That would demand `forc` to parse, or ask the `sway` compiler if a feature is enabled or not. 

```sway
#![enable(some_experimental_feature)]
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This RFC intends to propose a scheme to track changes in the compiler. These changes will be categorized into two ways:

1 - Non-breaking changes;
2 - Breaking changes.

Breaking changes will be any changes that, after updating the compiler version, causes:

1 - Code without deprecated warning to be flagged as error;
2 - ABI json properties to be removed or have their type changed;
3 - SDK (rust, typescript and others) to break;
4 - Receipt parsers to break;

The following changes are **not** considered to be breaking changes:

1 - Code flagged with deprecated warning to be flagged as error;
2 - Code that required an experimental flag, but now are the default behavior to compile;
3 - Contract ID to change;
4 - new ABI json properties;

## Minor Version Updates

When a developer updates to a different minor version, it is expected no breaking changes, except for severe bugs.

Minor changes will consider these to be breaking and non-breaking changes:

### Breaking Changes 

1 - If any new warning, error or other diagnostic are emitted;
2 - If any ABI json properties are removed or have their type changed;
3 - If any code using SDK (rust, typescript and others) stop working;
4 - If any receipt cannot be parsed anymore;
5 - If any "contract id" changes;
6 - Semantic changes

### Non-breaking Changes

1 - new ABI json properties;
2 - Changing one warning by another, or one error by another;
3 - Code that was **NOT** compiling, but now is.

## Major Version Updates

Major update is the opportunity to introduce breaking changes, but they cannot be introduced abruptly, and depending on the change, will need to be introduced into phases.

Changes that only affect the compiler/language, can be introduced freely following sway pace. Changes that interact with others tools, will need to be introduced into phases and in coordination with others tools.

These changes will need to be behind "feature flags", which will be described later.

### Changes can be introduced directly

1 - Warning, errors and diagnostics can be changed freely;
2 - Changes that cause "contract ids" to change;

### Changes that need to be gated

1 - If any ABI json properties are removed or have their type changed;
2 - If any code using SDK (rust, typescript and others) stop working;
3 - If any receipt cannot be parsed anymore;
4 - Semantic changes

## Exceptions for bug fixes

If a bug needs to introduce a breaking change will, by default, be introduced in the next major version. If the nature of the bug demands a urgent fix, and would not be appropriated to force users to "buy" all other changes, a minor change with breaking change can be generated.

# Possible changes

This section contains the suggested guide on how to introduce changes into different parts of the compiler and associated tools.

## Lexer and Parser

To allow as user friendly error messages as possible, in all possible cases we want both lexer and parser to parse the new syntax even with the feature off.

After that, lexer, parser will mark that a experimental feature was lexed/parsed; and a check will guarantee that no disabled experimental was parsed.

The error message will have a message explaining that feature is experimental and a github link for more details on the stabilization lifecycle.

## Formatting

When formatting does not depend on a flag, formatting should always format new syntax, even when the flag is off. To avoid breaking other parts of the code, or even worst, removing code.

## LSP

LSP can take advantage of specific error messages, and suggest user to enable the corresponding feature.
## TODO


3 - Lexer?
4 - Parser?
5 - CST?
6 - AST?
7 - Typed Tree
8 - LSP
9 - Forc and plugins
10 - swayfmt
11 - New error

# Drawbacks

[drawbacks]: #drawbacks

Why should we *not* do this?

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

- Why is this design the best in the space of possible designs?
- What other designs have been considered and what is the rationale for not choosing them?
- What is the impact of not doing this?

# Prior art

[prior-art]: #prior-art

These are the sources and stacks used as motivation for this RFC.
 
## How `rustc` does it

https://rustc-dev-guide.rust-lang.org/implementing_new_features.html#stability-in-code

1 - Open a tracking issue;
2 - Pick a name for the feature gate;
3,4 - Add the feature gate to the compiler code;
5 - If the feature gate is not set, you should either maintain the pre-feature behavior or raise an error, depending on what makes sense;
6 - Add a test to ensure the feature cannot be used without a feature gate;
7 - Add a section to the unstable book;
8 - Write a lot of tests for the new feature;
9 - Get your PR reviewed and land it.

## changeset

https://github.com/changesets/changesets

# Unresolved questions

[unresolved-questions]: #unresolved-questions


# Future possibilities

[future-possibilities]: #future-possibilities

