- Feature Name: (fill me in with a unique ident, `my_awesome_feature`)
- Start Date: (fill me in with today's date, YYYY-MM-DD)
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC aims to make the paradigm for handling reference types clear and to eliminate redundant concepts.

# Motivation

[motivation]: #motivation

There currently exists a cludge of features on top of heap pointers that have various levels of type correctness, offer various paradigms and have less than coherent syntax.

We want to clarify the rules for passing heap data to and from functions, how they are expressed in the type system and through syntax, and eliminate untyped values such as `raw_ptr` and `raw_slice`.


# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

Unlike Rust, Sway does not manage lifetimes. Due to the nature of smart contract
execution, heap memory usage only grows and allocated memory is allocated for
the entire lifetime of the execution. In Rust terms, every reference value has a
lifetype of `'static'`.

This allows us to do away with some complexity and handle values more like they
would be in Java or ML. As in those languages, there are no explicit pointer
types in Sway, because every value is either a primitive type or a pointer.

## Data types

In Sway there are two types of data types. Primitives and References.

Primitives are allocated on the stack. They live for the lifetime of the function they are declared in. 
They are passed and returned by value, which means their value is directly copied.
Primitives include `u8`, `u16`, `u32`, `u64`, and tuples such as `()`, `(u8, u64)`.

References are allocated on the heap and represented on the stack by a pointer to the heap.
They are passed and returned by reference, which means the pointer is copied and still points to the same heap data.

There are two kinds of references. Slim and fat.

Slim references are implemented using a single 8 byte address.
Slim references include structs, enums and arrays, such as `String`, `Option`, `[u8; 42]`.

Fat references are implemented using an 8 byte address and 8 bytes of additional data, either a length or a pointer to a more complex table.
Fat references include slices, such as `[u8]`, `str`.

## Box

It is sometimes desirable to have a reference to a primitive type, such as for passing a mutable reference to it to a function.
This can be achieved with the `Box` struct, which is so defined:

```sway
pub struct Box<T> {
  contents: T
}
```

and produces the desired memory representation.


## Slices

Slices represent contigous areas of heap memory.
They can be used to represent dynamically sized data.

To obtain a slice, one can either use a string literal, which returns a `str`:
```sway
let _: str = "Lorem Ipsum";
````

or convert from an array:


* explain removal of special behavior for wrapper types over ptr/slices


## Methods

## Passing values

## Returning values




Explain the proposal as if it was already included in the language and you were teaching it to another Sway programmer. That generally means:

- Introducing new named concepts.
- Explaining the feature largely in terms of examples.
- Explaining how Sway programmers should *think* about the feature, and how it should impact the way they use Sway. It should explain the impact as concretely as possible.
- If applicable, provide sample error messages, deprecation warnings, or migration guidance.
- If applicable, describe the differences between teaching this to existing Sway programmers and new Sway programmers.
- If this change is breaking, discuss how existing codebases can adapt to this change.

For implementation-oriented RFCs (e.g. for compiler internals), this section should focus on how compiler contributors should think about the change, and give examples of its concrete impact. For policy RFCs, this section should provide an example-driven introduction to the policy, and explain its impact in concrete terms.

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


* Copy trait for the distinction between primitive and complex types
* how to handle const-ness of returns
* consider using `ref` as a shorthand for `Box`




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
