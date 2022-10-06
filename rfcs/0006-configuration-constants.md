- Feature Name: (Configuration Time Constants, `config_time_constants`)
- Start Date: (fill me in with today's date, 2022-10-01)
- RFC PR: [FuelLabs/sway-rfcs#0006](https://github.com/FuelLabs/sway-rfcs/pull/19)
- Sway Issue: [FueLabs/sway#1498](https://github.com/FuelLabs/sway/issues/1498)

# Summary

[summary]: #summary

Configuration time constants can be conceptualized as traditional environment variables. Some bytecode has been compiled by the Sway compiler, and the SDK would like to configure some behavior of that bytecode with additional inputs that won't trigger a recompile.

There is a similar feature that was implemented [here](https://github.com/FuelLabs/sway/pull/2549), but that was a mistaken interpretation of the requirements. In #2549, a recompile still occurs and the new values are injected via `Forc.toml`, when we actually want these values to be injectable by the SDK.

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

TODO:

complexity of debugging
an additional post-compilation stage
further dependence on the encoder/decoder
further couples the SDK 

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives
TODO
- Why is this design the best in the space of possible designs?
- What other designs have been considered and what is the rationale for not choosing them?
- What is the impact of not doing this?

# Prior art

[prior-art]: #prior-art

TODO
immutables
env vars

# Unresolved questions

[unresolved-questions]: #unresolved-questions
TODO
- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

# Future possibilities

[future-possibilities]: #future-possibilities

TODO
advanced const eval within sdk
