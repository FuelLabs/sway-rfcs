- Feature Name: calling-context-attribute
- Start Date: 2022-07-06
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/9)
- Sway Issue: [FueLabs/sway#963](https://github.com/FuelLabs/sway/issues/963)

# Summary

[summary]: #summary

Sway will support an attribute (i.e. `#[context(internal_only)]`) to annotate the supported calling contexts for particular functions.

This annotation can then be used by the compiler to check and restrict the calling of these functions to a compatible calling context.

# Motivation

[motivation]: #motivation

The main goal is to be able to get compile-time safety when working with functions that should only be called from an internal (contract) context.

A real-world example of this is the [msg_amount() stdlib function](https://github.com/FuelLabs/sway-lib-std/blob/6a8f5bf588df5d0679fb834f05c900f2e54de426/src/context.sw#L33-L38) which only returns a proper value when used in an internal context. In an external context is returns a well-defined but not semantically representative value, specifically 0, as explained by @adlerjohn in [FueLabs/sway#963](https://github.com/FuelLabs/sway/issues/963).

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

A _calling context attribute_ is an attribute that can be used to annotate function items in Sway to restrict the context in which they can be called.

Take the following example:

```rust
contract;

#[context(internal_only)]
fn bar() {}

abi TestContract {
    fn foo();
}

impl TestContract for Contract {
    fn foo() {
      bar()
    }
}
```

The above code example shows a _calling context attribute_ annotating a function item, `fn bar()`, restricting it to be only called in `internal` contexts, or contract contexts.

Generally, Sway programmers should use this to annotate functions that are only applicable when being called from a contract, so the compiler can provide an error when they are misused.

This annotation is transitive, meaning it needs to be also specified through all functions
that call `internal_only` functions.


# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

Right now the current prototype implementation for this feature is using the same approach that was implemented for storage access attributes.

The attributes are parsed, and during type checking, we keep track of the current calling context for a particular type check context. Then during function and method applications, we can check if a particular function is missing a context attribute, and issue an error if that is the case.

Later, as we do for purity, once the entire program is type-checked, we perform an analysis to figure out which top-level declarations are being called from the wrong context and issue the corresponding compiler error.

The feature is pretty self-contained and doesn't affect any pre-existing code.

The only expected potential breaking changes are once the standard library code will take advantage of this, then user code will need to be annotated further up the call chain.

One thing to note is that is that functions that call an `internal_only` function needs themselves to be annotated as internal.

So for instance imagine the following library code:

```rust
#[context(internal_only)]
fn foo() {}

fn bar() {
  foo();
}
```

This will give a compile error, forcing the user to annotate `bar` with `#[context(internal_only)]` as well.

The only exception to this are contract-level functions which are themselves already internal.

# Drawbacks

[drawbacks]: #drawbacks

The only drawback that comes to mind is the additional complexity to the language.

But the extra safety guarantees provided by the feature should make up for it.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

We could go with an `internal_only` keyword I guess, but re-using attributes seems like a better approach since we are already using the same scheme for storage access.

# Prior art

[prior-art]: #prior-art

The obvious instance is Sway's very own storage attributes, which work used in a very similar manner, and from which the prototype implementation approach of this feature in the compiler was derived.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

1. Is the current naming (calling context attribute) for this feature OK or do you have a more semantically-correct suggestion?

2. Is `internal_only` the only calling context we want to support or can you think of some other we may want to support in the future?

3. Do we go with `internal_only` maybe or maybe use something else like `contract_only`?

4. Do we go with the current `context` attribute name, or should we name it `calling_context(internal_only)`, maybe even `restrict_context(internal)`, or something else?

# Future possibilities

[future-possibilities]: #future-possibilities

As asked above in the unresolved questions, are there any other contexts we may want to support in the future?