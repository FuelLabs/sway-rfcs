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

```sway
fn id<const SIZE: usize>(array: [u64; SIZE]) -> [u64; SIZE] {
    array
}
```

This also allows `impl` items such as

```sway
impl<const N: usize> AbiEncode for str[N] {
    ...
}
```

This constant can be infered or explicitly specified. When infered, the syntax is no different than just using the item:

```sway
    id([1u8])
```

In the example above, the Sway compiler will infer `SIZE` to be one, because `id` parameter will be infered to be `[u8; 1]`.

For the cases where the compiler cannot infer this value, or this value comes from a expression, it is possible to do:

```sway
    id::<1>([1u8]);
    id::<{1 + 1}>([1u8, 2u8]);
```

When the value is not a literal, but an expression, it needs to enclosed by curly braces. This will fail, if the expression cannot be evaluated as `const`.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This new syntax has three forms: const generics declaration, call and reference.

const generics declarations can appear anywhere a generic argument declaration is valid:

1. Function/method declaration;
2. Struct/Enum declaration;
3. `impl` declarations.

const generics call can appears everywhere a declaration that contains a generic argument call be referenced:

1. Function/method reference;
1. Struct/Enum reference;
1. Fully qualified call paths.

const generics references can appear anywhere a reference to a const variable can appear. For semantic purposes there is no difference from the reference of a const generics and a "normal" const.

Different from type generics, const generics cannot appear at:

1. constraints;
1. where types are expected.

By the nature of `impl` declarations, it is possible to specialize for some specific types. For example:

```sway
impl SomeStruct<bool> {
    fn f() {        
    }
}
```

## Const Value Specialization

In the example above, `f` only is available when the generic argument of SomeStruct is know to be bool. By the nature of const generics, Sway will not support specialization by value. This mean that the example below will not be supported:

```sway
impl SomeIntegerStruct<1> {
    ...
}

impl SomeBoolStruct<false> {
    ...
}
```

The main reason for forbidding this option is that apart from `bool`, which only needs two values, all other constants would demand complex syntax to guarantee the completeness and uniqueness of all implementations, the same way that `match` expressions do.

## Monomorphization

As other generic arguments, `const generics` monormophize functions, which means that a new "TyFunctionDecl", for example, will be created for which value that is instantiated.

# Drawbacks

[drawbacks]: #drawbacks

No reasons

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

# Prior art

[prior-art]: #prior-art

https://doc.rust-lang.org/reference/items/generics.html#const-generics

# Unresolved questions

[unresolved-questions]: #unresolved-questions


# Future possibilities

[future-possibilities]: #future-possibilities

Sway does not have a distinction between `const` and `non-const` functions. Which means that we will need to deny function calls in `const generics expressions`, or we will need to evaluate them and fail when they are not `const`. This can impact compilation time.
