- Feature Name: private_modules
- Start Date: 2023-04-05
- RFC PR: [FuelLabs/sway-rfcs#0007](https://github.com/FuelLabs/sway-rfcs/pull/25)
- Sway Issue: [FueLabs/sway#4446](https://github.com/FuelLabs/sway/issues/4446)

# Summary

[summary]: #summary

This RFC proposes introducing two changes.

First, instead of exposing the entire module structure by default and
modulating the privacy of elements globally and one by one, this RFC proposes
to make all modules private by default and only allow importing symbols
externally if they have explicitly been made public, including submodules.

Second, and to make the former change easier to deal with, we seek to introduce
public reexports with the `pub use` syntax.

# Motivation

[motivation]: #motivation

This is a follow up to our previous change in the definition of the module
structure, and the aim is to further clarify and make deliberate the module
structure of Sway packages.

This pair of features will help prevent leaky
abstractions by hiding the implementation details of a module by default. It will help
Sway programmers to design clear and deliberate library APIs that are not bound
by the specifics of an implementation.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

## Visibility and Privacy

Sway's symbol name resolution operates on a global hierarchy of namespaces.
To control whether a symbol can be used in the context of a module we check if
each use can be allowed or not, and if not produce an error.

**By default everything is private.** There are two exceptions to this:

* Associated items of a public trait are public by default
* Enum variants of a public enum are public by default

When an item is marked with `pub`, it is made public. It is public in the sense
that it is accessible to the outside world.


We allow item access in two cases:

* if an item is public, then it can be accessed outside of a module `m` if you
can access all the item's ancestor modules from `m`. You may also be able to
name the item through reexports.
* if an item is private, then it can be accessed by the current module and
its descendants.

## Reexports

We allow publicly reexporting items using the `pub use` syntax. This allo the
item to be imported according to the visibility rules above as if it were
declared where the reexport is stated. It also brings the item to the scoped
context the same way a regular `use` would.

## Example

Here's a small Sway library that combines all these concepts.

`lib.sw`
```sway
library;

// this module will be accessible outside the library
pub mod alpha;
// this module will not be accessible outside the library
mod beta;

fn baz() {
    ::alpha::foo();

    // Error: ::alpha::bar is private
    // ::alpha::bar();

    ::beta::foo();

    // Error: ::beta::bar is private
    // ::beta::bar();

    // Error: ::beta::gamma is private
    // ::beta::gamma::foo();

    // Error: ::beta::gamma is private
    // ::beta::gamma::bar();

    ::beta::gamma_foo();
    
}

fn main() { baz() }  
```

`alpha.sw`
```sway
library;

pub fn foo() {}
fn bar() {}
```

`beta.sw`
```sway
library;

mod gamma;

pub use gamma::foo as gamma_foo;
// Error: gamma::bar is private
// pub use gamma::bar as gamma_bar;

pub fn foo() {}
fn bar() {}
```

`beta/gamma.sw`
```sway
library;

pub fn foo() {}
fn bar() {}
````

## Migration

This is of course a breaking change. Existing codebases can replicate the
current behavior by replacing all their instances of `mod` by `pub mod`.
However it is also a good opportunity to think about the API design of
a codebase and only publicize what is required.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

We'll need to add the optional `pub` qualifier to both import statements and
module declarations.

Internally, this change will require a more complex handling of `Visibility` in
import handling and when we resolve call paths. We will need to validate the
visibility of all elements of a path.

This may require adding module declarations to the declaration engine because
we will need to hold the visibility of modules. This would also be helpful if
we want to later allow importing and reexporting modules themselves.

We should also give specific consideration to imports of enum variants and
trait associated items.

As for reexports, they should be straightforward to implement as a specific
behavior of type checking `AstNodeContent::UseStatement` with or without a
special `TyDecl` variant.

# Drawbacks

[drawbacks]: #drawbacks

This is yet another breaking change that will require a lot of edits from Sway
programmers (if trivial ones). We may want to reconsider if we don't
care to hold to Rust's private by default idiom, though it is probably in our
best interest to do such a drastic change as early as possible if we want to do
it all.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

These simple rules are a powerful and battle tested way of creating module
hierarchies that hide implementation details.
They are also what programmers coming from Rust would expect.

Not changing this default would make it difficult to hide the implementation
details of a Sway library or provide a specific interface.
And the longer we wait, the harder it will be to make this change if we want to.

# Prior art

[prior-art]: #prior-art

Once again, Rust's privacy rules and the long history of modular programming
languages are the prior art we take cues from.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

This RFC does not propose to allow importing modules by themselves (i.e.: `use foo;`
for a `mod foo;`), although it should be taken in consideration as a
possible extension by the implementation.

One thing the implementation may want to consider is an optimized or cached way
of doing visibility checks for paths as enforcing the new rules will be of a
higher order of complexity than a single declaration check.

# Future possibilities

[future-possibilities]: #future-possibilities

As mentioned, allowing module imports is a possible extension.

Another natural extension is to allow qualifiers to `pub` the same way
that Rust does to allow for more fine grained control of privacy similar to
`pub(crate)`, `pub(self)`, etc.
