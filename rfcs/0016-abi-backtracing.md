- Feature Name: `abi_backtracing`
- Start Date: 2025-07-03
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

ABI Backtracing brings an off-chain, almost zero-cost, opt-in backtracing/callstack capability to [ABI Errors](./0014-abi-errors.md). Via `backtracking` build option developers can opt-in for four degrees of details of backtracing information, for reverts caused by `panic` expressions. ABI Backtracing brings major extension to ABI Errors, by providing not only the location where the error occurs, but also the trace of function calls that lead to the error.

# Motivation

[motivation]: #motivation

[ABI errors](./0014-abi-errors.md) bring significant troubleshooting advantage at zero on-chain-cost, but with a limitation of providing only the location of the actual `panic` call.

This is especially limiting in cases of functions like `assert`, `assert_eq`, or `require`, where the error location will always be within those functions, whereas the actually relevant error location is the call-site. Such functions that check for preconditions and invariants, let's call them _guards_, are a common and often used pattern, especially in reusable libraries. One typical example would be the `sway_libs::ownership::only_owner` function. Not being able to point at the call-site as the error location of such functions is currently a significant practical limitation of ABI Errors.

Another class of functions where call-sites bring the actually useful information, and not the location of the `panic` calls, are the functions like `Option::unwrap`.

In these two cases, not having the callstack, or at least the immediate call-site, is conceptually very limiting. Needles to say, in all other cases, having a backtracing information will also significantly improve troubleshooting experience.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

Currently, if a `panic` occurs at runtime, tools, such as `forc test`, `forc call`, or SDKs, can provide the following troubleshooting information:
- error message
- error value
- `panic` location in code (package, its version, and the line and column)

For the remaining part of this RFC, the `forc test` will be used as example. A typical current `forc test` output containing all of the above would be:

```console
test some_test_for_admin_access, "path/to/failing/test.sw":42
    revert code: ffffffff00000007
    ├─ panic message: The provided identity is not an administrator.
    ├─ panic value:   NotAnAdmin(Address(Address(79fa8779bed2f36c3581d01c79df8da45eee09fac1fd76a5a656e16326317ef0)))
    └─ panicked in:   `only_admin` in auth_package@0.1.0, src/admin_access.sw:11:9
```

ABI backtracing will enrich the revert information with the **backtrace and function names**:

```console
test some_test_for_admin_access, "path/to/failing/test.sw":42
    revert code: ffffffff00000007
    ├─ panic message: The provided identity is not an administrator.
    ├─ panic value:   NotAnAdmin(Address(Address(79fa8779bed2f36c3581d01c79df8da45eee09fac1fd76a5a656e16326317ef0)))
    ├─ panicked in:   `only_admin` in auth_package@0.1.0, src/admin_access.sw:11:9
    └─ backtrace:
        └─ in `check_admin` call in my_package@1.2.3, src/preconditions.sw:42:8
            └─ in `check_access_rights` call in my_package@1.2.3, src/preconditions.sw:12:8
                └─ in `check_preconditions` call in my_package@1.2.3, src/preconditions.sw:52:8
                    └─ in `transfer_funds` call in funds_contract@0.2.5, src/main.sw:22:8
```

The backtrace will be limited to up to five back-calls. (The explanation for this limitation is given in the [Reference-level explanation](#reference-level-explanation).)

## Configuring the backtrace content

### Default builds

As it will be explained in the [Reference-level explanation](#reference-level-explanation), the ABI backtracing comes with a minimal on-chain cost, in terms of the bytecode size and gas usage. To allow developers to opt-in for this cost, backtracing will be configurable via dedicated `backtrace` build option.

To explain this build option, let use the following example. We will have five functions named `first`, `second`, ..., `fifth` that call each other sequentially, and the function `fifth` finally calling a failing `assert_eq`.

In the default `debug` build, the output of a failing `forc test` will look similar to this (package names and lines are omitted for brevity):

```console
test some_test, "path/to/failing/test.sw":42
    revert code: ffffffff00000007
    ├─ panic message: The provided `expected` and `actual` values are not equal.
    ├─ panic value:   AssertEq(AssertEq { expected: 42, actual: 43 })
    ├─ panicked in:   `assert_eq` in std@0.99.0, src/assert.sw:80:9
    └─ backtrace:
        └─ in `fifth` call in ...
            └─ in `fourth` call in ...
                └─ in `third` call in ...
                    └─ in `second` call in ...
                        └─ in `first` call in ...
```

In the default `release` build, the backtrace output will contain only the immediate call-site of the `assert_eq`:

```console
test some_test, "path/to/failing/test.sw":42
    revert code: ffffffff00000007
    ├─ panic message: The provided `expected` and `actual` values are not equal.
    ├─ panic value:   AssertEq(AssertEq { expected: 42, actual: 43 })
    ├─ panicked in:   `assert_eq` in std@0.99.0, src/assert.sw:80:9
    └─ backtrace:
        └─ in `fifth` call in ...
```

How is this achieved, or in other words, how the compiler knows which functions to include in the backtrace?

The backtrace can be directly influenced by developers, by utilizing the `#[trace]` attribute. The `#[trace]` attribute can be used everywhere where the `#[inline]` attribute can be used, means on functions that have implementations. Same like `#[inline]`, it also comes with two arguments, `always` and `never`.

The `#[trace(always)]` instructs the compiler to include the call-sites of such functions in the backtrace of default `release` builds. We expect this attribute to annotate guard functions, like aforementioned `assert`, `assert_eq`, `require`, and `only_owner`, or methods like `Option::unwrap`.

E.g, the `assert_eq` will be specified as follows:

```sway
#[trace(always)]
pub fn assert_eq<T>(expected: T, actual: T) where T: AbiEncode { ... }
```

Considering how low the on-chain cost of tracing guard's call-site is (more on this in the chapter [Runtime execution and bytecode and gas overhead](#runtime-execution-and-bytecode-and-gas-overhead)), this is a reasonable standard configuration for the `release` build.

By using `#[trace(never)]` developers can instruct the compiler not to include a function in a backtrace, even not in a `debug` build. This is useful, considering that the backtrace will be limited to five functions only. If an intermediate function call can be easily deducted, it might be worth not having it in the backtrace.

E.g., let's assume that the functions `fourth` and `second` are annotated with `#[trace(never)]`. The default `debug` build would then output the following backtrace:

```console
    └─ backtrace:
        └─ in `fifth` call in ...
            └─ in `third` call in ...
                └─ in `first` call in ...
```

### Custom builds

To give developers full control over the backtracing, the `backtrace` build option will be provided with the following values:

| Value | Meaning |
| ----- | ------- |
| all   | Backtrace all functions, even those annotated with `#[trace(never)]`. |
| all_except_never | Backtrace all functions, except those annotated with `#[trace(never)]`. This is the default for `debug` builds. |
| only_always | Backtrace only functions annotated with `#[trace(always)]`. This is the default for `release` builds. |
| none   | Do not backtrace any functions. This results in current ABI Errors behavior, with zero additional cost. |

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

A possibility to provide backtracks [was discussed in the original ABI errors RFC](https://github.com/FuelLabs/sway-rfcs/pull/43#discussion_r1858254347). It was discarded because of a high runtime cost. While this still holds for a general, full-blown backtracking as expected in non-blockchain languages and environments, in an attempt to solve the limitations around guard functions, a proof-of-concept was created, for a limited backtracing (up to five calls deep) with a minimal on-chain cost.

The fundamental assumptions and the mechanics of such backtracing is explained in details in the chapters below.

## Expected number of panic expressions and panicking calls

First we introduce a notion of a _panicking call_. A _panicking call_ is a function call that _might_ result in panicking. Note that we are talking strictly about panicking, and not reverting in general, because both ABI Errors and ABI Backtracking rely on the `panic` expression.

A function call might result in panicking if the called function, or any of the functions it internally calls, contains at least one `panic` expression.

We assume that the overall number of panicking calls in a realistic Sway program will always be _acceptably small_. Note that this is an assumption similar to the one we made when creating ABI Errors - that a number of `panic` expressions in a realistic Sway program will always be _acceptably small_. Although we never defined what that _acceptably small_ upper limit is, we are talking about less then hundred occurrences. Based on this assumption we assumed that the number of `errorCodes` entries in the ABI JSON file will never grow to unacceptable proportions.

A number of _panicking calls_ can and will very likely always be bigger then the number of `panic` expressions in code, but we still expect it to be _acceptably small_.

To support both assumptions, for the number of `panic` expressions and the number of _panicking calls_, I've examined the [Compolabs Orderbook Spark Market contract](https://github.com/compolabs/orderbook-contract/tree/master/spark-market). This is one of the biggest Sway contracts, where just the `main.sw` has ~50Kb in file size, and additional contract modules ~15Kbs. The contract in addition depends on the `sway-standards` and `sway-libs`.

The initial IR of that contract contains _57 reverts_ and _2542 function calls_. Even if all the reverts were generated by `panic` expressions, which will never be the case, this is still an _acceptably small_ number.

Those 2542 function calls call 214 unique functions. Some of those functions could panic, and thus their calls could be _panicking calls_. We are interested in the number of panicking calls in general, since we want to trace all of them in default `debug` builds, and in those coming from guards like `require` or functions like `Option::unwrap`, which we want to trace in default `release` builds. The latter we expect to be annotated with `#[trace(always)]` and to be the only traceable functions in `release` builds.

The statistics of those calls can be found in the `/files/0016-spark_orderbook_spark_market_function_calls_counted.csv` file. That statistics reveals the following:
- there are 585 potential _panicking calls_ in general,
- out of which, there are 158 potential `#[trace(always)]` _panicking calls_.

Although these numbers are significantly higher then the potential number of `panic` calls (<57), we can assume the following simplified model: **even in large Sway programs, the overall number of _panicking calls_ will be less than thousand, and the number of `#[trace(always)]` calls will be up to five times the number of `panic` occurrences in code which we expect to be less than hundred**.

## Providing panicking calls in ABI JSON

Each _panicking call_ will be identified by a unique number and provided in the new `panickingCalls` section in the ABI JSON.

E.g., for this _panicking call_ in a module `some_module` of a package `some_package`:

```sway
fn some_function() {
    let _ = this_function_might_panic(42);
}
```

the following ABI JSON entry would be created:

```json
"panickingCalls": {
    "1": {
        "pos": {
            "function": "some_package::some_module::some_function",
            "pkg": "some_package@0.1.0",
            "file": "src/some_module.sw",
            "line": 4,
            "column": 8
        },
        "function": "some_other_package::module::this_function_might_panic"
    },
}
```

Note that, based on the model elaborated in the previous chapter, for large Sway projects, we could end up:
- in ~600 such entries in `debug` builds,
- or in ~150 such entries in `release` builds.

## Encoding panicking calls and panic into revert codes

The only artefact a `panic` can produce at runtime, that will exist in all Sway program types (including predicates), is the revert code.

[ABI Errors](./0014-abi-errors.md) define revert codes produced by a `panic` as a compiler generated `u64` numbers above certain value, but without any particular meaning.

ABI Backtracing will produce revert code that will encode:
- the information that the revert is generated by a `panic` expression,
- the actual error code that can be located in the `errorCodes` section of the ABI JSON,
- up to five panicking call IDs, encoded in the order of calling, that can be located in the `panickingCalls` section of the ABI JSON.

The encoding of the `u64` revert code will work as following:

```console
1_pppppppp_CCCCCCCCCCC_CCCCCCCCCCC_CCCCCCCCCCC_CCCCCCCCCCC_CCCCCCCCCCC
```

- The leading `1` denotes a revert code generated by a `panic` expression. Arbitrary user-defined revert codes will must have the starting bit set to `0` or in other words be less then or equal to `9223372036854775807₁₀ = 7FFFFFFFFFFFFFFF₁₆`.
- The `pppppppp` denotes the error code in the `errorCodes` section of the ABI JSON, that identifies the actual `panic` location.
- Each `CCCCCCCCCCC` section denotes a panicking call code in the `panickingCalls` section of the ABI JSON. The calls represent the callstack, where the right-most code is the code of the immediate function call in which the `panic` occurs. If all `C`s a zero it means no-call. This will happen if the actual call-depth is less then five calls.

Note that this encoding allows for `2^8 = 256` unique error codes, and `2^11 - 1 = 2047` unique panicking calls. (A panicking call cannot be zero, which is used to distinguish a no-call. Therefore, the `- 1`.) These are both far above our _acceptably small_ numbers discussed in the chapter [Expected number of panic expressions and panicking calls](#expected-number-of-panic-expressions-and-panicking-calls).

Note that we might also go with 10 bits for encoding panicking call IDs, and with 8 + 5 = 13 bits for encoding `panic` locations. This will still be above the discussed _acceptably small_ numbers.

## Runtime execution and bytecode and gas overhead

A revert code produced by a `panic` expression is not a compile-time constant anymore, but rather depends on the runtime call-chain that led to a particular panicking.

In other words, the revert code must encode the _panicking_calls_ prior reaching the `panic` expression, and in the end, in case of panicking, embed the error code that uniquely identifies that exact `panic` expression.

How is such resulting revert code produced?

Every _panicking function_ will get a compiler generated additional `__backtrace: u64` argument. **This argument is added in the IR generation**, but for the sake of simplicity, in the below examples, we will discuss how the equivalent Sway code would look like.

E.g., the `this_function_might_panic` shown above will become `fn this_function_might_panic(x: u64, __backtrace: u64)` in the IR. Note that, by definition, the `same_function` can also panic, and thus it also gets the additional `__backtrace: u64` argument.

The above call will then, in the IR, become:

```sway
fn some_function(__backtrace: u64) {
    let __backtrace = <calculate backtrace>;
    let _ = this_function_might_panic(42, __backtrace);
}
```

How is the `__backtrace` calculated at runtime?

We just need to left-shift the existing `__backtrace` provided by the caller function and append/bitwise OR the unique panicking call ID of the exact `this_function_might_panic` call, which is a compile-time, compiler-generated constant:

```sway
fn some_function(__backtrace: u64) {
    let __backtrace = (__backtrace << 11) | BELOW_PANICKING_CALL_UNIQUE_ID;
    let _ = this_function_might_panic(42, __backtrace);
}
```

Note that we cannot add the `__backtrace` argument to entries like `main`. If the `this_function_might_panic` is called within an `<entry>`, the `__backtrace` will just be the panicking call unique ID:

```sway
fn <entry>() {
    let _ = this_function_might_panic(42, BELOW_PANICKING_CALL_UNIQUE_ID);
}
```

If the `this_function_might_panic` does not participate in backtracing, e.g., in the `release` mode, or if annotated with `#[trace(never)]`, the `__backtrace` argument will either be passed from the caller, or be zero in case of the caller being an entry:

```sway
fn <entry>() {
    let _ = this_function_might_panic(42, 0_u64);
}

fn some_function(__backtrace: u64) {
    let _ = this_function_might_panic(42, __backtrace);
}
```

Finally, the `panic` call will compile-time generate the unique error code of the `panic` call in the format:

```
1_pppppppp_00000000000_00000000000_00000000000_00000000000_00000000000
```

and bitwise OR it with the received `__backtrace`, that previously gets its leading part set to zeros:

```sway
fn this_function_might_panic(x: u64, __backtrace: u64) {
    if x > 100 {
        let __backtrace = 0b_0_00000000_11111111111_11111111111_11111111111_11111111111_11111111111 & __backtrace;
        let revert_code = 0b_1_pppppppp_00000000000_00000000000_00000000000_00000000000_00000000000 | __backtrace;
        panic "Error message."; // Reverts with the calculated `revert_code`.
    }

    // ...
}
```

The overall runtime cost is minimal:
- one [SLLI](https://docs.fuel.network/docs/specs/fuel-vm/instruction-set/#slli-shift-left-logical-immediate) and one [ANDI](https://docs.fuel.network/docs/specs/fuel-vm/instruction-set/#andi-and-immediate) instruction before every traceable _panicking call_.
- one [AND](https://docs.fuel.network/docs/specs/fuel-vm/instruction-set/#and-and) and one [OR](https://docs.fuel.network/docs/specs/fuel-vm/instruction-set/#or-or) instruction before every `panic` call.
- the cost of passing an additional `u64` argument to _panicking functions_.

# Drawbacks

[drawbacks]: #drawbacks

The only drawback I see is bloating the ABI JSON with additional `panickingCalls` entries. Similar issue we had with the `errorCodes`, except that for `panickingCalls` we can expect, if we adopt the model discussed above, up to five times more entries then in the `errorCodes`.

As a counterargument, ABI Backtracing can be used in `debug` builds to enhance development experience, and completely turned off with `backtrace = none` build option in the `release` build, if the number of entries in the `panickingCalls` is a concern.

Other than that, I don't see any drawbacks. The proposal is a logical extension of ABI Errors. It fits fully to the existing language features and requires no new ones. It causes a minimal runtime overhead that can also be fully opted-out.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

The full-blown backtracking similar to those in non-blockchain languages and environments [was discussed in the original ABI errors RFC](https://github.com/FuelLabs/sway-rfcs/pull/43#discussion_r1858254347). It would cause a too high runtime cost if we want to use it in `release` builds.

Initially, an alternative design was consider, that was limited only for the use-case of guard functions like `require` or `only_owner`. That design had a clear disadvantage of being a compiler support for a special case. Moreover, it was even hard to find a common term for guards or invariant checks on one side, and methods like `Option::unwrap` on the other side.

When it comes to building the backtrace, and potentially not limiting it to five calls, alternatives like logging were considered. They were abandoned because of numerous reasons like:
- too high runtime cost,
- too high number of unnecessary log receipts,
- difficulty to map logs to a particular `panic`.
- not supported in predicates.

If we don't implement ABI Backtracing, we are staying at the current support for error handling, as described in [ABI Errors](./0014-abi-errors.md). This will result in suboptimal experience in case of functions like `require` or `Option::unwrap`. Moreover, it will make development of reusable libraries more difficult in respect to internal usages of such functions. E.g., instead of using `only_owner` internally, as it is now, modules like `sway_libs::ownership` will have to duplicate checks and panicking into each individual function, in order to ensure that the panic will occur in those functions (since `only_owner` will, same like `Option::unwrap`, not be useful as panic location).

# Prior art

[prior-art]: #prior-art

Similar to `panic` and ABI Errors, ABI Backtracing is motivated by ideal of providing an experience similar to backtracking/callstack in non-blockchain environments, yet without causing on-chain costs, or at least not an unacceptable on-chain cost that cannot be opted-out if necessary.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

1. Is having a possibility to remove a function from a callstack via `#[trace(never)]` actually only potentially confusing? The symmetry with `#[inline]`, on the other hand feels like a right thing. Also, having only `#[trace(always)]` feels incomplete.
1. Is having four options for the `backtrace` build option too fine grained? Can we go only with three, where `all` would respect `#[trace(never)]`?

# Future possibilities

[future-possibilities]: #future-possibilities
