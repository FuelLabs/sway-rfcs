- Feature Name: `references`
- Start Date: 2023-08-17
- RFC PR: [FuelLabs/sway-rfcs#28](https://github.com/FuelLabs/sway-rfcs/issues/28)
- Sway Issue: [FueLabs/sway#5063](https://github.com/FuelLabs/sway/issues/5063)

# Summary

[summary]: #summary

This RFC aims to make the paradigm for handling reference types clear, fully typed and to
eliminate redundant concepts.

# Motivation

[motivation]: #motivation

There currently exists a kludge of features on top of pointers that have
various levels of type correctness, offer various paradigms and have less than
coherent syntax.

We want to clarify the rules for passing dynamic data to and from functions, how
they are expressed in the type system and through syntax, and eliminate untyped
values such as `raw_ptr` and `raw_slice`.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

Unlike Rust, Sway does not manage lifetimes. Due to the nature of smart contract
execution, dynamic memory usage only grows and allocated memory is allocated for
the entire lifetime of the execution. In Rust terms, every reference value has a
lifetime of `'static`.

This allows us to do away with some complexity and handle values more like they
would be in Java or ML.
In most cases, you shouldn't need to use explicit pointer types.

## Data types

In Sway there are two types of data types. Value types and Reference types.

Value types live for the lifetime of the function they are declared in. They are
passed and returned by value, which means their value is directly copied. Value
types include `u8`, `u16`, `u32`, `u64`, tuples such as `()`, `(u8, u64)` and
pointers such as `*mut u8`.

Reference types are represented by a pointer to a memory region and can have a
dynamic size. They are passed and returned by reference, which means the pointer
is copied and still points to the same data.

There are two kinds of references. Slim and fat.

Slim references are implemented using a single address. Slim references
include structs, enums and arrays, such as `String`, `Option`, `[u8; 42]`.

Fat references are implemented using an address and a small amount of additional
data, either a length or a pointer to a more complex table. Fat references
include slices, such as `[u8]`, `str`.

## Box

It is sometimes desirable to have a reference to a value type, such as for
passing a mutable reference to it to a function. This can be achieved with the
`Box` struct, which is so defined:

```sway
pub struct Box<T> {
    val: T
}
```

and produces the desired memory representation.

## Pointers

There are cases where one may want to directly manipulate memory addresses with pointer arithmetic,
to allow for this we have a pointer type that represents a single address: `*mut T` where T is the type being pointed to.

Pointers can be obtained by using the `__addr_of` intrinsic on a reference and dereferenced using the `__deref` intrinsic, like so:

```sway
let val: u64 = 1;
let ptr: *mut u64 = __addr_of(Box::new(val));
let ptr_val: u64 = __deref(ptr);
assert_eq(val, ptr_val);

let val: Box<u64> = Box::new(1);
let ptr: *mut Box<u64> = __addr_of(Box::new(val));
let ptr_val: Box<u64> = __deref(ptr);
assert_eq(val, ptr_val);

let val: Box<u64> = Box::new(1);
let ptr: *mut u64 = __addr_of(val);
let ptr_val: u64 = __deref(ptr);
assert_eq(val, Box::new(ptr_val));
```

Dereferencing an invalid pointer is Undefined Behavior.

## Slices

Slices represent contiguous areas of dynamic memory.
They can be used to represent dynamically sized data.
Slices are represented on the by a pair containing a pointer to the data and a length.

String slices, of type `str` represent a series of bytes encoding a valid UTF-8 string.
This is the type returned by string literals.

```sway
let _: str = "Lorem Ipsum";
````

Typed slices, of type `[T]`, represent contiguous series of elements of a type `T`.

```sway
let _: [u64] = [1, 2, 3].as_slice();
````

Slices can be obtained from arrays and other slices by using the `__slice`
intrinsic. This will produce a smaller slice of the argument type at the
specified indices. This slicing is bounds checked and will produce a revert if
slicing out of bounds.


```sway
let array: [u64; 4] = [1, 2, 3, 4];

// will produce 1, 2, 3, 4
let slice: [u64] = __slice(array, 0, 4);

// will produce 2, 3
let slice: [u64] = __slice(array, 1, 3);

// will revert
// let slice: [u64] = __slice(array, 0, 5);
````

Elements of slices can be obtained using the `__slice_elem` intrinsic.
This will return the element at the given index. Invalid indices will produce a revert.

```sway
let slice: [u64] = [1, 2, 3, 4].as_slice();

let elem = __slice_elem(slice, 2);
assert_eq(elem, 3);

// will revert
// let elem = __slice_elem(slice, 4);
```

## Passing values

When values are passed as arguments to a function they are either mutable or
immutable which is denoted by the `mut` prefix in the argument type.

Mutable value type arguments can be reassigned.

Mutable reference arguments can both be reassigned and have their fields
assigned to.

```sway
fn foo(
    mut arg1: Box<u32>,
    arg2: Box<u32>,
    mut arg3: u32,
    arg4: u32
) {
    // arg1 is mutable so this is legal
    arg1.val = 0;

    // arg1 is mutable so this is legal,
    // but it won't affect the original value the reference pointed to
    arg1 = Box { val: 1 };

    // arg2 is immutable so both or these are illegal
    // arg2.val = 0;
    // arg2 = Box { val: 1 };

    // arg3 is mutable so this is legal
    arg3 = 0;

    // arg4 is immutable so this is illegal
    // arg4 = 0;
}
```

## Returning values

Values returned by functions are mutable by default.

You can prepend the return type with `const` to make a reference return type
immutable and guarantee that the data pointed to by a returned reference type
will not be mutated.

```sway
fn foo() -> Box<u32> {
    Box { val: 0 }
}

fn bar() -> const Box<u32> {
    Box { val: 0 }
}


pub fn main() {
    // both of these are legal because foo returns a mutable value 
    let _ = foo();
    let mut _ = foo();


    // only the first is legal because bar returns an immutable value 
    let _ = bar();
    // let mut _ = bar();
}

```

Using `const` on value types is not allowed:

```sway
// this is illegal
// fn fun() -> const u32 { 0 }
```

## Methods

Methods definitions use `self` to refer to the value the method is being called
on, this follows the same rules defined for functions, except of course `self`
can't be reassigned.

```sway
struct S {
    a: u32,
}

impl S {
    pub fn foo(self) {
      // illegal since self is immutable
      // self.a = 0;
    }
    pub fn foo(mut self) {
      // legal since self is mutable
        self.a = 0;
    }
}

```

## Migration

Existing codebases can adapt to this change by changing every occurrence of `ref
mut` to `mut` and every use of `raw_slice` and `raw_ptr` to uses of `Box`, typed
pointer and slice types.

In general, switching untyped pointers to a properly typed `Box`, even a generic
`Box<T>`, is preferred. Pointers for whom the pointee isn't a value that can be
named may need to use `Box<()>` or `*mut ()`, the former is preferred.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Slices

Implementing the new slice types should require:

* parser changes to introduce the new syntax
* adding the new types to the type system (this is already partially done)
* implementing the `__slice` and `__slice_elem` intrinsics

The slicing intrinsics should be thoroughly tested (specifically on the bounds checking).

There are considerations to be given to the element sizes. We'll want to finish
current changes to the memory representation of small values so that `[u8]`
represents a continuous series of bytes without padding or provide this capability in other ways.

One thing to keep in mind is that slices' dynamic size makes them difficult to
deal with for the current ABI and they can't be returned as element of other
dynamic types. This is to be addressed by [a later RFC](https://github.com/FuelLabs/sway-rfcs/issues/29).

String literals are meant to return `str` and string array types are meant to
be totally replaced by `str`, however due to this ABI issue we'll need to keep
them around until further changes so string data can still be passed through
the ABI. We may want to consider temporarily introducing an intrinsic to convert
a string slice to a string array of a given size (with or without some bounds
checking).

`raw_slice` backs a lot of our dynamic types but we should be able to replace
most of its uses with a properly represented `[u8]`.

## References

Clarifying the reference syntax for function calls should only require a bunch
of small changes to the parser, except for the introduction of `const` return
values.

The way mutability is currently checked should already be compatible with
returning such immutable values and checking them against the mutability of
their local environment (even for a `let`), however we will need to introduce a
check to make sure that `const` is only used with reference types.

## Pointers

`*mut` should provide a fully typed alternative to `raw_ptr`.

`__addr_of` will have to be altered to return a `*mut` and we'll need to
introduce `__deref`.

We will not check pointer mutability at this time, hence the `mut` in `*mut`,
however we'll probably want to introduce `*const` once typed pointers are
stabilized.

Using this instead of `raw_ptr` will require heavy edits of `std` and `core`.

We may need to support pointer casts without asm block hacks. Introducing a
`__ptr_cast` intrinsic is on the table if this becomes a requirement.


# Drawbacks

[drawbacks]: #drawbacks

Changing the base assumptions about what a type represents is a major change and
programmers coming from Rust may be surprised at the differences. However the
differences are easy enough to explain and being able to shed the complexity of
borrow semantics is worth the cost. We may want to make the particulars of how
references work in Sway explicit in documentation aimed at programmers coming
from Rust.

The proposed formulation contains some ambiguity between mutable references
and references to mutable data. This should not be a major issue in practice as
the edge cases that require expressing the difference are rare, but those rare
cases should be expressible with `*mut` and `*const` pointers once we eventually
introduce the pair of them.

Abstracting away memory management too much might be a drawback for Sway and its
positioning as a smart-contract language, however maintaining access to pointer
arithmetic should still allow for atypical usage patterns without compromising
the use of safe and zero cost abstractions for most cases.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

To make the use of references more explicit and maintain syntax legibility for
people coming from Rust we could have chosen to use `&` everywhere a reference
is used and/or implicitly added it for unqualified reference types. However the
reason for Rust's use of this syntax rather than ML's terseness is to support a
borrow checker and guarantees that we do not make. The extra syntax burden does
not seem worth it since we do not provide such guarantees, nor need to provide
them. It can even be misleading.

Since we're leaning more towards ML, we may also have chosen to use `ref`
instead of `Box` to denote reference types. However we already majorly borrow
from Rust for our library abstractions, and a single field struct seems like the
simplest way of generating a reference type in Sway as it is.

The ambiguity as to the mutability of references or their content leads to a
choice when picking function argument syntax. i.e.: we could have used  `val:
mut T` or `mut val: T` or any combination of the two. Since we decided to
collapse the mutability into one to simplify things, the current syntax is used
since it is closer to the existing Sway behavior.

The use of `const` to denote returning const references is paricularly
conspicuous. The issue is that in Rust and in current Sway, returing an
unqualified reference type means returning a mutable type. Breaking this
assumption would not just be a big breaking change but may not even be a good
idea since mutable values are what people want to return most of the time.

Adding a qualifier seems like the least painful way to add the ability to return
immutable references (which is an absolute requirement). We may want to later
consider forcing people to add `const` or `mut` to their return values at a
later date, and perhaps even later make the `const` implicit.

# Prior art

[prior-art]: #prior-art

A lot of the design choices of this RFC have to do with strinking the balance
between Rust and ML's levels of abstraction. Sway is not meant to be a general
purpose systems programming language, but it is not a functional memory managed
language either. We want to maintain access to memory primitives whilst making
most Sway code terse, legible and easily understandable.

As prior art we considered Rust, ML and other managed GC languages such as Java
or C# that have similar simplified memory models.


# Unresolved questions

[unresolved-questions]: #unresolved-questions

The exact memory representation of values, by themselves or as part of a slice
is not fully addressed here. The ability to represent a series of bytes is a
hard requirement but how we do this and what specific types look like in memory
will have to be decided by the implementation.

How dynamic types interact with the ABI will have to be resolved in a later RFC.

# Future possibilities

[future-possibilities]: #future-possibilities

We could introduce a marker trait (like `Copy`) to make the distinction between value types
and references explicit through the type system. 

As previously discussed, we may consider eventually making reference returns
immutable by default, however this would have to go through multiple iterations
to make the qualifiers explicit and then reverse the implicit qualifification.

We may want to introduce a `*` operator that works over `__deref` and/or
allowing `Box` to use that operator.

We should consider introducing slicing and indexing operator such as `[0..n]`
and `[0]`. We needn't introduce the notion of a range yet to make those work.

As discussed, a natural extension of `*mut` is `*const`.
