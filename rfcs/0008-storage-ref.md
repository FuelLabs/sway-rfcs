- Feature Name: Storage References
- Start Date: 2023-02-10)
- RFC PR: [FuelLabs/sway-rfcs#0008](https://github.com/FuelLabs/sway-rfcs/pull/023)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/3043)

# Summary

[summary]: #summary

One paragraph explanation of the feature.

# Motivation

[motivation]: #motivation

Why are we doing this? What use cases does it support? What is the expected outcome?

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

A storage reference stores a `b256` key that describes a storage slot:

```rust
pub struct StorageRef<T> {
    key: b256,
}
```

We can implement `store` and `get` as follows:

```rust
impl<T> StorageRef<T> {
    #[storage(read)]
    pub fn get(self) -> Option<T> {
        std::storage::get(self.key)
    }

    #[storage(write)]
    pub fn store(self, other: T) {
        std::storage::store(self.key, other)
    }
}
```

One can create a `StorageRef` manually (it's really just a wrapper around a `b256` key) or via a call to `as_storage_ref` from a new trait called `AsStorageRef`:

```rust
pub trait AsStorageRef<T> {
    fn as_storage_ref(self) -> StorageRef<T>;
}
```

Calling `as_storage_ref` is only valid for a storage accesses. A storage access looks like `storage.a.b.c...`. For example
```rust
struct MyStruct {
    x: u64,
    y: b256,
}

storage {
    s: MyStruct, 
}

fn foo() {
    let x_ref: StorageRef<u64> = storage.s.x.as_ref();
    let y_ref: StorageRef<b56> = storage.s.y.as_ref();
    let s_ref: StorageRef<MyStruct> = storage.s.as_ref();
}
```

In order to use a storage reference, one can call `store` and `get` as follows:
```
let x_ref: StorageRef<u64> = storage.s.x.as_ref();
x_ref.store(42); // equivalent to `storage.x = 42`
let x = x_ref.get(); // equivalent to `let x = storage.s.x`

let y_ref: StorageRef<u64> = storage.s.y.as_ref();
y_ref.store(ZERO_B256); // equivalent to `storage.y = ZERO_B256`
let y = y_ref.get(); // equivalent to `let y = storage.s.y`

let s_ref: StorageRef<MyStruct> = storage.s.as_ref();
s_ref.store(MyStruct { x: 42, y: ZERO_B256 } ); // equivalent to `storage.s = MyStruct { x: 42, y: ZERO_B256 }`
let s = s_ref.get(); // equivalent to `let s = storage.s`
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This is the technical portion of the RFC. Explain the design in sufficient detail that:

- Its interaction with other features is clear.
- It is reasonably clear how the feature would be implemented.
- Corner cases are dissected by example.
- If this change is breaking, mention the impact of it here and how the breaking change should be managed.

The section should return to the examples given in the previous section, and explain more fully how the detailed proposal makes those examples work.

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
Please also take into consideration that rust sometimes intentionally diverges from common language features.

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
