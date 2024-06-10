 Name- Feature: `configurable_and_composable_storage`
- Start Date: 2024-06-10
- RFC PR: [FuelLabs/sway-rfcs#40](https://github.com/FuelLabs/sway-rfcs/pull/40)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC introduces a concept of a `Storage` trait, as well as the `StorageBox` and `StorageEncodedBox` structs. Those types are cornerstones upon which we build a fully flexible, feature rich, and robust access to storage. These concepts simplify defining dynamic storage types, like e.g., `StorageVec`. They also provide a dedicated way of configuring (in the `storage` declaration) and initializing (in the code) arbitrary storage types composed of existing storage types.

Additionally, the RFC provides API design guidelines for storage type's APIs. Those guidelines ensure that various aspects of a storage access like, e.g., accessing uninitialized storage, are alway treated in the same way, across various storage types.

# Motivation

[motivation]: #motivation

The [`storage_keys` RFC](./0008-storage-handler.md) introduced the concept of a `StorageKey` which improved the creation of dynamic storage types, like `StorageVec` and `StorageMap`. While bringing noticeable improvement at the time, that approach, which we currently use, has the following issues and limitations:
- There is no clear definition of a "storage type", or a "storable type".
  - E.g., the `x: u64 = 123` syntax only gives a (false) impression that we are storing a `u64` in the storage, while actually just being a syntax sugar for `x: StorageKey<u64> = <compiler-generated configuration of storage slots based on encoded u64>`.
  - This is especially confusing for dynamic storage types, because they are always, from the Sway perspective, just empty structs. Their real definition is an impl of `StorageKey<T>`. E.g., `StorageVec<V>` becomes `impl<V> StorageKey<StorageVec<V>>`.
  - Above points lead to confusing error messages when using `storage` and forbid having methods like `clear()` or `read()` on dynamic storage types, because they clash with already existing methods implemented for every `StorageKey`.
  - Similarly, the common methods, like the mentioned `clear()` and `read()` might not have sense for certain storage types but they are still always available.
- Composing dynamic storage types, e.g., `StorageVec<StorageVec<u64>>`, relays on the `field_id` hack in the `StorageKey`.
  - `field_id` represents an unnecessary cognitive burden when using `StorageKey`s.
  - Proper usage of `filed_id` is error-prone and its false usage, which is easy to happen, can lead to hard-to-explain bugs like, e.g., [this one](https://github.com/FuelLabs/sway/issues/6036F).   
- Clearing dynamic storage types, e.g., `StorageVec<T>`, relays on a global hack in the `clear()` method of the `StorageKey`.
- Dynamic storage types cannot be configured in the `storage` declaration.
  - Those types are always configured as empty Sway structs. E.g., `StorageVec { }`.
  - Programmers are forced to alway write those empty structs in the configuration, just to satisfy the compiler.
  - The only way to configure dynamic storage types is via SDKs, or by using them in code, thus at runtime.
- As a consequence of the above points, but also a separate requirement, it is not possible to write a const eval function that could configure a dynamic storage type based on a certain logic.
- As a consequence of the above points, but also a separate requirement, it is not possible to configure a dynamic storage type composed of other storage types, like e.g., `StorageMap<u64, StorageVec<u256>>`.
- Elements in the `storage` declaration must alway be configured, even if programmers just want to list them and actually configure them during deployment via SDKs.
- It is not possible to store dynamic Sway types like `Vec` and `String` in the storage.

The above points lead to:
- non-optimal developer experience (e.g., missing possibility to configure dynamic storage types in `storage` declarations; being forced to configure all `storage` elements, etc.).
- difficult and error-prone development of user-defined dynamic storage types due to error-prone storage access design and storage API.
- possibility to provide inconsistent APIs (e.g., `StorageVec::pop()` returns `V` while `StorageVec::get()` returns `StorageKey<V>`).

With the approach proposed in this RFC, we will solve all the above points by providing:
- clear abstractions for storable types via `Storage` trait, as well as storage primitives for storing arbitrary Sway types, even the dynamic ones.
  - The abstractions will forbid semantically wrong usage by-design.
- support for safe and arbitrary composable and configurable dynamic storage types.
  - Implementing the `Storage` trait will automatically make a storage type compatible with all other storage types.
- support for complex configuration of dynamic storage types in `storage` declarations.
- support for skipping default configuration of elements in `storage` declarations.

## Sample code

[sample-code]: #sample-code

To prove that such implementation is possible and to give a tangible feeling for the proposed new approach to storage handling, this RFC comes with extensive [sample code](../files/0013-configurable-and-composable-storage/):
- [sway-libs](../files/0013-configurable-and-composable-storage/sway-libs/) provide:
  - definition of the `Storage` trait as well as few other traits like, e.g., `DeepReadStorage` and `DeepClearStorage`.
  - implementation of the atomic `Storage` types, `StorageBox` and `StorageEncodedBox`.
  - implementation of STD dynamic storage types like, e.g., `StorageVec` and `StorageMap`.
- [user-defined-libs](../files/0013-configurable-and-composable-storage/user-defined-libs/) provide:
  - implementation of a user defined `StoragePair` storage type.
- [contracts](../files/0013-configurable-and-composable-storage/contracts/) provide:
  - several demo-contracts that demonstrate usage of the new storage.
- [api-design](../files/0013-configurable-and-composable-storage/api-design/) provides:
  - implementation of several storage types with the focus on explaining the proposed API design guidelines.

The sample code contains documentation for Sway programmers (using Sway doc-comments `///`), as well as extensive explanations for RFC reviewers (using comments starting with `//--`). Open discussion points are marked with `TODO-DISCUSSION`.

Going through the sample code is highly encouraged.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

This guide-level explanation primarily explains how the new `storage` declaration and `Storage` types will be used by Sway programmers. Explaining writing user-defined `Storage` types was more fitting to the [Reference-level explanation](#reference-level-explanation) and is explained there.

## `storage` declarations and storage types

[storage-declarations-and-storage-types]: #storage-declarations-and-storage-types

The `storage` declaration will get a new operator, `:=`, pronounced _configured with_. The left-hand side (LHS) of the `:=` operator will be the definition of the storage element, as it is now. The right-hand side (RHS) will represent the _configuration_ of that storage element. The configuration is any const eval expression that returns an instance of a type stored by the storage type specified on the LHS.

The type of the LHS storage element must implement the `Storage` trait. This trait denotes a storage type that can be an element of a `storage` declaration. The `Storage` trait is explained in detail in the [The `Storage` trait](#the-storage-trait) chapter of the [Reference-level explanation](#reference-level-explanation).

There are two classes of storage types. _Atomic storage types_ are the leafs of hierarchies of composed storage types. They cannot contain other storage types. _Compound storage types_ are storage types that contain other storage types. Standard library (STD) provides two _atomic storage types_, the [`StorageBox`](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_box.sw) and the [`StorageEncodedBox`](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_encoded_box.sw), as well as several compound storage types, like e.g., [`StorageVec`](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_vec.sw) and [`StorageMap`](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_map.sw).

To store Sway types of a known size that does not contain pointers or references, the `StorageBox` is used. To store a Sway type of a dynamic size, that implements `AbiEncode` and `AbiDecode`, the `StorageEncodedBox` is used.

```Sway
storage {
    box_1: StorageBox<u64> := 0,
    box_2: StorageBox<u64> := the_meaning_of_life(),

    box_3: StorageBox<Struct> := Struct::default(),
    box_4: StorageBox<Struct> := Struct { x: 11, y: false },
    box_4: StorageBox<Struct> := some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"),
}
```

If the `Struct` in the above example would have a dynamic size, to store it we just need to replace `StorageBox` with `StorageEncodedBox`:

```Sway
struct Struct {
    vec: Vec<u64>,
    txt: String,
}

box_1: StorageEncodedBox<Struct> := Struct::default(),
box_2: StorageEncodedBox<Struct> := Struct { vec: Vec::from([1, 2, 3]), txt: String::from("text") },
```

The later usage of `storage` elements is completely the same, regardless if they are stored in the `StorageBox` or `StorageEncodedBox`. The only difference is in the background. The `StorageEncodedBox` encodes and decodes the stored values during reading and writing using the ABI encoding and is thus more gas and storage demanding.

It is possible to arbitrarily compose and configure storage types. As an example, let's consider a `StorageVec<StorageVec<StorageBox<Struct>>>` and an intentionally complex `StorageMap`. Note that the `Struct` _must_ be stored in the `StorageBox`. The `StorageVec`, as well as all other _compound storage types_ can store only other store types.

The `[<content>]` on the RHSs represent instances of _typed slices_. As explained in the [Reference-level explanation](#reference-level-explanation), typed slices are one of the language prerequisites for the new storage.

```Sway
storage {
    vec_of_vec_1: StorageVec<StorageVec<StorageBox<Struct>>> := [
        [],
        [Struct::default()],
        [
            Struct::default(),
            Struct { x: 11, y: false },
            some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"),
        ]
    ],

    map_01: StorageMap<str[3], StorageVec<StorageMap<u64, StorageVec<StorageBox<Struct>>>>> := [
        ("abc", [
            (11, [Struct::default(), Struct { x: 11, y: false }]),
            (22, []),
            (33, [some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc"), Struct::default()]),
        ]),
        ("def", [
            (111, [Struct::default(), Struct { x: 111, y: true }]),
            (222, [Struct::new_false(222)]),
            (333, [some_const_fn_that_creates_struct(true, Struct { x: 22, y: true }, "abc")]),
        ]),
    ],
}
```

A simpler example of a `StorageVec` containing `u64` will look like:

```Sway
storage {
    vec_of_val_1: StorageVec<StorageBox<u64>> := [],
    vec_of_val_2: StorageVec<StorageBox<u64>> := [1, 2, 3, 4, 5],
}
```

Configuring compound storage types is automatically supported for all storage types (by implementing `Storage`). Here are a few examples for the user-defined storage type [`StoragePair`](../files/0013-configurable-and-composable-storage/user-defined-libs/storage_pair.sw):

```Sway
storage {
    pair_1: StoragePair<StorageBox<u64>, StorageEncodedBox<String>> := (123, String::from("text")),
    pair_2: StoragePair<StVecOfU64, StVecOfU64> := ([1, 2, 3], [11, 22, 33]),

    vec_of_pairs: StorageVec<StoragePair<StorageBox<Struct>, StVecOfU64>> := [
        (Struct { x: 0, y: true }, [1, 2, 3]),
        (Struct::default(), []),
        (Struct { x: 11, y: false }, [111, 222, 333]),
    ],

    map_of_pairs: StorageMap<str[3], StoragePair<StorageBox<Struct>, StVecOfU64>> := [
        ("abc", (Struct { x: 0, y: true }, [1, 2, 3])),
        ("def", Struct::default(), []),
        ("ghi", Struct { x: 11, y: false }, [111, 222, 333]),
    ],

    pair_of_pairs: StoragePair<StPairOfStVecOfU64, StPairOfStVecOfU64> := (
        ([1, 2, 3], [11, 22, 33]),
        ([4, 5, 6], [44, 55, 66])
    )
}
```

For more examples of using storage types in storage declarations, see:
- [`demo_contract_basic_storage.sw`](../files/0013-configurable-and-composable-storage/contracts/demo_contract_basic_storage.sw)
- [`demo_contract_encoded_storage.sw`](../files/0013-configurable-and-composable-storage/contracts/demo_contract_encoded_storage.sw).
- [`demo_contract_user_defined_storage.sw`](../files/0013-configurable-and-composable-storage/contracts/demo_contract_user_defined_storage.sw).

## Default `storage` configuration

[default-storage-configuration]: #default-storage-configuration

If developers just want to list the `storage` elements, knowing that they will be configured via SDKs, they can list the elements without providing the _configure with_ operator. The types of the values used to configure the elements must implement the `core::default::Default` trait that will be added to the STD.

```Sway
storage {
    built_in:    StorageBox<u64>,                                   // Same as `built_in: StorageBox<u64> := 0`.
    some_struct: StorageBox<Struct>,                                // `Struct` implements `core::default::Default`.
    storage_vec: StorageVec<StorageBox<u64>>,                       // Slices implement `Default` and the default is an empty slice `[]`.
    storage_map: StorageMap<str[3], StorageVec<StorageBox<u64>>>,   // Slices implement `Default` and the default is an empty slice `[]`.
}
```

## Using storage types in code

[using-storage-types-in-code]: #using-storage-types-in-code

All storage types will be implementing `Storage::new()` and `Storage::init()` constructors that will create an uninitialized and initialized instance of a storage type, respectively. In addition, they will follow the storage API guidelines explained in the [Storage API guidelines](#storage-api-guidelines).

`Storage` constructors and the atomic `StorageBox` and `StorageEncodedBox` will eliminate the need for using the low-level storage API in the contract code. The low-level API will be needed only when implementing custom storage, and even then, its usage will follow simple, well established patterns.

Storage API guidelines will provide unified developer experience across all storage types. Below are a few examples of using storage types in code.

An important term to establish will be the _self key_. Self key is the [`StorageKey`](../files/0013-configurable-and-composable-storage/sway-libs/storage.sw) at which an instance of a storage type is stored.

```Sway
fn demo() {
    // Obtain the self key of the locally created `StorageBox`.
    let local_box_self_key = get_storage_key();

    // `init` will create the `StorageBox` instance and initialize the storage to the `b256::zero()`.
    let local_box = StorageBox::<b256>::init(local_box_self_key, &b256::zero());

    // `read` reads the stored value or reverts if the `StorageBox` is uninitialized.
    assert_eq(local_box.read(), 0x0000000000000000000000000000000000000000000000000000000000000000);
}
```

When writing to the storage, developers will always write the _value_ that the particular storage expects, and not the storage contained in the storage, thus preventing by-design a wrong, error-prone usage that is possible with the current API. In other words, the API conveys the semantics of composition and containment of storage type hierarchies, which also implies ownership. If a storage is contained in another storage, it cannot at the same time be contained in some other storage.

```Sway
fn demo() {
    let mut local_vec_of_vec_of_vec_1 = StorageVec<StorageVec<StorageVec<StorageBox<u64>>>>::init(self_key, &[
        [],
        [[]],
        [[], []],
        [[11, 22, 33], [33, 22, 11]]
    ]);

    // The overall Storage API prohibits semantically wrong usage.
    // The desired composition semantics that implies ownership of the
    // stored data is imposed by the API.
    //
    // E.g., `StorageVec::push` does not accept the contained storage
    // as the type but rather the value that needs to be contained.
    //
    // This prohibits error-prone usage like:
    //
    // let vec_of_vec_a = StorageVec<StorageVec<StorageBox<u6>>>::init(...);
    // let vec_of_vec_b = StorageVec<StorageVec<StorageBox<u6>>>::init(...);
    // let element_of_a = a.get(0);
    // vec_of_vec_of_b.push(element_of_a);
    //
    // `StorageVec` which is contained in `a` cannot be contained in `b`!

    // In the proposed API, storing in the storage means providing the _value_ to be stored.
    local_vec_of_vec_of_vec_1.push(&[[11, 22, 33], [33, 22, 11]]);
}
```

Storage types will also implement some common storage traits like `DeepReadStorage` and `DeepClearStorage` defined in [`storage.sw`](../files/0013-configurable-and-composable-storage/sway-libs/storage.sw). This will increase the uniformity of use even more. E.g., the `DeepReadStorage` will be implemented by storage types that are fully aware of all the content they store and can read their entire content in one, presumably optimized go.

E.g., the `StorageVec` implements `DeepReadStorage`. So, to get the whole content of, e.g., a `StorageVec<StorageVec<StorageBox<u64>>>` will look like:

```Sway
// `deep_read` returns the same type that `init` accepts, the type contained and specified by the `Storage` implementation.
let value = storage.vec_of_vec_of_u64.deep_read();

// In this case that type is a slice of slices of `u64`.
assert_eq(value, [[1, 2, 3], [11, 22, 33]]);
```

For more examples on using storage types in code, see the `demo` functions in the [demo contracts](../files/0013-configurable-and-composable-storage/contracts/).

## Storage API design guidelines

[storage-api-design-guidelines]: #storage-api-design-guidelines

Storage API design guidelines are discussed and explained in detail in sample implementations given in the [`api-design`](../files/0013-configurable-and-composable-storage/api-design/). Here we are listing the major decisions and why they make the usage of the API easier by clearly communicating potential nuances in the usage of a particular storage type.

1. The API clearly communicates that the underlying storage might be uninitialized which can cause certain operations, like e.g. `StorageBox::read()` to fail. _All_ operations that can fail must have the `try_` prefix and return an `Option`.
1. Every `try_` operation has its "non-try" counterpart that returns the value and reverts if the operation fails internally. The counterpart is always named the same as the `try_`, but without the `try_` prefix. E.g., `read()` for `try_read()`.
1. Uninitialized storage instances are always safe to use. This way we benefit of the possibility to not pay for default initialization and still safely use the storage instance. Every storage type will provide its own semantics for uninitialized storage state. E.g. an uninitialized [`StorageVec`](../files/0013-configurable-and-composable-storage/api-design/storage_vec.sw) has the same semantics as an empty `StorageVec`.
1. Thus, the failing of `try_` methods can always be seen as a semantic failure. E.g., `StorageVec::try_get()` can fail if the `StorageVec` is not initialized or because it requested element index is out of bounds. Since in the first case we consider the vector to be empty, it is also a semantic error.
1. Certain operations might have a version with a "special behavior". E.g., in the case of the `StorageVec`, we want to provide a possibility to `get()` an element without the expensive length check. In such cases, the method will be named by the original name, and the suffix indicating the "special behavior". E.g., `StorageVec::get_unchecked()`.
1. When the special behavior consists of doing deep clear via `DeepClearStorage` or deep read via `DeepReadStorage`, the suffix will always be `_deep_clear` and `_deep_read`, respectively.

Thus, every storage type operation might come in all or some of these flavours:
- `fn <operation>() -> T`: reverts in case of uninitialized storage or other error.
- `fn try_<operation>() -> Option<T>`
- `fn <operation>_<special_behavior>() -> T`: reverts in case of uninitialized storage or other error.
- `fn try_<operation>_<special_behavior>() -> Option<T>`

This might look like cluttering of a single operation, but:
1. it properly communicates the behavior of the operation.
1. having an operation actually implementing all four variants will be rare.

For real-life examples, and the proof of the second point, consider the sample implementations provided in the [`api-design`](../files/0013-configurable-and-composable-storage/api-design/).

## Storage references

[storage-references]: #storage-references

Sometimes we want to be able to store in the storage a "reference" to another storage instance. Storage API and the compiler will provide support for such use cases. On the API level, the `StorageRef` type (defined in the [`storage.sw`](../files/0013-configurable-and-composable-storage/sway-libs/storage.sw)) will contain a type-safe "reference" to a storage element. This "reference" will internally just be the `StorageKey` of the referenced storage element.

```Sway
pub enum StorageRef<TStorage> where TStorage: Storage {
    Null: (),
    Ref: StorageKey,
}
```

`StorageRef`s will be stored in [`StorageRefBox`es](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_ref_box.sw) and once retrieved from the storage it will be possible to dereference them to access the referenced storage.

Every storage type automatically provides the `StorageRef` that references it, via the `Storage::as_ref` method.

Thus, storage references provide a convenient, type-safe way to express referencing storage elements, but with a price that might be considerable in some cases. Namely, the `StorageRef` requires two storage slots to store a reference. This means that developers might consider other, less storage consuming, manual approaches to "reference" a storage entity. E.g., if referenced elements are stored in a `StorageVec`, "referencing" them by storing their vector indices as "references" might be less storage-costly. In this case, we are trading type-safety and clear built-in API for the performance.

Storage reference will be supported in the `storage` declarations, by allowing the `storage` keyword to be used on the RHS of the _configure with_ operator:

```Sway
type StVecOfU64 = StorageVec<StorageBox<u64>>;
type StPairOfStVecOfU64 = StoragePair<StVecOfU64, StVecOfU64>;

storage {
    vec_1: StVecOfU64 := [11, 22, 33],
    vec_2: StVecOfU64 := [44, 55, 66],

    pair_1: StPairOfStVecOfU64 := ([0, 0, 0], [1, 1, 1]),
    pair_2: StPairOfStVecOfU64 := ([], []),

    map_1: StorageMap<str[3], StVecOfU64> := [
        ("abc", [1, 2, 3]),
        ("def", [11, 22, 33]),
        ("ghi", [111, 222, 333]),
    ]

    //--
    // Storage references can be used in storage configurations.
    // They can reference other storage elements, or their parts.
    //--
    vec_of_refs: StorageVec<StorageRefBox<StVecOfU64>> := [
        StorageRef::Null,
        storage.vec_1.as_ref(), // <<-- Note using the `storage` keyword here, as well as `as_ref`.
        storage.pair_1.first().as_ref(),
        storage.map_1.get("abc").as_ref(),
        StorageRef::Ref(some_const_fn_that_returns_the_storage_key_of_the_referenced_storage()),
    ],
}
```

For more examples on using storage references, see the [`demo_contract_storage_references.sw`](../files/0013-configurable-and-composable-storage/contracts/demo_contract_storage_references.sw).

## Breaking changes

[breaking-changes]: #breaking-changes

This proposal brings breaking changes in:
- `storage` declarations.
- existing STD storage types like, e.g., `StorageVec`.
- low-level storage API.
- the code that deals with the storage, via any of the above approaches.

Additionally, values stored using the current storage API cannot always be read with the new API and vice versa, because some of the changes will result in a different layout of the stored values within the storage.

To support explaining breaking changes to existing users and to ease migration we will:
- utilize [expressive diagnostics](./0012-expressive-diagnostics.md) to provide detailed explanations on how to fix compiler errors and migrate the code.
- where applicable, provide scripts to semi-automate the migration by converting the existing code to the new syntax and semantics.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

The implementation of the proposed features relies on a couple of other language features that need to be implemented first. We will only list them here, since their detailed explanation, in certain cases, could require a separate RFC. To follow the reference-level explanation of the configurable and composable storage, it is sufficient to have an intuitive understanding of these language features. Where needed, they are explained in enough detail in the [sample code](../files/0013-configurable-and-composable-storage/).

The [sample code](../files/0013-configurable-and-composable-storage/) provides a detailed view on how the Sway STD part of this RFC will be implemented and used.

Here, we will focus on the compiler support for the feature.

The additional language features that are the prerequisite to implement this RFC are:
- const functions and traits.
- typed slices.
- marker traits.
- negative impls.
- type aliases with generic parameters and trait constraints.

## The `Storage` trait

[the-storage-trait]: #the-storage-trait

The `Storage` trait is [defined](../files/0013-configurable-and-composable-storage/sway-libs/storage.sw) as:

```Sway
pub trait Storage {
    type Value;
    type Config;

    const fn new(self_key: &StorageKey) -> Self;

    const fn internal_get_config(self_key: &StorageKey, value: &Self::Value) -> Self::Config;

    const fn internal_layout() -> StorageLayout;

    const fn self_key(&self) -> StorageKey;

    #[storage(write)]
    fn init(self_key: &StorageKey, value: &Self::Value) -> Self;
} {
    const fn as_ref(&self) -> StorageRef<Self> {
        StorageRef::<Self>::Ref(self.self_key())
    }
}
```

The functions prefixed with `internal` are used only when implementing storage types, and should never be used in contract code.

`Storage` trait methods and associated types provide all the information needed by the compiler to:
- support configuring arbitrary storage types in `storage` declarations.
- support type-checking arbitrary composition of storage types.

The get a hands-on feeling for concrete implementations of the `Storage` trait and better understanding of the meaning of its methods and associated types see the [provided implementations of STD storage types](../files/0013-configurable-and-composable-storage/sway-libs/storage/) and the user-defined [`StoragePair`](../files/0013-configurable-and-composable-storage/user-defined-libs/storage_pair.sw).

Let's explain the `Storage` type by explaining how it is used by the compiler and when implementing storage types.

### Configuring storage

[configuring-storage]: #configuring-storage

The `Value` associated type specifies the type of the _entire_ value that is stored in the storage. Compiler expect the RHS of the _configure with_ operator to be of this type.

E.g., the `StorageBox<T>` stores values of type `T` which means it will define its `Value` as `type Value = T`.

Arbitrary composition of storage types is made simple by intuitive recursive definitions of `Value` associated types.

E.g., the `StorageVec<TStorage>` (note here that every _compound storage type_ can store only types that implement `Storage`) will store slices of whatever the value of the contained `TStorage` is. Thus, its `Value` will simply be `type Value = [TStorage::Value]`.

Similarly, the `StorageMap` will store `(K, V)` tuples, where `V` must be `Storage`. Thus, its `Value` will simply be `type Value = (K, V::Value)`.

Once the `Value` is specified in the `Storage` implementation the compiler can type-check the RHS of `:=` against the `Value` expected by the LHS. It is worth noticing here that we have all the information needed, to, in a case of a type-mismatch, provide a detailed [expressive diagnostics](./0012-expressive-diagnostics.md) explaining the error.

Also, every storage type will always have the same way of configuring, defined by the `Value` type. This guarantees intuitive and consistent usage. E.g., for the `StorageVec`, developers will know that they always need to provide a slice of the values expected by the contained storage type.

The provided RHS expression that returns the type specified by `Value` must be const eval, as it is now.

In the second step, the compiler needs to calculate the concrete storage slots in which to store the _configured with_ RHS values.

This is where the `Storage::Config` associated type comes in play, together with the `const fn` function `internal_get_config()`.

Before generating the slots, the compiler already knows:
- the `StorageKey` at which a particular `storage` element will be stored. This key is calculated based on the element name and namespace, or it is given using the `in` keyword. This storage key is, as mentioned below, called the _self key_ of the storage element.
- the const eval calculated RHS which has the type `Value`.

The `const fn internal_get_config()` takes exactly those two parameters and provides a result of type `Self::Config`. Every `Self::Config` type is a combination of `StorageConfig` types defined as:

```Sway
pub struct StorageConfig<TValue>
{
    pub storage_key: StorageKey,
    pub value: TValue,
}
```

Essentially, the `StorageConfig<TValue>` tells the compiler at which `storage_key` the `value` should be stored. This information is const calculated by every storage type.

E.g., the `StorageBox<T>` simply stores a value of the type `T` at its `self_key`. Therefore, its `Config` will be defined as `type Config = StorageConfig<T>`.

E.g., the `StorageVec<TStorage>` must be able to store the vector's length and the configuration of all the contained elements. Thus, its `Config` can be specified as `type Config = (StorageConfig<u64>, [TStorage::Config])`. The first part of the tuple is the length, and the second the slice of all the `Config`s of the contained storage type.

In general, the `Config` type is defined recursively as:

```
<Config> := StorageConfig<TValue>
            | [<Config>]
            | (<Config>, ...);
```

Where `[<Config>]` represents a slice of `Config`s and `(<Config>, ...)` a tuple of arbitrary many `Config`s.

During the evaluation of storage slots, the compiler will traverse the structure returned by the `internal_get_config()` and for every occurrence of `StorageConfig<TValue>` it will create the corresponding slot definition.

Note that the constraints set on _atomic storage types_ will ensure that the `TValue` is of a type that compiler can serialize to slots.

### Using `storage` in code

[using-storage-in-code]: #using-storage-in-code

When a `storage` element is accessed in code via, e.g., `storage::ns1::ns2.elem`, the compiler will calculate the _self key_ of the element (`elem` in this example) and call the `Storage::new()` implementation of its storage type to create an instance. The `new` will get the calculated _self_key_ as the parameter.

Notice here that a `storage` element is always guaranteed to be a type that implements `Storage`. Having a non-`Storage` type in a `storage` declaration is a compile error. E.g, this is not allowed:

```Sway
storage {
    x: u64 := 0, // ERROR: `u64` does not implement `Storage`.
}
```

### Optimizing storage layout

[optimizing-storage-layout]: #optimizing-storage-layout

The `Storage::internal_layout()` function returns an instance of the `StorageLayout` enum defined as:

```Sway
/// Defines how a concrete [Storage] implementation places
/// its stored values within the storage, relative to the
/// given self key of the storage.
pub enum StorageLayout {
    /// The values are scattered within the storage and
    /// can be on arbitrary storage slots, unrelated to
    /// the self key.
    Scattered: (),
    /// The values are stored starting from the self key
    /// in a continuous sequence of consecutive storage
    /// slots. The size that the stored value occupies is
    /// not know and can vary.
    Continuous: (),
    /// The values are stored starting from the self key
    /// in a continuous sequence of consecutive storage
    /// slots. The size that the stored value occupies is
    /// known and fixed.
    ContinuousOfKnownSize: u64,
}
```

This way, a storage type, when embedded within another storage can signal to its "parent" to optimize storing of its child elements by e.g., packing them.

E.g., the `StorageVec<TStorage>` will use this information to pack its elements in consecutive slots if the `TStorage` is, e.g., `StorageBox<Struct>` whose layout is the fixed `ContinuousOfKnownSize(__size_of(Struct))`. To see how the `internal_layout` function is used in the implementation of the `StorageVec` see [`storage_vec.sw`](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_vec.sw).

E.g., the user-defined `StoragePair<A, B>` also uses this information to provide optimal storage use, as shown in the [`storage_pair.sw`](../files/0013-configurable-and-composable-storage/user-defined-libs/storage_pair.sw).

### Developing storage types

[developing-storage-types]: #developing-storage-types

With the `Storage` trait defined as such, developing arbitrary storage types becomes straightforward. Every storage type is to be seen as a recursive container of other storage types, where we know that this "recursion" must end with some of the _atomic storage types_.

Thus, the implementations of storage types are essentially recursive compositions of their contained storage types. The `Value` and the `Config` associated types will, in general, be constructed based on the `Value` and `Config` types of the contained storage types. Similarly, the implementations of the `internal_get_config()` and `init()` functions will recursively call those same methods of the contained storage types.

To get the feeling for these straightforward and essentially short and compact implementations of storage types, see the atomic and compound storage types implemented in [`sway-libs`](../files/0013-configurable-and-composable-storage/sway-libs/) and the user-defined [`StoragePair`](../files/0013-configurable-and-composable-storage/user-defined-libs/storage_pair.sw).

### Defining storage traits

[defining-storage-traits]: #defining-storage-traits

The clear definition of the `Storage` trait allows defining storage traits. A storage trait is a trait that has `Storage` as a supertrait. The STD will come with (at least) two storage traits, `DeepReadStorage` and `DeepClearStorage` both defined in the [`storage.sw`](../files/0013-configurable-and-composable-storage/sway-libs/storage.sw).

The implementations of storage traits will, similar to the implementations of `Storage`, be straightforward and based on recursive calls to the implementations of the same storage traits on the contained storage types.

To get the feeling for these straightforward and essentially short and compact implementations of storage traits, see the implementations of `DeepReadStorage` and `DeepClearStorage` for [`StorageVec`](../files/0013-configurable-and-composable-storage/sway-libs/storage/storage_vec.sw) and [`StoragePair`](../files/0013-configurable-and-composable-storage/user-defined-libs/storage_pair.sw).

By convention, all storage trait will have the suffix `Storage`.

## Internal API and the `__state` intrinsics

[internal-api-and-the-state-intrinsics]: #internal-api-and-the-state-intrinsics

The STD will still provide the low-level storage `read`, `write`, and `clear` functions. However, unlike now when they are actually sometimes needed in contract code, e.g., to store arrays, in the new storage implementation there should never be a need to use them in contracts. Instead, the atomic `StorageBox` and `StorageEncodedBox` should be used. They provide the same low-level functionality while offering safe storage access.

The low-level API will be used only when implementing storage types, and even in those cases not always. Thus, the proposal is to move them to the module named [`internal`](../files/0013-configurable-and-composable-storage/sway-libs/storage/internal.sw) to emphasize that they are, similar to `Storage::internal_` functions, meant to be used only when developing custom storage types.

Similarly, the `__state_` intrinsics should be used only in the implementations of the internal API functions. In addition, the `__state_load_word` intrinsic should be changed to return the information if the requested slot was set or unset.

# Drawbacks

[drawbacks]: #drawbacks

The only drawback I can think of is the time and effort needed to implement the proposal and to deal with the [breaking changes](#breaking-changes). However, the impact of _not_ improving the current storage handling will over time surely be higher. It would mean carrying on the issues mentioned in the [Motivation](#motivation) and, worst of all, living with an API that is error-prone by-design.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

During the work on this RFC, five different approaches were intensely discussed and modeled in code. Non of them came even near to the simplicity of use and implementation of the proposed approach. Also, all of the discussed approaches could not guarantee an API that would prevent error-prone implementation of storage types, when it comes to the containment and composition semantics.

For the storage API design guidelines, three different approaches were considered. We've tried to, e.g.:
- additionally distinguish between operations failing because of the storage being uninitialized and because of semantic errors like out of bound access. 
- avoid having possible multiple versions of a method by, e.g., putting the `Storage` instance in a "state" where it behaves differently for particular operations.

All three approaches ended up to be less intuitive to use and implement then the approach proposed in the [Storage API design guidelines](#storage-api-design-guidelines).

# Prior art

[prior-art]: #prior-art

As the [`storage_keys` RFC](./0008-storage-handler.md) puts it, there is no much prior art that would correspond with the overall direction for storage handling that we took in Sway. This means, having the `storage` elements be distinguished and having the API that communicates that storage operations might fail.

The proposed approach builds on top of those two premisses, and brings robust and easy to implement composable storage types that can be arbitrarily configured in `storage` declarations.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

Through the RFC process I expect the following open questions to be resolved:
- questions posed in the [sample code](../files/0013-configurable-and-composable-storage/) and marked with `TODO-DISCUSSION`.
- naming of proposed code elements like, e.g., method/function names, type names, etc. Since those names will become the part of the storage API it is of highest importance to come up with good and expressive names for abstractions.

Also, I expect the current storage attributes, `#[storage(read, write)]`, to be discussed. In the sample code, the existing attributes are used. However, there are two questions to be decided on:
- if the meaning of `write` remains "read and write" as it is now, the attributes should be renamed to `readonly` and `readwrite`.
- if we want to strictly distinguish between `read` and `write`, the question is why not introduce `clear` as well, which is currently treated as `write`.

# Future possibilities

[future-possibilities]: #future-possibilities

As already mentioned in the [`storage_keys` RFC](./0008-storage-handler.md), if we ever introduce the `Index` trait, it can also be implemented for the storage types like, e.g., `StorageVec`.