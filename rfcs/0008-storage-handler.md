- Feature Name: Storage Keys 
- Start Date: 2023-02-10)
- RFC PR: [FuelLabs/sway-rfcs#0023](https://github.com/FuelLabs/sway-rfcs/pull/023)
- Sway Issue: [FueLabs/sway#3043](https://github.com/FuelLabs/sway/issues/3043)

# Summary

[summary]: #summary

This RFC introduces the concept of a `StorageKey` which describes a particular storage slot via its key. The RFC also reworks how storage accesses are represented in the language and how `StorageKey` can be used to build dynamic storage types, such as `StorageMap` and `StorageVec`, more robustly.

# Motivation

[motivation]: #motivation

The current approach for reading and writing storage slots/variables has multiple flaws, despite being quite ergonomic:

1. There is currently no way to reason about the location of a particular storage variable, which makes passing "references" to storage variables impossible. One workaround is manipulating and reading storage slots manually via `std::storage::store` and `std::storage::get`, but this approach is quite unsafe. Alternatively, one could declare a `trait` in a library and implement it in a contract and have its methods access storage variables. Those methods are then used in the library to access storage indirectly. This does not solve the full problem and feels more like a workaround than a real solution.
1. Dynamic storage types, such as `StorageMap` and `StorageVec`, currently require a "hacky" compiler intrinsic called `__get_storage_key` which is not very well defined and is hard to use. Introducing the concept of a `StorageKey` will helps us completely remove this intrinsic.
1. The current implementation of dynamic storage types prevents th-em from being used as struct fields or as type parameters of other storage types (e.g. `StorageVec<StorageVec<u64>>`).

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

A `StrorageKey` is a thin wrapper type, in the standard library, around a `b256` key that describes a storage slot:

```rust
pub struct StorageKey<T> {
    key: b256,
}
```

The type `T` describes the type of the data stored at `key`. Since each storage slot is 64 bytes long, some types cannot fit in a single storage slot. In that case, the data is stored across multiple consecutive storage slots starting at `key`. More on this in [Storage Slot Assignment](#storage-slot-assignment).

Reading and writing the data stored at `key` can be accomplished using the `read` and `write` methods below:

```rust
impl<T> StorageKey<T> {
    #[storage(read)]
    pub fn read(self) -> Option<T> {
        std::storage::get(self.key)
    }

    #[storage(write)]
    pub fn write(self, other: T) {
        std::storage::store(self.key, other);
    }
}
```

Notice that `read` returns an `Option` because it is possible that a particular storage slot is not valid, i.e. has not been written before, in which case `None` is returned. If the type `T` spans multiple storage slots, then the method `read` returns `None` if at least one the storage slots that `T` spans is invalid.

With the `StorageKey` type available, this RFC proposes a redefinition of the meaning of the expression `storage.<var>.<field>...` to return a `StorageKey` "pointing" to the actual data instead of returning the data itself. The RFC also proposes removing the "reassignment" statement `storage.<var>.<field>.. = ..` from the language.

Below is an example showing the behavior of `StorageKey` and the new behavior of storage access expressions:

```rust
struct MyStruct {
    x: u64,
    y: b256,
}

storage {
    s: MyStruct = MyStruct { x: 0, y: ZERO_B256 }, 
}

fn foo() {
    // Get the storage key to the struct field `x` directly and then use it to store `42` in `x`.
    let x_key: StorageKey<u64> = storage.s.x;
    x_key.write(42);
   
    // Call `write` and `read` directly on `storage.s.y`
    storage.s.y.write(ZERO_B256);
    let y:Option<b256> = storage.s.y.read();

    // Get the storage key to the struct `s` and then use it to store `MyStruct { x: 42, y: ZERO_B256 }` in `s`.
    let s_key: StorageKey<MyStruct> = storage.s;
    s_key.write(MyStruct { x: 42, y: ZERO_B256 } );

    // Read the struct `s`
    let s:Option<MyStruct> = s_key.read();
}
```

Below is how the "counter" example now looks like:

```rust
contract;

abi TestContract {
    #[storage(write)]
    fn initialize_counter(value: u64) -> u64;

    #[storage(read, write)]
    fn increment_counter(amount: u64) -> u64;
}

storage {
    counter: u64 = 0,
}

impl TestContract for Contract {
    #[storage(write)]
    fn initialize_counter(value: u64) -> u64 {
        // Previoulsy: `storage.counter = value`
        storage.counter.write(value);

        value
    }

    #[storage(read, write)]
    fn increment_counter(amount: u64) -> u64 {
        // Previously: `let incremented = storage.counter + amount`
        let incremented = storage.counter.read().unwrap_or(0) + amount;

        // Previously: `storage.counter = incremented`
        storage.counter.write(incremented);

        incremented
    }
}
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

The compiler will handle storage slots assignment for each storage variable. Each storage access expression will simply return a `StorageKey` containing the key chosen by the compiler.

## Storage Slot Assignment

Each storage variable in a `storage` block is assigned an index corresponding to its location in the list of variables:

```rust
struct MyInnerStruct {
    c: u64,
    d: b256,
}

struct MyStruct {
    a: u64,
    b: MyInnerStruct,
}

storage {
    x: u64 = 0, // Assigned index `0`
    y: b256 = ZERO_B256, // Assigned index `1`
    str: str[99], // Assigned index '2'
    s: MyStruct = MyStruct { a: 0, b: MyInnerStruct { c: 0, d: ZERO_B256 } }, // Assigned index `3`
}
```

The "index" assigned to each variable is used to generated a key as follows.

### "Small" Types

Small types are types that fit in a single storage slot. We exclude structs with multiple fields from this definition even they do fit in one slot; structs with at least one field are considered "large types" are handled in the [next section](#large-types).

Storage variables that have small types are assigned a single key that is equal to `sha256("storage_<idx>")` where `<idx>` is the index assigned to the storage variable. In the example above, the key chosen for `x` is:

```rust
sha256("storage_0") = 0xf383b0ce51358be57daa3b725fe44acdb2d880604e367199080b4379c41bb6ed
```

and the key chosen for `y` is:

```rust
sha256("storage_1") = 0xde9090cb50e71c2588c773487d1da7066d0c719849a7e58dc8b6397a25c567c0
```

### "Large" Types

Large types span multiple storage slots and are laid out sequentially in storage starting at key `sha256("storage_<idx>")` where `<idx>` is the index assigned to each storage variable. The number of storage slots required can be computed as `(__size_of::<T>() + 31) >> 5` (ceiling of the size of the data type divided by `32`). Structs are the only exception to this rule because the fields of a struct are each stored in their own storage slot regardless of their size. This makes accessing or writing a particular struct field much more efficient.

> **Note**
> Struct variables are laid out in the same way today.

For example, the storage variable `str` above is a string containing `99` characters and its size is `99` bytes which span 2 storage slots. It is also assigned index `2`. Therefore, `str` spans slots with keys `sha256("storage_2")` and `sha256("storage_2") + 1`.

Variable `s` on the other hand, is a nested struct and is assigned index `3`. Therefore, each of its fields (and subfields) is assigned a separate key starting with `sha256("storage_3")`:

- `s.a` is assigned `sha256("storage_3")`.
- `s.b.c` is assigned `sha256("storage_3") + 1`.
- `s.b.d` is assigned `sha256("storage_3") + 2`.

### Empty Types

There are two possible empty types: structs with no fields and enums with no variants. Empty structs are useful for implementing dynamic storage types such as `StorageMap` and `StorageVec`. Storage variables that have empty types should not consume any storage slots.

### Behavior of `StorageKey`

When a storage variable is accessed, a `StorageKey` is returned of the appropriate type. The `StorageKey` object contains the `b256` key required to access the underlying data:

```rust
assert(storage.x.key == sha256("storage_0"));
assert(storage.y.key == sha256("storage_1"));
assert(storage.str.key == sha256("storage_2"));
assert(storage.s.a.key == sha256("storage_3"));
assert(storage.s.b.c.key == sha256("storage_3") + 1);
assert(storage.s.b.d.key == sha256("storage_3") + 2);

assert(storage.s.key == sha256("storage_3")); // Same as `storage.s.a.key`
assert(storage.s.b.key == sha256("storage_3") + 1); // Same as `storage.s.b.c.key`
```

> **Note**: 
> The above is a pseudo-code and is not meant to compile for various reasons.

## Implementation Detail

The typed expression `TyStorageAccess` in the compiler should now return `std::storage::StorageKey` which should store the key chosen by the compiler according to the rules described in [Storage Slots Assignment](#storage-slot-assignment). The rest of the flow is be handled automatically after removing all the unnecessary logic in the compiler for reading and writing storage slots.

## Implementing Dynamic Storage Types using `StorageKey`.

Dynamic storage types such `StorageMap` and `StorageVec` currently use the intrinsic `__get_storage_key` which is not very well defined and has a fragile implementation. With `StorageKey` available and returned directly from a storage access expression (as in `storage.my_map`), we can re-implement methods like `StorageMap::insert`, `StorageMap::get`, and `StorageMap::remove` in a safer and cleaner way as follows:

```rust
/// A persistent key-value pair mapping struct.
pub struct StorageMap<K, V> {}

impl<K, V> StorageMap<K, V> {
    #[storage(write)]
    pub fn insert(self: StorageKey<Self>, key: K, value: V) {
        let key = sha256((key, self.key));
        store::<V>(key, value);
    }

    #[storage(read)]
    pub fn get(self: StorageKey<Self>, key: K) -> Option<V> {
        let key = sha256((key, self.key));
        get::<V>(key)
    }

    #[storage(write)]
    pub fn remove(self: StorageKey<Self>, key: K) -> bool {
        let key = sha256((key, self.key));
        clear::<V>(key)
    }
}
```

Note that this requires that the compiler allows `self` to be type-ascribed. This is not possible today but should be easy to do. We should make sure to restrict the types allowed to only `Self` and `StorageKey<Self>`. Rust has a small list of types that `self` is allowed to have such as `Rc` and `Arc` so this feature is not unheard of.

With the above new implementation, we should be able to continue to use `StorageMap` as before:

```rust
storage {
    my_map: StorageMap<u64, u64> = StorageMap {}
}

storage.my_map.insert(0, 0);
let x = storage.my_map.get(0);
storage.my_map.remove(0);
```

A similar approach can be followed to re-implement `StorageVec` and other dynamic storage types.

## Dynamic Storage Types in Structs

The code below will now be valid after implementing all of the above:

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

It will also be possible to pass a `StorageMap` to a function by passing a `StorageKey` to it as follows:

```rust
storage {
    my_map: StorageMap<u64, u64> = StorageMap {}
}

fn foo(map: StorageKey<StorageMap<u64, u64>>) {
    map.insert(0, 0);
}

fn bar() {
    foo(storage.my_map); 
}
```

Sway code using storage maps and vectors will not look any different than before after this RFC is implemented.

# Drawbacks

[drawbacks]: #drawbacks

There are two main drawbacks for the approach proposed above:

1. Reading and writing a storage variable is now a bit more complicated and less ergonomic than before because we now have to call `read` and `write` manually. We also have to handle the `Option` returned by `read` which can be quite verbose. We should consider making this more ergonomic by introducing a simpler syntax that de-sugars to the API calls above. For example, we could de-sugar something like `storage.x = 42` to `storage.x.write(42)`. We could also consider making `read` return the data directly instead of an `Option` if we completely disallow storage slots corresponding to storage variables from being invalidated (For example, remove `std::storage::clear`).

2. The second drawback is related to the fact that structs take up more storage slots than they actually need. This behavior is **not** new. There is a tradeoff here to be considered. If we make structs tightly packed, then manipulating a single field becomes more expensive (potential read-modify-write patterns or fields "spilling" over to the next slot), but the number of storage slots required may become lower. We might want to consider a `#[packed]` attribute in the future to let the user decide on one way v.s. the other. Another thing to consider with tightly-packed structs is that the type `StorageKey` would then also require an additional field that points to a particular location _inside_ a given slot (i.e. which byte to start reading from or writing to).

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

One alternative is to continue with the current use model which has many flaws so that's not ideal. Another alternative is to introduce an `AsStorageKey` trait that allows calling `storage.x.get_storage_key()` to get the storage key manually, but that approach has its limitations when implementing `StorageMap` and `StorageVec` and requires defining the behavior of `get_storage_key` when called on a regular stack variable.

One more alternative is to completely remove the concept of a "storage variable" and switch over to thinking about storage like file I/O or databases. However, I think the approach described in this RFC provides a good middle ground where methods like `write` and `read` somewhat behave like I/O methods but also keeps the abstraction of "storage variables" to help user write readable code.

# Prior art

[prior-art]: #prior-art

Solidity's approach to storage is completely different from the above and has its own problems, as storage variable are hard to identify and storage accesses are not explicit enough. Sway's current approach is also flawed as explained in the [Motivation](#motivation) section.

In Rust, the closest thing to storage accesses is file I/O where a handler is used to read and write to a file similarly to `write` and `read` above.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

- How do we make storage accesses, particularly reads, more ergonomic?
- Is not having structs tightly packed acceptable? Is that something that we want in the future, potentially via a `#[packed]` attribute that also reorders the fields of the struct for optimal layout?
- How do we implement nested dynamic storage types such as `StorageVec<StorageVec<u64>>`?
- How do we obtain a `StorageKey` for data stored in a dynamic storage collection such as `StorageMap` or `StorageVec`? Is that even needed/required?

# Future possibilities

[future-possibilities]: #future-possibilities

- Tightly packed storage structs.
- Nested dynamic storage types such as `StorgaeVec<StorageVec<u64>>`.
