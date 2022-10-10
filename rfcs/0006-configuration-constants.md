- Feature Name: Configuration Time Constants, `config_time_constants`
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

This supports the use case of configurable values post-compile-time but pre-runtime, similar to Solidity's `immutable` concept or environment variables in traditional programming. This allows for, e.g., updating contract addresses without recompiling the bytecode.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

When a Sway program is compiled, a set of artifacts are produced. Included in these artifacts are a JSON ABI descriptor, a configuration-time-constant descriptor, and the actual bytecode. The object we are discussing here is the configuration-time-constant descriptor, which describes the specific offset within the bytecode, in terms of bytes, to the data section entry for a particular configuration variable.

The configuration variables for a program can be identified by the `configurable` keyword within the Sway language. This denotes a constant within the program that has no known value at compile time. The value will be provided at configuration time by the SDK or some other consumer of the configuration-time-constant descriptor. As an example:

```rust
// main.sw
script;

configurable CONTRACT_ADDRESS: b256;

fn main() { ... }
```
```
// configurable-constants.json

{
    "CONTRACT_ADDRESS": {
        "type": "b256",
        "offset": "12345"
    }
}
```

If you are not using the SDK, it will be possible to define these values either by passing a flag to `forc` or including them in the `Forc.toml` manifest file.


# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

The `type` field of the JSON file should describe the type of the configurable in the same manner as types are described in the JSON ABI file.

No two configurables in a program should have the same name to prevent collisions.

The range from the offset to the offset plus the size of the type will represent bytes within the bytecode that will be overwritten by the SDK, which will write values according to the ABI encoder's memory layout, which is consistent with Sway's memory layout.

The change is not breaking as it is entirely new functionality.

# Drawbacks

[drawbacks]: #drawbacks

One major drawback is the additional cognitive complexity this adds to the compilation process. If any bug is introduced or the overwriting of the bytecode goes awry in any way, it will result in confusing and inconsistent undefined behavior. We will need to introduce sufficient checks to ensure that an end user would never encounter this situation.

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
