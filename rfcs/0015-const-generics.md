- Feature Name: const_generics
- Start Date: 2024-10-27
- RFC PR: [FuelLabs/sway-rfcs#42](https://github.com/FuelLabs/sway-rfcs/pull/42)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

Allows constant values as generic arguments.

# Motivation

[motivation]: #motivation

Some types have constants, specifically unsigned integers as part of their definition (e.g. arrays and string arrays). Without `const generics` it is impossible to have a single `impl` item for all instances of these types.  

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

`const generics` refer to the language syntax where generic parameters are defined as constant values, instead of types.

A simple example would be:

```rust
fn id<const SIZE: u64>(array: [u64; SIZE]) -> [u64; SIZE] {
    array
}
```

This also allows `impl` items such as

```rust
impl<const N: u64> AbiEncode for str[N] {
    ...
}
```

This constant can be inferred or explicitly specified. When inferred, the syntax is no different than just using the item:

```rust
id([1u8])
```

In the example above, the Sway compiler will infer `SIZE` to be one, because `id` parameter will be infered to be `[u8; 1]`.

For the cases where the compiler cannot infer this value, or this value comes from an expression, it is possible to do:

```rust
id::<1>([1u8]);
id::<{1 + 1}>([1u8, 2u8]);
```

When the value is not a literal, but an expression, it is named "const generic expression" and it needs to be enclosed by curly braces. This will fail if the expression cannot be evaluated as `const`.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This new syntax has three forms: declarations, instantiations, and references. 

"Const generics declarations" can appear anywhere all other generic arguments declarations are valid:

1. Function/method declaration;
1. Struct/Enum declaration;
1. `impl` declarations.

```rust
// 1
fn id<const N: u64>(...) { ... }

// 2
struct SpecialArray<const N: u64> {
    inner: [u8; N],
}

//3
impl<const N: u64> AbiEncode for str[N] {
    ...
}
```

"Const generics instantiations" can appear anywhere all other generic argument instantiations are valid:

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

"Const generics references" can appear anywhere any other identifier appears. For semantic purposes, there is no difference between the reference of a "const generics" and a "normal" const.  

```rust
fn f<const I: u64>() {
    __log(I);
}
```

Different from type generics, const generics cannot appear at:

1. constraints;
1. where types are expected.

```rust
// 1 - INVALID
fn f<const I: u64>() where I > 10 {
    ...
}

// 2 - INVALID
fn f<const I: u64>() -> Vec<I> {
    Vec::<I>::new()
}
```

## Const Value Specialization

By the nature of `impl` declarations, it is possible to specialize `impl` items for some specific types. For example:

```rust
impl SomeStruct<bool> {
    fn f() {        
    }
}
```

In the example above, `f` is only available when the generic argument of `SomeStruct` is known to be `bool`. This kind of specialization will not be supported for "const generics", which means that the example below will not be supported:  

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

As with other generic arguments, `const generics` monormorphize functions, which means that a new "TyFunctionDecl", for example, will be created for which value that is instantiated.

Prevention of code bloat will be the responsibility of the optimizer.  

Monomorphization for const generics has one extra complexity. To support arbitrary expressions it is needed to "solve" an equation. For example, if a variable is typed as `[u64; 1]` and a method with its `Self` type as `[u64; N + 1]` is called, the monomorphization process needs to know that `N` needs to be valued as `0` and if the variable is `[u64; 2]`, `N` will be `1`.  

## Type Engine changes

By the nature of `const generics`, it will be possible to write expressions inside types. Initially, only simple references will be
supported, but at some point, more complex expressions will be needed, for example:

```sway
fn len<T, const N: u64>(a: [T; N]) { ... }

fn bigger<const N: u64>(a: [u64; N]) -> [u64; N + 1] {
 [0; N + 1]
}
```

This poses the challenge of having an expression tree inside of the type system. Currently Sway already 
has three expression trees: `Expr`, `ExpressionKind` and `TyExpressionVariant`. This demands a new one,
given that the first two allow much more complex expressions than what `const generics` wants to support; 
and the last one is only created after some `TypeInfo` already exists, and thus cannot be used.  

At the same time, the parser should be able to parse any expression and return a friendly error that such expression  
is not supported. 

So, in case of an unsupported expression the parser will parser the `const generic` expression as it does for normal `Expr`and will lower it to the type system expression enum, but in the place of the unsupported expression will return a `TypeInfo::ErrorRecovery`.  

These expressions will also increase the complexity of all type related algorithms such as:  

1. Unification
2. PartialEq
3. Hash

In the simplest case, it is very clear how to unify `TypeInfo::Array(..., Length::Literal(1))` and `TypeInfo::Array(..., Length::Expression("N"))`.
But more complex cases such as `TypeInfo::Array(..., Length::Expression("N"))` and `TypeInfo::Array(..., Length::Expression("N + 1"))`, is not clear
if these types are unifiable, equal or simply different.

## Method call search algorithm

When a method is called, the algorithm that searches which method is called uses the method `TraitMap::get_impls`.
Currently, this method does an `O(1)` search to find all methods applicable to a type. For example:

```sway
impl [u64; 1] {
 fn len_for_size_one(&self) { ... }
}
```

would create a map with something like

```
Placeholder -> [...]
...
[u64; 1] -> [..., len_for_size_one,...]
...
```

The algorithms first create a `TypeRootFilter`, which is very similar to `TypeInfo`. And uses this `enum` to search the hash table.
After that, it "generalizes" the filter and searches for `TypeRootFilter::Placeholder`.

To fully support `const generics` and `const value specialization`, the compiler will now keep generalizing the
searched type until it hits `Placeholder`. For example, searching for `[u64; 1]` will actually search for:

1. [u64; 1];
1. [u64; Placeholder];
1. Placeholder;

The initial implementation will do this generalization only for `const generics`, but it also makes sense to 
generalize this with other types such as `Vec<u64>`.

1. Vec\<u64>;
1. Vec\<Placeholder>;
1. Placeholder;

This gets more complex as the number of `generics` and `const generics` increases. For example:

```sway
struct VecWithSmallVecOptimization<T, const N: u64> { ... }
```

Searching for this type would search:

1. VecWithSmallVecOptimization\<u64, 1>
1. VecWithSmallVecOptimization\<Placeholder, 1>
1. VecWithSmallVecOptimization\<u64, Placeholder>
1. VecWithSmallVecOptimization\<Placeholder, Placeholder>
1. Placeholder

More research is needed to understand if this change can potentially change the semantics of any program written in Sway.  

# Implementation Roadmap

1. Creation of the feature flag `const_generics`;
1. Implementation of "const generics references";
```rust
fn f<const I: u64>() { __log(I); }
```
3. The compiler will be able to encode arrays of any size; Which means being able to implement the following in the "core" lib and using arrays of any size as "configurables";
```rust
impl<T, const N: u64> AbiEncode for [T; N] { ... }
```
4. Being able to `abi_encode` arrays of any size;  
```rust
fn f<T, const N: u64>(s: [T; N]) -> raw_slice {
 <[T; N] as AbiEncode>::abi_encode(...);
}
f::<1>([1])
```
5. Inference of the example above;  
```rust
f([1]);
core::encode([1]);
```
6. Struct/enum support for const generics;
7. Function/method declaration;
8. `impl` declarations;
9. Function/method reference.

# Drawbacks

[drawbacks]: #drawbacks

None

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

# Prior art

[prior-art]: #prior-art

This RFC is partially based on Rust's own const generic system:  
- https://doc.rust-lang.org/reference/items/generics.html#const-generics  
- https://blog.rust-lang.org/inside-rust/2021/09/06/Splitting-const-generics.html  
- https://rust-lang.github.io/rfcs/2000-const-generics.html  
- https://doc.rust-lang.org/beta/unstable-book/language-features/generic-const-exprs.html  

# Unresolved questions

[unresolved-questions]: #unresolved-questions

1. What is the impact of changing the "method call search algorithm"?  

# Future possibilities

[future-possibilities]: #future-possibilities

As mentioned above, implementing constraints like where N > 0.
