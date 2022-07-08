- Feature Name: docstrings
- Start Date: 2022-06-27
- RFC PR: [FuelLabs/sway-rfcs#0002](https://github.com/FuelLabs/sway-rfcs/pull/2)
- Sway Issue: [FueLabs/sway#149](https://github.com/FuelLabs/Sway/issues/149)

# Summary

[summary]: #summary

Sway will convert Rust-style docstrings (`///`-style comments) into a `#[doc("documentation string")]` annotation. This annotation can then be consumed by tooling and plugins to produce
rendered documentation, a la `cargo doc` or `docs.rs`.

# Motivation

[motivation]: #motivation

As Sway's designs are largely motivated by Rust's design, we have always wanted to support in-code documentation in this manner. In-code documentation support has been part of the Sway vision
since the beginning.

This particular approach is both low-friction, in that it utilizes our existing features (annotations, comments, forc plugins); and consistent with Rust's implementation of docstrings. Upon
the implementation of this RFC in Sway, forc plugins should be able to produce documentation and documentation-related tooling based on in-code docstrings.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

A _docstring_ is a line of prose within a Sway source code file. This plain-language string serves to provide exposition and contextual explanation to the subsequent line of Sway code.

Docstrings, for convenience, may be written as a comment with three slashes. E.g.:

```rust
/// The entry point to the script.
fn main() {}
```

The above code example shows a _docstring_ documenting a function item, `fn main()`.

Generally, Sway programmers should find this to be the most expedient and convenient way to provide API documentation for libraries and contract ABIs, and documentation of internal concepts within scripts and predicates.

This style of docstring should be familiar to Rust programmers, and the concept of docstrings is generally prevalent in modern programming languages and should not require significant explanation or new educational material.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

Docstrings should be implemented as attributes (a.k.a. annotations) ([reference 1](https://github.com/FuelLabs/sway/issues/470), [reference 2](https://github.com/FuelLabs/sway/pull/1518), [reference 3 (rust)](https://doc.rust-lang.org/reference/attributes.html)). Because annotations/attributes can be applied to any `Item` in Sway ([reference 1](https://github.com/FuelLabs/sway/blob/master/sway-parse/src/attribute.rs#L4), [reference 2](https://github.com/FuelLabs/sway/blob/ba30e8e5ccbb0512aacbaee594473da9e0839c3d/sway-parse/src/item/mod.rs#L13)), this means that any `Item` can be documented with this feature.

A docstring of the format `/// this is a docstring` should be converted to an attribute of the format `#[doc("this is a docstring")]`. This may require work in the attribute parser to support strings as attribute contents, although that is unclear at this moment. It is also possible the attribute system can currently handle this.


# Drawbacks

[drawbacks]: #drawbacks

There are no foreseeable drawbacks.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

In the space of possible docstring designs, this is the most consistent with Rust and also very ergonomic. Additionally, a good chunk of Sway code has already been written with the assumption that this docstring format will be accepted. Therefore, there are already many docstrings written in this way.

Other designs could include just the attribute without the three-slash-comment-based syntactic sugar, ML-family-style docstrings `{- docstring -}`, or multiline-style:

```
/**
 * Multiline style docstring.
 *
 */
```

The proposed style is, however, most consistent with our design principles. If we were to leave docstrings unimplemented, we would be missing a core part of the Sway product and would
have no canonical method of in-code documentation.


# Prior art

[prior-art]: #prior-art

The obvious instance is Rust's docstrings. [Read more about that here](https://doc.rust-lang.org/rust-by-example/meta/doc.html).

Additionally, many other languages have docstrings either via third party tooling or via native support:

1. Javascript (`/**`-style)
2. Haskell (`{-`-style)
3. C# (`///` or `/**`)
4. Ocaml (`(**`-style)

And many, many more. Native docstring support is generally loved by language communities and is critical to having a consistent documentation experience across the language ecosystem.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

1. Is the current annotations system robust enough to support this?

# Future possibilities

[future-possibilities]: #future-possibilities

Eventually, we'd like to support things like upwards-associating docstrings (`//!` in Rust) and docstring code tests, where code snippets within docstrings are included in a test suite. These are not necessary for an initial docstring implementation, though.
