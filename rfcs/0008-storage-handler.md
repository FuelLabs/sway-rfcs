- Feature Name: `storage_keys` 
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
1. Dynamic storage types, such as `StorageMap` and `StorageVec`, currently require a "hacky" compiler intrinsic called `__get_storage_key` which is not very well defined and is hard to use. Its implementation also requires that all methods using it are inlined, which is not something that can be guaranteed, even if `#[inline(always)]` is used. Introducing the concept of a `StorageKey` will help us completely remove this intrinsic.
1. The current implementation of dynamic storage types prevents them from being used as struct fields or as type parameters of other storage types (e.g. `StorageVec<StorageVec<u64>>`).

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

A `StrorageKey` is a thin wrapper type, in the standard library, around a `b256` key that describes a storage slot and a `u64` offset, in 64 bit words, from the beginning of that slot.

```rust
pub struct StorageKey<T> {
    key: b256,
    offset: u64,
}
```

The type `T` describes the type of the data that the `StorageKey` points to. Since each storage slot is 64 bytes long, some types cannot fit in a single storage slot, particuarly if `offset` is non-zero. In that case, the data is stored across multiple consecutive storage slots starting at `key + offset`. More on this in [Storage Slot Assignment](#storage-slot-assignment).

> **Note** 
> We use the `+` sign in `key + offset` throughout this document to refer to the location in storage that `StorageKey { key, offset}` points to. For example, if `key = 0x0...00` and `offset = 10`, then `key + offset` points to the second word in storage slot `0x0...02` because `offset` is in words and each storage slot contains 4 words.

Reading and writing the data stored at `key + offset` can be accomplished using the `read`, `try_read`, and `write` methods below:

```rust
impl<T> StorageKey<T> {
    #[storage(read)]
    pub fn read(self) -> T {
        std::storage::read::<T>(self.key, self.offset).unwrap()
    }

    #[storage(read)]
    pub fn try_read(self) -> Option<T> {
        std::storage::read::<T>(self.key, self.offset)
    }

    #[storage(write)]
    pub fn write(self, other: T) {
        std::storage::write(self.key, self.offset, value);
    }
}
```

This assumes the existence of functions `std::storage::read` and `std::storage::write` that read and write the appropriate storage slots given a key and an offset and handle all the appropriate storage slot assignment and data conversion.

Notice that `StorageKey::try_read` returns an `Option` because it is possible that a particular storage slot is not valid, i.e. has not been written before, in which case `None` is returned. If the type `T` spans multiple storage slots, then the method `StorageKey::try_read` returns `None` if at least one the storage slots that `T` spans is invalid. The method `StorageKey::read` is similar to `StorageKey::read` except that it unwraps the returned `Option` internally.

With the `StorageKey` type available, this RFC proposes a redefinition of the meaning of the expression `storage.<var>.<field>...` to return a `StorageKey` "pointing" to the actual data instead of returning the data itself. The RFC also proposes removing the "reassignment" statement `storage.<var>.<field>.. = ..` from the language, at least temporarily.

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
   
    // Call `write` and `try_read` directly on `storage.s.y`
    storage.s.y.write(ZERO_B256);
    let y: Option<b256> = storage.s.y.try_read();

    // Get the storage key to the struct `s` and then use it to store `MyStruct { x: 42, y: ZERO_B256 }` in `s`.
    let s_key: StorageKey<MyStruct> = storage.s;
    s_key.write(MyStruct { x: 42, y: ZERO_B256 } );

    // Read the struct `s`
    let s: MyStruct = s_key.read();
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
        let incremented = storage.counter.read() + amount;

        // Previously: `storage.counter = incremented`
        storage.counter.write(incremented);

        incremented
    }
}
```

> **Note** 
> Because storage variables defined in a `storage` block have to be initialized, it is generally often to call `StorageKey::read` to get back the data directly instead of having to handle the `Option` returned from `try_read`. This, of course, becomes unsafe if `asm` blocks that clear storage slots are used. Note that the standard library currently has a public method `clear` that we also propose that it should be made private to avoid potential foot guns.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

The compiler will handle storage slots assignment for each storage variable. Each storage access expression will simply return a `StorageKey` containing the key and the offset chosen by the compiler.

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

Small types are types that fit in a single storage slot. Storage variables that have small types are packed and assigned a single key that is equal to `sha256("storage_<idx>")` where `<idx>` is the index assigned to the storage variable. In the example above, the key chosen for `x` is:

```rust
sha256("storage_0") = 0xf383b0ce51358be57daa3b725fe44acdb2d880604e367199080b4379c41bb6ed
```

and the key chosen for `y` is:

```rust
sha256("storage_1") = 0xde9090cb50e71c2588c773487d1da7066d0c719849a7e58dc8b6397a25c567c0
```

### "Large" Types

Large types span multiple storage slots and are packed and laid out sequentially in storage starting at key `sha256("storage_<idx>")` where `<idx>` is the index assigned to each storage variable. The number of storage slots required can be computed as `(__size_of::<T>() + 31) >> 5` (ceiling of the size of the data type divided by `32`). 

For example, the storage variable `str` above is a string containing `99` characters and its size is `99` bytes which span 2 storage slots. It is also assigned index `2`. Therefore, `str` spans slots with keys `sha256("storage_2")` and `sha256("storage_2") + 1`.

Variable `s` is a nested struct and is assigned index `3`. Therefore, its fields and subfields are stored as follows:

- `s.a` is stored as the first word in storage slot with key `sha256("storage_3")`.
- `s.b.c` is stored as the second word in storage slot with key `sha256("storage_3")` (same slot as `s.a`).
- `s.b.d` is the third and fourth words in storage slot with key `sha256("storage_3")` as well as the first and second words in storage slot with key `sha256("storage_3") + 1`.

### Empty Types

There are two possible empty types: structs with no fields and enums with no variants. Empty structs are useful for implementing dynamic storage types such as `StorageMap` and `StorageVec`. Storage variables that have empty types do not consume any storage slots.

### Behavior of `StorageKey`

When a storage variable is accessed, a `StorageKey` is returned of the appropriate type. The `StorageKey` object contains the `b256` key and the `u64` offset required to access the underlying data:

- `storage.x` returns `StorageKey<b256> { key: sha256("storage_0"), offset: 0 }`.
- `storage.y` returns `StorageKey<b256> { key: sha256("storage_1"), offset: 0 }`.
- `storage.str` returns `StorageKey<str[99]> { key: sha256("storage_2"), offset: 0 }`.
- `storage.s` returns `StorageKey<MyStruct> { key: sha256("storage_3"), offset: 0 }`.
- `storage.s.a` returns `StorageKey<u64> { key: sha256("storage_3"), offset: 0 }`.
- `storage.s.b` returns `StorageKey<MyInnerStruct> { key: sha256("storage_3"), offset: 1 }`.
- `storage.s.b.c` returns `StorageKey<u64> { key: sha256("storage_3"), offset: 1 }`.
- `storage.s.b.d` returns `StorageKey<b256> { key: sha256("storage_3"), offset: 2 }`.

## Implementation Detail

The typed expression `TyStorageAccess` in the compiler should now return `std::storage::StorageKey` which should store the key and offset chosen by the compiler according to the rules described in [Storage Slots Assignment](#storage-slot-assignment). The rest of the flow will be handled automatically after removing all the unnecessary logic in the compiler for reading and writing storage slots.

## Implementing Dynamic Storage Types using `StorageKey`.

Dynamic storage types such `StorageMap` and `StorageVec` currently use the intrinsic `__get_storage_key` which is not very well defined and has a fragile implementation. With `StorageKey` available and returned directly from a storage access expression (as in `storage.my_map`), we can re-implement methods like `StorageMap::insert`, `StorageMap::get`, and `StorageMap::remove` in a safer and cleaner way as follows:

```rust
/// A persistent key-value pair mapping struct.
pub struct StorageMap<K, V> {}

impl<K, V> StorageKey<StorageMap<K, V>> {
    #[storage(read, write)]
    pub fn insert(self, key: K, value: V) {
        let key = sha256((key, self.key));
        write::<V>(key, 0, value);
    }

    #[storage(read)]
    pub fn get(self, key: K) -> StorageKey<V> {
        StorageKey {
            key: sha256((key, self.key)),
            offset: 0,
        }
    }

    #[storage(write)]
    pub fn remove(self, key: K) -> bool {
        let key = sha256((key, self.key));
        clear::<V>(key)
    }
}
```

With the above new implementation, we should be able to continue to use `StorageMap` as before:

```rust
storage {
    my_map: StorageMap<u64, u64> = StorageMap {}
}

storage.my_map.insert(0, 0);
let x = storage.my_map.get(0).read();
storage.my_map.remove(0);
```

> **Note**
> The method `get` now returns a `StorageKey` instead of the actual data because this simplifies nesting storage maps and other dynamic storage types. 

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
let x = storage.s.map2.get(0).read();
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

## Nested Dynamic Storage Types

Nesting dynamic storage type is now trivial given what we have so far:

```rust
storage {
    nested_map_1: StorageMap<u64, StorageMap<u64, StorageMap<u64, u64>>> = StorageMap {},
}

storage.nested_map_1.get(0).get(0).insert(0, 1);
storage.nested_map_1.get(1).get(1).insert(1, 8);
assert(storage.nested_map_1.get(0).get(0).get(0).read() == 1);
assert(storage.nested_map_1.get(1).get(1).get(1).read() == 8);
```

# Drawbacks

[drawbacks]: #drawbacks

There are two main drawbacks for the approach proposed above:

1. Reading and writing a storage variable is now a bit more complicated and less ergonomic than before because we now have to call `read` and `write` manually. We should consider making this more ergonomic by introducing a simpler syntax that de-sugars to the API calls above. For example, we could de-sugar something like `storage.x = 42` to `storage.x.write(42)`.

2. The second drawback is that, because sturcts are packed in storage, then we will often need to read a storage slot before writing to it because we may need to preserve parts of it if the value we're writing is smaller than the slot itself. This means that almost each storage write now also requires a storage read. This is the case in Solidity as well. The upside here is that a smaller number of storage slots will be needed overall.

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

- How do we make storage accesses more ergonomic? Or at least as ergonomic as they currently are?

# Future possibilities

[future-possibilities]: #future-possibilities

## Unpacked storage structs.

Unpacking structs in storage could be useful in certain situations. The advantage of unpacking sturcts is that each field and subfield gets its own storage slot which often makes reading and writing those fields and subfields cheaper. We may want to consider an annotation in the future that requests that a given struct is unpacked in storage.

## `Index` and `IndexAssign` traits

We can introduce the traits `Index` and `IndexAssign` which would allow implementing `index()` and `index_assign()` for dynamic storage types such as `StorageMap` and `StorageVec` as follows:

```rust
impl Index for StorageHandle<StorageMap<K, V>>
    fn index(self, key: K) -> StorageKey<V> {
        StorageKey {
            key: sha256((key, self.key)),
            offset: 0,
        }
    }
}

impl IndexAssign for StorageHandle<StorageMap<K, V>>
    #[storage(read, write)]
    pub fn index_assign(self, key: K, value: V) {
        let key = sha256((key, self.key));
        write::<V>(key, 0, value);
    }
}
```

Note that this deviates from Rust which has `Index` and `IndexMut`, but `IndexMut` likely requires mutable references in the language which we don't have. However, there has been [attempts](https://github.com/rust-lang/rfcs/pull/1129) to introduce `IndexAssign` in Rust but without any success due to reasons that I don't think apply to Sway.

With the above, the compiler can then de-sugar expressions like `a[i]` to `a.index(i)` and `a[i] = b` to `a.index_assign(i, b)`. For a nested `StorageMap`, the resulting user code would look like:

```rust
struct M {
    u: b256,
    v: u64,
}

storage {
    nested_map_2: StorageMap<(u64, u64), StorageMap<str[4], StorageMap<u64, M>>> = StorageMap {},
}

let m1 = M {
    u: 0x1111111111111111111111111111111111111111111111111111111111111111,
    v: 1,
};

storage.nested_map_2[(1, 0)]["0000"][0] = m1;
assert(storage.nested_map_2[(1, 0)]["0000"][0].read() == m1);
```
