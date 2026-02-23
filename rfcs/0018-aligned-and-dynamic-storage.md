- Feature Name: `aligned_and_dynamic_storage`
- Start Date: 2026-02-18
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

Current storage access, via `storage_api` and `StorageKey`, always assumes that a value written in a slot might share that slot with other values. For `storage` fields and storage types like `StorageMap` this is never the case. The only `std` storage type potentially "packing" different values in a single field is `StorageVec`.

Although the below assumption does not hold for the most of storage access, it results in **an unnecessary slot reads before write in most of the storage access cases**.

This PR introduces a concept of an _aligned stored value_. _Aligned stored value_ is a one that:
- always starts at the beginning of a slot,
- and never shares its slot with another value.

This PR proposes explicit API for accessing _aligned stored values_: `read_aligned`, and `write_aligned` functions, and `AlignedStorageKey` struct. Those take advantage of the above fact **and remove the need for reads before writes**. 

The PR also proposes the optimal way of integrating the [dynamic storage opcodes](https://github.com/FuelLabs/fuel-specs/pull/640), respecting the **low cost of dynamic writes** and **high base cost of dynamic reads**.

# Motivation

[motivation]: #motivation

The costs of storage instructions are given in [Costs of storage instructions](#costs-of-storage-instructions).

The typical sizes of stored types are given in [Typical sizes of stored types](#typical-sizes-of-stored-types).

[Dynamic storage](https://github.com/FuelLabs/fuel-specs/issues/517) brings [additional storage opcodes](https://github.com/FuelLabs/fuel-specs/pull/640) that can be used to lower storage access cost. However, because of the high base read cost, we need to combine them with the existing opcodes to gain the maximum benefits. As the typical sizes of types show, large values on which dynamic storage becomes directly useful are rare.

`StorageMap` values and `storage` fields **never share slots with other values**. Also, they **always start at the beginning of a slot**. We say that those values are _aligned to slot boundaries_. Out of standard storage types, only `StorageVec` packs different values to the same slot and can position values at an arbitrary index within a slot.

If we utilize the fact that most of the values written to storage are _aligned stored values_ and support that on the API/type level, **we can remove unnecessary reads before writes, which are currently the major cause of high write costs**.

Moreover, if we optimally combine the non-dynamic and dynamic opcodes we can achieve significantly lower access cost of storage writes.

By applying the approach described in the [Guide-level explanation](#guide-level-explanation) we can achieve the below gas savings on storage access. On top of the gas savings, we would have ~10 gas units saved on additional computation currently necessary, e.g., the `slot_calculator` costs. 

| Type size (bytes) | Current reading | New reading | Current writing | New writing |
| ----------------- | --------------- | ----------- | --------------- | ----------- |
| [1..8]            | 520             | 503 (`srw`) | 1027            | 10 (`swrd`) |
| (8..32)           | 520             | 520         | 1027            | 10 (`swrd`) |
| =32               | 520             | 520         | 507             | 10 (`swrd`) |
| (32..64]          | 1040            | 1040        | 1547            | 10 (`swrd`) |
| =64               | 1040            | 1040        | 1014            | 10 (`swrd`) |

TODO-IG! Discuss `StorageVec` optimizations.

TODO-IG! Discuss optimizations for larger types and direct usage of dynamic reads.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

We introduce two new `storage_api` functions:
- `fn read_aligned<T>(slot: b256) -> Option<T>`
- `fn write_aligned<T>(slot: b256, value: T)`

`read_aligned` will have a simplified computation effort compared to `read` and a slight advantage in reading types of size <=8 bytes.
`write_aligned` will have a simplified computation effort, utilize `swrd` and the alignment guarantee to achieve the gas savings presented above.

Additionally, `write` will internally use `swrd` instead of `srwq` to achieve better performance in writing non-aligned values.

We also introduce `AlignedStorageKey` struct. `AlignedStorageKey` offers the same API as the `StorageKey`, but guarantees access to aligned values and uses `read_aligned` and `write_aligned` under the hood.

Compiler will generate `AlignedStorageKey`s for `storage` field access.

`StorageMap` will use `AlignedStorageKey` for accessing its values.

TODO-IG!: If we don't optimize `StorageVec` it can simply continue to use `StorageKey`.

TODO-IG!: Partial read and writes, e.g., `storage.some_struct.some_field.read()`.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This is the technical portion of the RFC. Explain the design in sufficient detail that:

- Its interaction with other features is clear.
- It is reasonably clear how the feature would be implemented.
- Corner cases are dissected by example.
- If this change is breaking, mention the impact of it here and how the breaking change should be managed.

The section should return to the examples given in the previous section, and explain more fully how the detailed proposal makes those examples work.

### Costs of storage instructions

Cost of non-dynamic storage instructions take from the [chain configuration](https://github.com/FuelLabs/chain-configuration/blob/master/upgradelog/ignition/consensus_parameters/7.json).

```
"srw": 503,
"sww": 510,
"scwq": {
  "HeavyOperation": {
    "base": 507,
    "gas_per_unit": 515
  }
},
"srwq": {
  "HeavyOperation": {
    "base": 520,
    "gas_per_unit": 522
  }
},
"swwq": {
  "HeavyOperation": {
    "base": 507,
    "gas_per_unit": 525
  }
},
```

Cost of dynamic storage instructions take from the [Dynamic storage support PR](https://github.com/FuelLabs/fuel-vm/pull/982/changes#diff-d795ba779718a009d63d6bf0edbedd9bd9bc1c17e63036c69ebb2313d8f808f5R190).

```
sclr: DependentCost::HeavyOperation {
    base: 7,
    gas_per_unit: 20,
},
srdd: DependentCost::LightOperation {
    base: 2513,
    units_per_gas: 39,
},
swrd: DependentCost::LightOperation {
    base: 10,
    units_per_gas: 406,
},
supd: DependentCost::LightOperation {
    base: 2513,
    units_per_gas: 35,
},
spld: DependentCost::LightOperation {
    base: 3427,
    units_per_gas: 2,
},
spcp: DependentCost::LightOperation {
    base: 1,
    units_per_gas: 3333,
},
```

### Typical sizes of stored types

The below graphs show distribution of sizes of types used as `storage` fields, or stored in `StorageMap`s or `StorageVec`s. TODO-IG!: Write sources and conclusions.

![Standalone `storage` field](../files/0018-aligned-and-dynamic-storage/standalone-storage-field.jpg)

![`StorageMap`](../files/0018-aligned-and-dynamic-storage/stroage-map.png)

![`StorageVec`](../files/0018-aligned-and-dynamic-storage/storage-vec.jpg)


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

Discuss prior art, both the good and the bad, in relation to this proposal.
A few examples of what this can include are:

- For language, library, cargo, tools, and compiler proposals: Does this feature exist in other programming languages and what experience have their community had?
- For community proposals: Is this done by some other community and what were their experiences with it?
- For other teams: What lessons can we learn from what other communities have done here?
- Papers: Are there any published papers or great posts that discuss this? If you have some relevant papers to refer to, this can serve as a more detailed theoretical background.

This section is intended to encourage you as an author to think about the lessons from other languages, provide readers of your RFC with a fuller picture.
If there is no prior art, that is fine - your ideas are interesting to us whether they are brand new or if it is an adaptation from other languages.

Note that while precedent set by other languages is some motivation, it does not on its own motivate an RFC.
Please also take into consideration that sway sometimes intentionally diverges from common language features.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

# Future possibilities

[future-possibilities]: #future-possibilities

Think about what the natural extension and evolution of your proposal would
be and how it would affect the language and project as a whole in a holistic
way. Try to use this section as a tool to more fully consider all possible
interactions with the project and language in your proposal.
Also consider how this all fits into the roadmap for the project
and of the relevant sub-team.

This is also a good place to "dump ideas", if they are out of scope for the
RFC you are writing but otherwise related.

If you have tried and cannot think of any future possibilities,
you may simply state that you cannot think of anything.

Note that having something written down in the future-possibilities section
is not a reason to accept the current or a future RFC; such notes should be
in the section on motivation or rationale in this or subsequent RFCs.
The section merely provides additional information.
