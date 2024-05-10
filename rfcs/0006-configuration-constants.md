- Feature Name: `config_time_constants`
- Start Date: 2022-10-01
- RFC PR: [FuelLabs/sway-rfcs#0006](https://github.com/FuelLabs/sway-rfcs/pull/19)
- Sway Issue: [FueLabs/sway#1498](https://github.com/FuelLabs/sway/issues/1498)

# Summary

[summary]: #summary

Configuration time constants can be conceptualized as traditional environment variables. Some bytecode has been compiled by the Sway compiler, and the SDK would like to configure some behavior of that bytecode with additional inputs that won't trigger a recompile.

There is a similar feature that was implemented [here][pr_2549], but that was a mistaken interpretation of the requirements. In [#2549][pr_2549], a recompile still occurs and the new values are injected via `Forc.toml`, when we actually want these values to be injectable by the SDK.

[pr_2549]: https://github.com/FuelLabs/sway/pull/2549

# Motivation

[motivation]: #motivation

The primary and only motivation that requires this feature is contract factories. To construct a set of trusted contracts from some template, we need to have a mapping of which parts of the bytecode are just configuration variables and which parts are application logic. By comparing the version with zeroed-out constants we can assert that two contracts are the same, modulo their configuration time constants.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

When a Sway program is compiled, a set of artifacts are produced. Included in these artifacts are a [JSON ABI descriptor](https://fuellabs.github.io/fuel-specs/master/protocol/abi/json_abi_format.html#json-abi-spec) containing a configuration-time-constant descriptor, and the actual bytecode. The object we are discussing here is the configuration-time-constant descriptor, which describes the specific offset within the bytecode, in terms of bytes, to the data section entry for a particular configuration variable.

The configuration variables for a program are declared in a `configurable` block similarly to `storage` variables. Each configurable variable requires a type annotation as well as an initializer. The value of each configurable variable can be overriden at configuration time by the SDK, `forc`, or some other consumer of the configuration-time-constant descriptor. As an example:

```rust
// main.sw
script;

configurable {
    CONTRACT_ADDRESS: b256 = 0x0000000000000000000000000000000000000000000000000000000000000000,
    PRICE_RATIO: u64 = 0,
}

fn main() -> (u64, b256) { 
    (PRICE_RATIO, CONTRACT_ADDRESS)
}
```
```json
// project-abi.json
{
  ...
  "configurables": [
    {
      "configurableType": {
        "name": "",
        "type": 3,
        "typeArguments": null
      },
      "name": "CONTRACT_ADDRESS",
      "offset": 3260
    },
    ...
  ],
  ...
```

As `configurable` values will affect a contract's ID, `forc` users must be able to specify these values for each of their contract dependencies. To enable this, `forc` will allow users to specify a `config/<contract-dependency-name>.sw` file for each contract dependency that contains configurable values. This Sway file must export the required constants as specified by the contract dependency's `configurable` block. These files will be compiled independently for each contract dependency, and the resulting `configurable` bytecode section for each dependency will be used to replace its default `configurable` bytecode section.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

The `type` field of the JSON file should describe the type of the configurable in the same manner as types are described in the JSON ABI file.

A single `configurable` block is allowed in a program and no two configurable variables in a program should have the same name to prevent collisions.

The range from the offset to the offset plus the size of the type will represent bytes within the bytecode that will be overwritten by the SDK (or `forc`), which will write values according to the ABI encoder's memory layout, which is consistent with Sway's memory layout.

The change is not breaking as it is entirely new functionality.

Configuration time constants may not be defined in any library code and must be defined at the top level. Should a library need to reference a configurable value, it should utilize design patterns such as the [builder pattern](https://en.wikipedia.org/wiki/Builder_pattern) to ingest the constants from the top level.

## Failure to provide constants

If the constants are not provided, the SDK and/or `forc` should throw an error. Both tools have knowledge of the required constants due to the descriptor file, so they may check for the constants' presence and report a descriptive error if any are missing.

## Interactions with optimization passes

Configuration time constants are not allowed to be optimized away or constant folded or really touched in any way (for example, a config struct cannot be broken into into its individual elements). They always need an actual spot in the bytecode. So, the optimizor has take that into account. This can be accomplished with a "configurable" section that is entirely different from the data section and that can be left untouched by the rest of the compilation process. That being said, configurable variables that have no uses in a Sway program should be omitted from both the bytecode and the JSON ABI descriptor.

## Allowed Types

Any type that can be handled by the ABI encoder and decoder can be passed along as a config-time constant.

## Memory layout

The memory layout of configurable variables is identical to the memory layout of `const` variables which also matches the layout described in the [Argument Encoding](https://fuellabs.github.io/fuel-specs/master/protocol/abi/argument_encoding.html) section of the ABI spec.

## Specifying configuration-time constants for contract-dependencies in `Forc.toml`

With the recent introduction of [`[contract-dependencies]`](https://github.com/FuelLabs/sway/pull/3016), it would be necessary to allow `forc` projects to specify the configuration constants declared within each of their contract-dependencies. This is important in allowing the user to refer to a specific contract, and to make sure we are constructing the correct contract ID constants during build.

With configuration time constants, declaring `[contract-dependencies]` in `Forc.toml` might look something like:

```toml
[contract-dependencies]
foo = { git = "https://domain.com/owner/repo", config = "config/foo.sw" }
```

where `config/foo.sw` has a single `configurable` block with each constant value specified.

Alternatively, we could remove the need to specify the `config` file location manually by making the `config/` directory a standard location. We could require that, for each contract-dependency that has a `configurable` block, a file exists in the `config/` directory that matches the name of the dependency with `.sw` appended (e.g. `config/foo.sw`). In the case that no `config/foo.sw` file is present, we could either:

1. produce an error, or
2. fallback to using the contract dependency's default values, indicating that we are falling back with a `info!` log or similar.

# Drawbacks

[drawbacks]: #drawbacks

One major drawback is the additional cognitive complexity this adds to the compilation process. If any bug is introduced or the overwriting of the bytecode goes awry in any way, it will result in confusing and inconsistent undefined behavior. We will need to introduce sufficient checks to ensure that an end user would never encounter this situation. An example of testing this behavior would be integration tests that pass in the majority of the ABI-encodable types, fuzzed, as config time constants, and assessing behavior.

This increases our reliance on the correctness of the ABI encoder in the SDK, and any version mismatches or bugs in the encoder will result in similarly undefined and unpredictable behavior.

This change also further couples the language to the SDK, further minimizing the use case of writing Sway without the SDK. This can be alleviated by introducing mechanisms to `forc` for defining these values manually, as mentioned in the guide-level explanation.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

One alternative is to introduce an environment variables/configuration-time constants section to the transaction format. This could be cleaner, but the impact on Sway would be minimal. Sway would still output a descriptor file, introduce the `configurable` keyword syntax, etc., and the majority of this RFC would still apply. The benefit of adding this to the transaction format would be potential simplification of the process. A couple negatives would be additional churn on the client, VM, and SDK; and further coupling of specifically Sway to the FuelVM.

If we do not implement configuration-time constants, the workflow of deploying contracts and then calling them from scripts (i.e. the main use case of Sway) would still require manually updating contract addresses in the source code. Without an enshrined tool for configuring values like this, it is likely that some third party `sed`-like workaround would develop in the community to the detriment of the Fuel stack developer experience.


# Prior art

[prior-art]: #prior-art

[Immutables in Solidity](https://docs.soliditylang.org/en/v0.6.5/contracts.html) are the closest prior art, effectively performing the exact same functionality. Environment variables in traditional software development are also similar in paradigm and utility.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

This change has been discussed in depth among SDK, Sway, and client developers and there is little ambiguity. There could be further iterations on minor details like the specific syntax in the language and the format of the descriptor file.

# Future possibilities

[future-possibilities]: #future-possibilities

Someday, if possible without the SDK importing the compiler, perhaps some constant evaluation of more sophisticated expressions could be done in the SDK, although that's a minor use case. 

It is also possible that configuration time constants are added to the transaction format someday. If that happens, the compiler will not need to change dramatically but the client and SDK will have work to do.
