- Feature Name: (fill me in with a unique ident, `my_awesome_feature`)
- Start Date: (fill me in with today's date, YYYY-MM-DD)
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC is a guide on how to introduce breaking changes following the compiler release lifecycle.

# Motivation

[motivation]: #motivation

To maximize user experience when updating the compiler, we need a guide on how to introduce breaking changes.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

The compiler will follow a "rolling release" scheme, which means that periodically (to be specified) a
new major version will be released.

This means that as soon as the compiler reach version "1.0.0", the next **major version** will be "1.1.0"; and
after that and if needed, the next **minor version** would be "1.1.1".

The only changes that will trigger "minor updates" are:
1 - Urgent security fixes;
2 - Bugs that render "stable" functionality unusable;

## PR changes

Every PR will have a section named "Release Notes", which will contains a user friendly explanation of what the PR contains.
That allows the whole team to understand the impact of the change, if it contains breaking changes or not, and correctly
configure the PR to the next major or minor update.

The compiler release notes **WILL** be the amalgamation of these section "as is".

## Breaking changes

A breaking change is a difference in functionality from the previous version of the compiler that may require an update to sway code in order for it to compile.

The following changes are defined to be breaking changes, and will need to follow the process of being gated by features flags.

1 - Code without deprecated warning to be flagged as error;
2 - ABI json properties to be removed or have their type changed;
3 - Binary encoding that will break how SDK (and others) communicate with the compiler, that includes

- How scripts/predicates accept arguments on `main`;
- How scripts/predicates return data from `main`;
- How the `contract method selector` is encoded;
- How `contract method` arguments are encoded;
- How `log` data is encoded;
- How `message` data is encoded;

  4 - Utilization of new VM opcodes;
  5 - IR changes
  6 - Receipt parsers to break;
  7 - When a compiler feature or a standard library produce different behavior for the same code (semantic changes);

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

Why should we _not_ do this?

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

Where should we save "release notes"?
1 - In files inside the repo? - Saving in files sounds the best approach, but if we use the same file, all PRs will conflict. To avoid this we can do like `changeset` and use random names.
2 - In github PR descriptions? - This is the easiest approach, but it can be cumbersome to recover these messages.
3 - In git commit messages? - Given that the commit message is "created" when the PR is merged, there is no way to guarantee that "release notes" will exist or be "parseable" when we need them.

Should new warnings be considered breaking changes?
1 - Normally warnings should not be considered breaking changes, because they do not break anything.
2 - But on the other hand, if the team treat warnings as errors, new warnings will break CIs, and demand
developers attention. Not all fixes are trivial, and can demand bigger code changes than the user would expect
from a minor update from the compiler.

# Future possibilities

[future-possibilities]: #future-possibilities

`
