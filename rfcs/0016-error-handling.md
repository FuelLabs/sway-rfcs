- Feature Name: `error_handling`
- Start Date: 2025-05-14
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC defines guidelines on error handling for developers of reusable Sway libraries and applications. It aims for achieving consistent and predictable behavior in case of errors across the ecosystem. Implementing it will guarantee a smooth error troubleshooting experience, at zero-cost, unless opted-in for an acceptable on-chain cost.

The proposed approach strives to strike a balance between: 
- code readability and convenience (e.g., using guard functions for testing preconditions instead of in-place `if !<precondition> { panic ... }`),
- performance (e.g., having zero-cost error messages by default),
- troubleshooting experience (e.g., pointing to exact location in code where the error occurs).

# Motivation

[motivation]: #motivation

[ABI errors](0014-abi-errors.md) bring improved debugging and troubleshooting experience at possible zero-cost. **But those improvements and zero-cost can be achieved only if the feature is adequately and consistently used across libraries and applications.**

Currently, we have a consistent approach to recoverable errors, through the usage of the `std::result::Result` type. Irrecoverable errors, however, are handled less consistently, combining several approaches:
- using `__revert` often with `0` as argument,
- using various `std::revert::*` functions,
- using `std::assert::*` functions, mostly in tests, **but also in non-test code, e.g. in the `std` implementation, examples, etc.**.

On top of these existing approaches, ABI errors bring the `panic` expression, potentially increasing the level of inconsistency. Moreover, the benefits of the `panic` expressions can be fully achieved only if it is used in alignment with best practices detailed in this RFC.

This RFC aims for a clear guideline on how to properly utilize ABI errors, `panic` expression in particular.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

Throughout this RFC, we use the following terms:
- _end-developer_ for application developers, who write they own code over which they have full control, and reuse Sway libraries, over whose implementation and behavior they have no control.
- _reusable library_ for any dependency, that the end-developer has no control over, i.e., cannot opt in or out of a certain behavior of individual functions/methods. This includes `std`, libraries provided by Fuel, like, e.g., `sway_libs`, or any third-party libraries.
- _application_ for any end-developer code. This will usually mean contracts, scripts, or predicates, but can also mean application specific local libraries, that the end-developer has a full control of.

When it comes to error handling, end-developers cannot influence implementation and behavior of _reusable libraries_ they use as dependencies. That's why we expect _reusable libraries_ to follow strict guidelines, to fullfil the expectations listed in the below chapter.

## Error handling in reusable libraries

[error-handling-in-reusable-libraries]: #error-handling-in-reusable-libraries

When using _reusable libraries_ the end-developers will expect the following:
1. In case of irrecoverable errors, the error location will always be in the library code that has caused the issue.
1. In case of irrecoverable errors, there will be no on-chain cost for error handling by default, unless the developer opts-in for a cost via dedicated API.
1. Error type enums will have the prefix `Error`. E.g., `AccessError`.
1. Error messages will be helpful and follow a consistent pattern and wording.

The above expectations imply the following rules for implementing _reusable libraries_:
1. _Reusable libraries_ will never use helper functions like `assert`, `revert`, or `require`. **Because, in the case of using those helpers, the error location will be in the helper and not in the library code.** Instead, they will use the `panic` expression directly, ensuring the error location being in the library code.
1. _Reusable libraries_ will exclusively use strings for formulating error messages in the default API. Using enums would result in increase of bytecode size that cannot be opted in or out by end-developers. Providing additional information via non-unit enum variants might be useful in certain cases. For such cases, a dedicated opt-in API should be provided. An example would be `Result::unwrap` and `Result::expect` methods. The former, considered the default, will `panic` with zero-cost and useful common error message, while the latter will provide rich information, but with on-chain overhead. Important is that the developer can opt-in and accept that cost and is not getting it as default.

For helpful and consistent error messages, the proposal is to consistently use full sentences that answer the question "What has happened, where, and, ideally, why?". E.g.:
- "`u8::add` (+) has overflowed." Not: "u8 add overflow", etc.
- "The sender was not the owner. Only owners can renounce ownership."
- "`u256::log2` was called for `u256` zero. Logarithm is undefined for zero."
- "`Result::unwrap` was called on `Err` variant."

Types and method names should be enclosed in `backticks`. This makes them stick out as entities and convenient to define without escaping quotes in error messages that will always be Sway string slices. (Note that Sway still does not support escape characters in string slices.)

Why adding a failing function/method name in the message? ABI errors contain source code location, but not the failing function/method name. To find which exact function fails, one must look at the source code, which is an inconvenient indirection. That's the reason for including the "where", the function/method name, in the message itself, to immediately provide more context. (Adding support for showing the function/method name is discussed in [Future possibilities](#future-possibilities).)

## Error handling in applications

In applications, end-developers can choose between the performance and the convenience, but we must clearly document the tradeoffs. E.g., 

```sway
require(<some check>, "Some check must pass.");
```

will result in the error message being stored on-chain, contributing to the bytecode size.

On the contrary, the more verbose:

```sway
if !<some check> {
    panic "Some check must pass.";
}
```

will result in the error message not being stored on-chain.

## Error handling in Sway tests and SDKs

`forc test` will have first-class support for ABI errors and `panic` expression. For every revert caused by `panic`king, it will show the package, file location, error message, and the logged error value if available.

If the `panic` argument was an error type whose instance is composed of other error types, the error messages will be extracted and shown for all the nested error type instances. E.g., assuming we have:

```sway
#[error_type]
pub enum StorageError {
    #[error(m = "Some storage error.")]
    SomeStorageError: (),
    ...
}

#[error_type]
pub enum ContractError {
    #[error(m = "Error in contract while accessing storage.")]
    StorageError: StorageError,
    ...
}
```

Panicking with `panic ContractError::StorageError(StorageError::SomeStorageError)` will result in two error messages:

```
Some storage error.
└ Error in contract while accessing storage.
```

In a general case, `forc test` will display the tree of error messages pointing to the root cause(s):

```
Final error.
├ Cause 1.
└ Cause 2.
  └ Root cause.
```

The `#[test]` attribute will be extended with additional arguments, to enhance asserting on expected `panic`king:
- `should_panic` (without values) will assert if the test reverts with a compiler generated revert code. The difference between the existing `should_revert` and `should_panic` is, that the former can assert _any_ revert and can specify the expected revert id, while the latter can only assert that the revert code was compiler generated (>= 0xffff_ffff_0000_0000).
- `panic_msg = "<regex>"` asserts that the error message related to the `panic`king matches the provided `regex`,
- `panic_value = "<regex>"` asserts that the logged error value related to the `panic`king matches the provided `regex`. The values will be displayed as decoded logs are currently displayed. The `regex` must match the displayed representation. E.g., if the logged error value is `MyEnumVariant(MyStruct { x: 42 })` we can assert it with any of the following regexes, depending on the required strictness: `42`, `x..42`, `MyStruct.*x.*42`.

Similarly, the SDKs will recognize reverts coming from `panic`king and display their ABI error information accordingly.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Adapt compilation of `panic` to avoid structural changes in the `std`

Currently, the implementation of `panic` wraps the argument into an `encode` call to be able to log it. This makes it impossible to use `panic` even with constant string slice arguments in `std` modules like `ops`, because of circular dependencies with the `codec` module. Rather then restructuring the standard library, we will change the compiler to recognize constant string slices as a special case and do not `encode` them, which will remove the need for `encode`ing and thus the circular dependency.

## Extend the `#[test]` attribute

Adding the proposed new arguments to the `#[test]` attribute is a straightforward reuse of the existing compiler infrastructure for declaring attributes, and does not require any changes in the compiler.

## Adapt existing reusable libraries

The majority of the work will go into adapting the `std` and other libraries to follow the guidelines presented in [Error handling in reusable libraries](#error-handling-in-reusable-libraries).

All the existing enums used for error reporting, like, e.g. `standards::src5::AccessError` will be annotated as `#[error_type]`s.

As an example of a typical adaptation of a _reusable library_, let's consider the `sway_libs::ownership` module. Calling `only_owner` as an entry guard in every `ownership`'s function as it is now, would result in an ABI error always located in the `std::revert::require` function. This is against the guidelines, as it provides an error location unnecessary separated through two levels of indirection from the actual guard invocation point.

Instead, we should introduce a private `is_owner` function and panic in every `sway_libs::ownership`'s function separately:
```
if !is_owner() {
    panic AccessError::NotOwner;
}
```
This is more verbose, but provides optimal troubleshooting experience.

**Note that the `only_owner` function still remains and can be used by end-devs as a guard in _applications_, as it is used now.** Important is, that the end-developers can make their own choice between readability, performance, and troubleshooting experience.

## Consolidate `std::assert` and `std::revert` modules

The existing helper functions in the `std::assert` and `std::revert` modules will be changed as detailed below. The `std::revert` module could be in the end removed altogether, depending on the decisions we take on the `revert` and `require` functions (see: [Unresolved questions](#unresolved-questions)).

### `revert` and `revert_with_log`

`revert` and `revert_with_log` will be deprecated, with the deprecation note suggesting using the `panic` expression as alternative.

`revert_with_log` currently accepts any `AbiEncode`able parameter, whereas `panic` is more restrictive and expects an `Error`. We see this restriction as a desirable design choice. A revert should always be accompanied with a helpful error information, and not just any value, without additional context. What would make sense here, though, to gain more flexibility, is extending error types to also support structs (see: [Future possibilities](#future-possibilities)).

### `assert`

The current `assert` function brings as much harm as benefit. The lack of any contextual information (code line, error message) in practice always enforces commenting out `assert` calls in code, until the failing one is detected. This is definitely a suboptimal troubleshooting experience.

Replacing the current contextless `assert(condition: bool)` by `assert<T>(condition: bool, error: T) where T: Error` would enforce best practices by requiring developers to provide contextual information via error message.

In tests, `assert` is mostly used to test equalities, and that almost exclusively for `AbiEncode`able types. Using the `assert_eq` for such cases significantly improves the troubleshooting experience.

Therefore, by extending `assert` with the `error` parameter, and promoting the usage of `assert_(n)eq`, we essentially enforce via API the best practice of providing helpful debugging information.

As a part of the consolidation, the existing contextless `assert(<v1> == <v2>)` lines in tests will be replaced with troubleshooting friendly `assert_eq(<v1>, <v2>)` for all `AbiEncode`able types.

The functions in `std::assert` will be rewritten to use `panic` internally. This will remove the need for hardcoded `ASSERT_SIGNAL`s constant, provide logged information tied to the error (currently, in case of additional logs, developers need to know to look at the last logs), and allow usage of the new `#[test]` arguments (`panic_msg` and `panic_value`). An error type enum `AssertError` will be introduced:

```sway
pub struct AssertEq<T> where T: AbiEncode {
    pub expected: T,
    pub actual: T,
}

#[error_type]
pub enum AssertError<T> where T: AbiEncode {
    #[error(m = "`std::assert::assert` has failed.")]
    Assert: T,
    #[error(m = "`std::assert::assert_eq` has failed.")]
    AssertEq: AssertEq<T>,
    #[error(m = "`std::assert::assert_neq` has failed.")]
    AssertNeq: T,
}
```

This means that a typical failing assert will result in an error message like:

```
`std::assert::assert` has failed.
└ This is the exact user-defined helpful message.
```

Note that in this case we panic on error type enums and not on hardcoded string slices, thus introducing overhead. This is not in the collision with the second point in the guidelines (zero-cost), because:
- end-developers can always choose to use `if + panic` directly instead of `assert`.
- we assume `assert_eq` and `assert_neq` to be used exclusively in tests and not on-chain.

### `require`

Having `assert<T>(condition: bool, error: T) where T: Error` eliminates the need for a separate `require` function, or at least makes the existing question of the difference between `assert` and `require` more prominent.

The proposal is to deprecate `require` and replace it by `assert<T>(condition: bool, error: T) where T: Error`. This proposal is controversial. The argumentation for it is the following. `assert` is Rust inspired API and is used both in tests and non-test code. `require` is intended to check pre- or post conditions and is inspired by Solidity's `require` function. It the context of blockchain development in Rust it is used as well, e.g., in the [anchor_lang](https://docs.rs/anchor-lang/latest/anchor_lang/index.html), Rust eDSL for writing Solana programs.

Having both `assert` and `require` introduces confusion on intended usage. Should `assert` be used only in tests? Or also for catching internal errors in non-test code? If so, we have it currently inconsistently used even in the `std`, e.g., in the `std::math`.

From the Rust-inspired perspective, it is enough having only `assert` to ensure invariants. Using `assert` for catching internal errors is problematic in terms of gas cost and bytecode size, if they get left in code. The only way to currently "remove" such asserts in `release` builds is to comment them out. To fully support the uses case of debug-time asserts we should introduce `debug_assert` (see: [Future possibilities](#future-possibilities)). From that perspective, having an `assert` in non-test code would immediately imply checking invariants.

The counterargument is, that `require` is well established and understood, especially for the developers with the Solidity background. Having it next to `assert[_(n)eq]` can cause confusion when to use which, but the distinction can be explained in the documentation and enforced by guidelines: `require` for invariants, and `assert`s for tests (and, eventually, `debug_assert` for catching internal errors).

## Adapt `std::result::Result`

In the case of the `std::result::Result`, the `unwrap` method will panic with a hardcoded string slice to guarantee zero-cost. The `expect` will panic with a message and error like now, wrapped in the `ResultError`:

```sway
#[error_type]
pub enum ResultError<M, E> where M: AbiEncode, E: AbiEncode {
    #[error(m = "`Result::expect` was called on `Err` variant.")]
    ExpectCalledOnErr: (M, E),
    ...
}
```

Additionally, we can enforce the `Err` variant to be an `Error` instance (see: [Unresolved questions](#unresolved-questions)).

## Develop migrations

The migration steps for all the changes described above can be written using existing infrastructure provided in the `forc-migrate` tool.

# Drawbacks

[drawbacks]: #drawbacks

The only drawback is the implementation effort. However, the ABI errors become useful **only** if the ecosystem of _reusable libraries_ properly utilize the `panic` expression. Not investing effort into described implementation means rendering the effort that went into development of ABI errors useless.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

The proposed approach strives to strike a balance between: 
- code readability and convenience (e.g., using `only_owner` as a guard instead of `if !is_owner() { panic ... }`),
- performance (e.g., having zero-cost string slice error messages vs providing additional information via error type enums),
- troubleshooting experience (e.g., pointing to exact location in code, rather then in helper function that panics).

The proposed approach empowers the end-developer to always be able to consciously choose between the three, whereas the _reusable libraries_ guarantee zero-cost errors by default.

This comes at cost of putting more effort in writing _reusable libraries_. E.g, forbidding usage of helper functions, providing opt-in API with richer error messages etc.

Alternative was consider, where _reusable libraries_ by default provide rich information. This goes against Sway's philosophy of not paying upfront for what one potentially does not need.

Providing a "detailed panicking" version of a _reusable library_ that could be turned on in a compilation profile, was also considered. E.g., `<u8 as Add>::add` might provide exact values that have caused an overflow when compiled with such flag or in tests:

```sway
...
if panic_on_overflow_enabled() {
    #[cfg(any(detailed_panic = true, test = true))]
    panic OpsError::Overflow(self, other);

    #[cfg(all(detailed_panic = false, test = false))]
    panic "`u8::add` (+) has overflowed.";
} else {
    ...
}
...
```

The benefits of such optional "detailed panicking" is hard to estimate at the moment, compared to additional feature complexity and additional development effort.

# Prior art

[prior-art]: #prior-art

The concepts of recoverable errors modeled by `std::result::Result` and irrecoverable by reverting are already a part of Sway error handling. This RFC proposes a way of replacing low-level-reverting with `u64` error codes with higher-level concept of panicking with rich error information.

The major conceptual difference between panicking in Rust and Sway is the inability to provide a backtrace (stacktrace). Strictly speaking, this would be possible but at way-to-high and unacceptable gas and bytecode cost.

Having preconditions checked by guard functions like `only_owner` is an established pattern. E.g., in Solidity often achieved using [function modifiers](https://docs.soliditylang.org/en/latest/contracts.html#function-modifiers). The proposal still encourages their usage, but only in the _applications_ code.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

1. Should we force `Result::Err` variant to be an `Error` (`where E: Error`)? In practice, it is already either an error enum or a string, so the change will not be perceived as restriction. The benefit is, that the caller can always panic on the content of the `Err` variant. Moreover, if we extend `#[error_type]` to support structs, there will very likely be no real case for the `Err` not to be an `Error`. Also, the similar argument applies like for the `revert_with_log` - we enforce errors to ensure always having helpful troubleshooting information.
1. Should we deprecate `require` an replace it with `assert(condition, error)`?
1. Should we use simpler glob patterns instead of regular expressions in the `panic_msg` and `panic_value` arguments of the `#[test]` attribute? Regular expressions are mightier, but can be cumbersome for simpler matches, especially when matching dots.
1. Should we still keep the `std::revert::revert(code: u64)`? The reason for the proposed deprecation is the assumption that reverting with a `u64` error code will not be needed in _applications_. By removing it, we again enforce best error handling practices by expecting end-developers to use `panic` and provide rich error messages. Is there a use case for _applications_ to have a need to revert on an error code? Like following a certain SRC?

# Future possibilities

[future-possibilities]: #future-possibilities

## Implementing `#[error_type]` for structs

It is a straightforward extension. It would make `#[error_type]` further similar to Rust's `#[thiserror::error]` attribute and allow specifying a single rich error information without forcibly wrapping it into an error type enum with a single variant.

## Implementing `debug_assert`

It can be easily achieved if we implement `#[cfg]` on expressions:

```sway
fn debug_assert(...) {
    #[cfg(debug_assertions = true)]
    assert(...); // Will be optimized away, turning `debug_assert` in noop in `release` builds.
}
```

## Extending `#[error]` attribute with `help` and `url` arguments

To provide additional, detailed help or to link to external documentation, both optional. E.g.:

```
#[error(m = "Error message.", help = "Detailed explanation.", url = "https:://url.to.external/help/123")]
```

## Extending ABI `errorCodes` with failing function name

Currently, if the name of the failing function/method is not provided in the error message, as proposed in this RFC, the developer will have to look at the failing package source code to detect the failing function. Failing function name is in a way an elementary information and often the first starting point in troubleshooting.

It would be ideal to have it included in the `errorCode` section of the ABI and automatically displayed via tooling.

This requires developing compiler support for getting a unique string representation of a function/method. E.g.:

```sway
<Point<u8, u8> as Add>::add(self, other: Point<u8, u8>)
```

## Detailed panicking compilation profile

As explained in [Rationale and alternatives](#rationale-and-alternatives).

## Supporting `str` constants

Currently, Sway doesn't support `str` constants:

```sway
const C: str = "";
         ^^^
`str` or a type containing `str` on `const` is not allowed.
```

In the context of error handling, supporting `str` constants would allow reuse error messages without hardcoding them in several `panic` occurrences.

Also, if zero-cost is required, instead of enum type errors whose all variants are units and do not carry any additional useful information, `str` constants conveniently grouped by common prefix could be used. E.g., instead of:

```sway
#[error_type]
pub enum SomeError {
    #[error(m = "First error has happened.")]
    First: (),
    #[error(m = "Second error has happened.")]
    Second: (),
}
```

developers can rather opt for zero-cost, `const` based version:

```sway
const SOME_ERROR_FIRST: str = "First error has happened.";
const SOME_ERROR_SECOND: str = "Second error has happened.";
```

## Introducing question mark operator `?`

Same as in Rust, for propagating erroneous values to the calling function.
