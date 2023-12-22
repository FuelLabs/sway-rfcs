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
the entire lifetime of the execution. In Rust terms, every dynamic value has a
lifetime of `'static`.

This allows us to do away with some complexity and handle values more like they
would be in Java or ML.
In most cases, you shouldn't need to use explicit pointer types.

## Data types

In Sway there are two types of data types. Built-in types and compound types.

Built-in types include `u8`, `u16`, `u32`, `u64`, and pointers such as `*mut u8`.
Compound types are arrays, structs, tuples, and enums.

Both built-in and compound types live for the lifetime of the function they are declared in.
They are passed and returned by value, which means their value is directly copied.

Internally, access to compound types (also called aggregates within the compiler) is
realized via pointer to a memory region. That's why those types are internally called
reference types. Note that from the Sway programmer's perspective, they still have value semantics.

There are two kinds of such internal references. Slim and fat.

Slim references are implemented using a single address. Slim references
include structs, enums, and arrays, such as `String`, `Option`, `[u8; 42]`.

Fat references are implemented using an address and a small amount of additional
data, either a length or a pointer to a more complex table. Fat references
include slices, such as `[u8]`, `str`.

## References

References mentioned above are an internal compiler construct, but from the programmer's
perspective still regular value types, copied in assignments, and passed and returned by value.

From the programmer's perspective, it is sometimes desirable to have a reference to a value type,
such as for passing a mutable reference to value to a function or declaring a recursive data type.

This can be achieved with the new language construct, _references_.

References to values can be obtained by the reference operator &.
References have their own mutability and can point to mutable or immutable values.
Thus, we support mutable references to mutable values and any combination of the two.

The below example shows how a reference can be declared.

```sway
let mut m_i = 0u64;
let r_m_i = &mut m_i; // Immutable reference to a mutable `m_i`.
let mut m_r_m_i = &mut m_i; // Mutable reference to a mutable `m_i`.
let r_m_i = &m_i; // Immutable reference to an immutable (via reference) `m_i`.
let mut r_m_i = &m_i; // Mutable reference to an immutable (via reference) `m_i`.

let i = 0u64;
let r_m_i = &mut i; // ERROR: `i` is not mutable.
```

The dereference operator * is used to access the referenced value.
In addition, if the reference refers to a compound type, the operators . and [] automatically dereference.

```sway
let mut r_i = &i; // Mutable reference to immutable a `u64`: r_i: &u64.
let mut r_m_i = &mut m_i; // Mutable reference to a mutable `u64`: r_i: &mut u64.

*r_i = 1; // ERROR: Referenced value is not mutable.
r_1 = &x; // OK: `r_1` is mutable.

*r_m_i = 1; // OK: Changes `m_i`.
r_m_i = &x; // OK: `r_m_i` is mutable.

// Accessing built-in types and enums over reference via dereferencing operator (*).
let a = 2 * *r_i; 

let mut s = Struct { x: 0u64 };
let r_s = &mut s; // `r_s` is immutable reference to a mutable struct.

r_s.x = 1; // Same as `(*r_s).x = 1`.
```

Here, we are listing the major properties of references:
- References have their own mutability and can point to mutable or immutable values.
- & operator defines the reference. * operator is dereferencing.
- . and [] operators also dereference if the reference is a reference to a struct/tuple or array, respectively.
- References can be parts of aggregates.
- References can reference other references.
- References can be used in pattern matching and deconstructing.
- References can reference parts of aggregates. E.g., having a reference to an array element.
- References can be passed to and returned from functions.
- References will play well with iterators and the `for` loop, once implemented.
- References can be used together with generics.
- References can be taken from arbitrary expressions, including constants and literals.
- References can be used in type aliases.
- `self` keyword will become a reference, and us such comply to the reference passing syntax.
- References cannot be used in storage.
- References cannot be used in ABIs and `main` functions.
- Equality of references is the equality of the values they refer to if the underlying type implements `std::ops::Eq`.
- `__addr_of` called on a reference returns the address the reference points to.

For detailed examples of syntax and semantics see the accompanied file [0010-references.sw](../files/0010-references.sw).

## Pointers

There are cases where one may want to directly manipulate memory addresses with pointer arithmetic,
to allow for this we have a pointer type that represents a single address: `*mut T` where `T` is the type being pointed to.

Pointers can be obtained by using the `__addr_of` intrinsic on a reference and dereferenced using the `__deref` intrinsic, like so:

```sway
let val: u64 = 1;
let ptr: *mut u64 = __addr_of(&val);
let ptr_val: u64 = __deref(ptr);
assert_eq(val, ptr_val);

let ref: &u64 = &1;
let ptr: *mut &u64 = __addr_of(&ref);
let ptr_val: &u64 = __deref(ptr);
assert_eq(ref, ptr_val); // Equality of references is the equality of referenced values.

let ref: &u64 = &1;
let ptr: *mut u64 = __addr_of(ref); // Returns the address od the referenced value.
let ptr_val: u64 = __deref(ptr);
assert_eq(ref, &ptr_val); // Equality of references is the equality of referenced values.
```

Dereferencing an invalid pointer is Undefined Behavior.

## Slices

Slices represent contiguous areas of dynamic memory.
They can be used to represent dynamically sized data.
Slices are represented by a pair containing a pointer to the data and a length.

String slices, of type `str` represent a series of bytes, encoding a valid UTF-8 string.
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
specified indices. This slicing is bounds-checked and will produce a revert if
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
immutable which is denoted by the `mut` prefix before the argument name.

Mutable value type arguments can be reassigned.

Mutable reference arguments can both be reassigned and have their fields
assigned to, depending on the declaration of the reference.

```sway
fn foo(
    ref: &u32, // Immutable reference to immutable value.
    mut m_ref: &u32, // Mutable reference to immutable value.
    mut m_ref_m: &mut u32, // Mutable reference to a mutable value.
    val: u32 // Immutable value passed by-value.
    mut m_val: u32, // Mutable value passed by-value.
) {
    *ref = 0; // ERROR: The referenced value is immutable.
    ref = &0; // ERROR: The reference `ref` is immutable.

    *m_ref = 0; // ERROR: The referenced value is immutable.
    m_ref = &0; // OK: The reference `m_ref` is mutable.

    *m_ref_m = 0; // OK: The referenced value is mutable.
    m_ref_m = &0; // OK: The reference `m_ref_m` is mutable.

    val = 0; // ERROR: `val` is immutable.

    m_val = 0; // OK: `m_val` is mutable.
}
```

For more detailed examples see the section _Passing and returning references from functions_ in the accompanied file [0010-references.sw](../files/0010-references.sw).

## Returning values

When returning values from functions, copies are returned, as per the by-value semantics of all Sway types.

When returning references, the mutability of the referenced value can be explicitly specified.

```sway
fn foo() -> &u32 { // Returns a reference to an immutable `u32`.
    &0
}

fn bar() -> &mut u32 { // Returns a reference to a mutable `u32`.
    &0
}


pub fn main() {
    let r_foo = foo();
    *r_foo = 1; // ERROR: `r_foo` is a reference to immutable value.

    let r_bar = bar();
    *r_bar = 1; // OK: `r_bar` is a reference to mutable value.

    let mut m_r_foo = foo();
    m_r_foo = &1; // OK: `m_r_foo` is a mutable reference to immutable value.

    let mut r_bar = bar();
    m_r_bar = &1; // OK: `m_r_bar` is a mutable reference to mutable value.
}

```

For more detailed examples see the section _Passing and returning references from functions_ in the accompanied file [0010-references.sw](../files/0010-references.sw).


## Methods

Methods definitions use `self` to refer to the value the method is being called
on, this follows the same rules defined for functions, except of course `self`
can't be reassigned.

```sway
struct S {
    a: u32,
}

impl S {
    pub fn foo(&self) {
      // illegal since self is immutable
      // self.a = 0;
    }
    pub fn foo(&mut self) {
      // legal since self is mutable
        self.a = 0;
    }
}

```

For more detailed examples see the section _`self` keyword_ in the accompanied file [0010-references.sw](../files/0010-references.sw).


## Migration

Existing codebases can adapt to this change by changing every occurrence of `ref
mut` to `&mut` and every use of `raw_slice` and `raw_ptr` to uses of references, typed
pointer and slice types.

In general, switching untyped pointers to a properly typed reference, even a generic
`&T`, is preferred. Pointers for whom the pointee isn't a value that can be
named may need to use `&()` or `*mut ()`, the former is preferred.

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

Implementing the new reference construct should require:

* parser changes to introduce the new syntax
* adding the new types to the type system
* implementing the heap allocation for types
* implementing a simple escape analysis that avoids heap allocation if there are no references in code

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

Abstracting away memory management too much might be a drawback for Sway and its
positioning as a smart-contract language. However maintaining access to pointer
arithmetic should still allow for atypical usage patterns without compromising
the use of safe and zero cost abstractions for most cases.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

To make the use of references more explicit and maintain syntax legibility for
people coming from Rust we have chosen to use `&` everywhere a reference
is used. However the reason for Rust's use of this syntax rather than ML's
terseness is to support a borrow checker and guarantees that we do not make.
This could be misleading at first for programers coming from Rust. We will properly
document the difference between Sway references and Rust borrowing.
We believe that the difference, properly presented, will be straightforward and
easy to understand. Apart from that, the chosen syntax should feel natural for
programers coming from Rust.

Since we're leaning more towards ML, we may also have chosen to use `ref`
to denote reference types. However we already majorly borrow
from Rust for our library abstractions. Moreover, the `ref` syntax felt much verbose.

# Prior art

[prior-art]: #prior-art

A lot of the design choices of this RFC have to do with striking the balance
between Rust and ML's levels of abstraction. Sway is not meant to be a general
purpose systems programming language, but it is not a functional memory managed
language either. We want to maintain access to memory primitives whilst making
most Sway code terse, legible and easily understandable.

As prior art we considered Rust, ML and other managed GC languages such as Java
or C# that have similar simplified memory models. For the parts of the references
semantics we borrow from C++.


# Unresolved questions

[unresolved-questions]: #unresolved-questions

The exact memory representation of values, by themselves or as part of a slice
is not fully addressed here. The ability to represent a series of bytes is a
hard requirement but how we do this and what specific types look like in memory
will have to be decided by the implementation.

How dynamic types interact with the ABI will have to be resolved in a later RFC.

# Future possibilities

[future-possibilities]: #future-possibilities

We should consider introducing slicing and indexing operator such as `[0..n]`
and `[0]`. We needn't introduce the notion of a range yet to make those work.

As discussed, a natural extension of `*mut` is `*const`.
