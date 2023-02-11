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

Calling `as_storage_ref` is only valid for a storage accesses. A storage access looks like `storage.a.b.c...`. For example:

```rust
struct MyStruct {
    x: u64,
    y: b256,
}

storage {
    s: MyStruct, 
}

fn foo() {
    let x_ref: StorageRef<u64> = storage.s.x.as_storage_ref();
    let y_ref: StorageRef<b56> = storage.s.y.as_storage_ref();
    let s_ref: StorageRef<MyStruct> = storage.s.as_storage_ref();
}
```

In order to use a storage reference, one can call `store` and `get` as follows:
```rust
let x_ref: StorageRef<u64> = storage.s.x.as_storage_ref();
x_ref.store(42); // equivalent to `storage.x = 42`
let x = x_ref.get(); // equivalent to `let x = storage.s.x`

let y_ref: StorageRef<u64> = storage.s.y.as_storage_ref();
y_ref.store(ZERO_B256); // equivalent to `storage.y = ZERO_B256`
let y = y_ref.get(); // equivalent to `let y = storage.s.y`

let s_ref: StorageRef<MyStruct> = storage.s.as_storage_ref();
s_ref.store(MyStruct { x: 42, y: ZERO_B256 } ); // equivalent to `storage.s = MyStruct { x: 42, y: ZERO_B256 }`
let s = s_ref.get(); // equivalent to `let s = storage.s`
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

One way of implementing `as_storage_ref` is via the `__get_storage_key` intrinsic:

```rust
impl AsStorageRef<T> for T {
    #[inline(always)]
    fn as_storage_ref() -> StorageRef<T> {
        StorageRef {
            key: __get_storage_key()
        }
    }
}
```

Currently, the intrinsic just returns the storage key corresponding to the top level storage variable. It should be extended to return the storage key of an arbitrary storage accesses `storage.a.b.c...`.

## Implementing `StorageMap` using `StorageRef`.

The current implementation of `insert` and `get` for `StorageMap` rely on the intrinsic `__get_storage_key` directly. Instead, the implementation should use `StorageRef` directly, potentially as follows:

```rust
/// A persistent key-value pair mapping struct.
pub struct StorageMap<K, V> {}

impl<K, V> StorageMap<K, V> {
    #[storage(write)]
    pub fn insert(self: StorageRef<Self>, key: K, value: V) {
        let key = sha256((key, self.key));
        store::<V>(key, value);
    }

    #[storage(read)]
    pub fn get(self: StorageRef<Self>, key: K) -> Option<V> {
        let key = sha256((key, self.key));
        get::<V>(key)
    }

    #[storage(write)]
    pub fn remove(self: StorageRef<Self>, key: K) -> bool {
        let key = sha256((key, self.key));
        clear::<V>(key)
    }
}
```

This should still allow writing the following:

```rust
storage {
    my_map: StorageMap<u64, u64> = StorageMap {}
}

my_map.insert(0, 0);
let x = my_map.get(0);
my_map.as_storage_ref().remove(0);
```

If the compiler does not allow arbitrary `self` types at the moment, this should be changed to allow at least `StorageRef`. This is currently allowed in Rust for specific types such as `Rc` and `Arc` so it might make sense for Sway to allow only `StorageRef` for now.

Note that the methods of `StorageMap` should be callable using directly as in `storage.my_map.insert(..)` or by calling `as_storage_ref()` first as in `storage.my_map.as_storage_ref().insert(..)`. This may require a coercion between `T` and `StorageRef<T>`.

A similar approach for `StorageVec` can be followed.

## `StorageMap` and `StorageVec` in structs.

Writing the code below will be automatically possible after implementation all of the above:

```rust
MyStruct {
    map1: StorageMap<u64, u64>,
    map2: StorageMap<u64, u64>,
}

storage {
    s: Mystruct = MyStruct {
        map1: StorageMap { },
        map2: StorageMap { },
    }
}

storage.s.map1.insert(0, 0);
let x = storage.s.map2.get(0);
```

It will also be possible to pass a `StorageMap` to a function by passing a `StorageRef` to it as follows:

```rust
storage {
    my_map: StorageMap<u64, u64> = StorageMap {}
}

fn foo(map: StorageRef<StorageMap<u64, u64>>) {
    map.insert(0, 0);
}
```

> **Note**: **none of the changes proposed in this RFC are breaking. Existing user code is expected to contiue working as expected**

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
