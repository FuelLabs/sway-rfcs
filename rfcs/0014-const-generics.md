- Feature Name: (fill me in with a unique ident, `my_awesome_feature`)
- Start Date: (fill me in with today's date, YYYY-MM-DD)
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

Allows constant values as generic arguments.

# Motivation

[motivation]: #motivation

Some types have constants, specifically unsigned integers, as their definition (e.g. arrays and string arrays). Without const generics it is impossible to have `impl` items for all instances of these types.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

`const generics` refer to the language syntax where generic parameters are defined as constant values, instead of types.

A simple example would be:

```rust
fn id<const SIZE: usize>(array: [u64; SIZE]) -> [u64; SIZE] {
    array
}
```

This also allows `impl` items such as

```rust
impl<const N: usize> AbiEncode for str[N] {
    ...
}
```

This constant can be infered or explicitly specified. When infered, the syntax is no different than just using the item:

```rust
id([1u8])
```

In the example above, the Sway compiler will infer `SIZE` to be one, because `id` parameter will be infered to be `[u8; 1]`.

For the cases where the compiler cannot infer this value, or this value comes from a expression, it is possible to do:

```rust
id::<1>([1u8]);
id::<{1 + 1}>([1u8, 2u8]);
```

When the value is not a literal, but an expression, it is named "const generic expression" and it needs to be enclosed by curly braces. This will fail, if the expression cannot be evaluated as `const`.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This new syntax has three forms: declarations, instantiations and references.

"const generics declarations" can appear anywhere all others generic arguments declarations are valid:

1. Function/method declaration;
1. Struct/Enum declaration;
1. `impl` declarations.

```rust
// 1
fn id<const N: usize>(...) { ... }

// 2
struct SpecialArray<const N: usize> {
    inner: [u8; N],
}

//3
impl<const N: usize> AbiEncode for str[N] {
    ...
}
```

"const generics instantiations" can appear anywhere all others generic argument instantiations are valid:

1. Function/method reference;
1. Struct/Enum reference;
1. Fully qualified call paths.

```rust
// 1
id::<1>([1u8]);
special_array.do_something::<1>();

// 2
SpecialArray::<1>::new();

// 3
<SpecialArray::<1> as SpecialArrayTrait::<1>>::f();
```

"const generics references" can appear anywhere any other identifier appear. For semantic purposes there is no difference from the reference of a "const generics" and a "normal" const.

```rust
fn f<const I: usize>() {
    __log(I);
}
```

Different from type generics, const generics cannot appear at:

1. constraints;
1. where types are expected.

```rust
// 1 - INVALID
fn f<const I: usize>() where I > 10 {
    ...
}

// 2 - INVALID
fn f<const I: usize>() -> Vec<I> {
    Vec::<I>::new()
}
```

## Const Value Specialization

By the nature of `impl` declarations, it is possible to specialize for some specific types. For example:

```rust
impl SomeStruct<bool> {
    fn f() {        
    }
}
```

In the example above, `f` only is available when the generic argument of SomeStruct is know to be `bool`. This will not be supported for "const generics", which means that the example below will not be supported:

```rust
impl SomeIntegerStruct<1> {
    ...
}

impl SomeBoolStruct<false> {
    ...
}
```

The main reason for forbidding this is that apart from `bool`, which only needs two values, all other constants would demand complex syntax to guarantee the completeness and uniqueness of all implementations, the same way that `match` expressions do.

## Monomorphization

As other generic arguments, `const generics` monormorphize functions, which means that a new "TyFunctionDecl", for example, will be created for which value that is instantiated.

Prevention of code bloat will be responsability of the optimizer.

# Implementation Roadmap

1. Creation of the feature flag `const-generics`;
1. Implementation of "const generics references";
```rust
fn f<const I: usize>() { __log(I); }
```
3. The compiler will be able to encode arrays of any size; That means being able to implement the following in the "core" lib and using arrays of any size as configurables;
```rust
impl<T, const N: usize> AbiEncode for [T; N] { ... }
```
4. Being able to `encode` arrays of any size;
```rust
fn f<T, const N: usize>(s: [T; N]) -> raw_slice {
    <[T; N] as AbiEncode>::abi_encode(...);
}
f::<1>([1])
```
5. Inference of the example above
```rust
f([1]);
core::encode([1]);
```
6. Struct/enum support for const generics
7. Function/method declaration;
8. `impl` declarations.
9. Function/method reference;

# Drawbacks

[drawbacks]: #drawbacks

None

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

# Prior art

[prior-art]: #prior-art

This RFC is partially based on Rust's own const generic system: https://doc.rust-lang.org/reference/items/generics.html#const-generics

# Unresolved questions

[unresolved-questions]: #unresolved-questions

None

# Future possibilities

[future-possibilities]: #future-possibilities

Sway does not have a distinction between `const` and `non-const` functions. Which means that we will need to deny function calls in `const generics expressions`, or we will need to evaluate them and fail when they are not `const`. This can impact compilation time.
