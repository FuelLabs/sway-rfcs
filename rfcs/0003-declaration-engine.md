- Feature Name: Declaration Engine
- Start Date: 2022-07-13
- RFC PR: [FuelLabs/sway-rfcs#0011](https://github.com/FuelLabs/sway-rfcs/pull/11)
- Sway Issue: [FueLabs/sway#1821](https://github.com/FuelLabs/sway/issues/1821), [FueLabs/sway#1692](https://github.com/FuelLabs/sway/issues/1692)

# Summary

[summary]: #summary

With it's current design, the Sway compiler faces challenges regarding how declarations interact with the type system and code generation. These include:
1. function bodies must be inlined during type checking ([FueLabs/sway#1557](https://github.com/FuelLabs/sway/issues/1557))
2. monomorphization of declarations is unnecessarily duplicated ([FueLabs/sway#862](https://github.com/FuelLabs/sway/issues/862))
3. it is currently impossible to implement `where` clauses without extensive special casing/dummy definitions ([FueLabs/sway#970](https://github.com/FuelLabs/sway/issues/970))

This RFC proposes a solution to this---the "declaration engine". The declaration engine is a redesign of how the compiler thinks about type checking of declarations, and seeks to solve the problems described above. At a high level, the declaration engine stores intermediate representations of potentially type-checked declarations and allows the compiler to refer to those intermediate representations during type checking.

# Motivation

[motivation]: #motivation

With the changes introduced by this RFC, the compiler will be able to think about declarations more abstractly and will not be required to inline AST nodes during type checking. In addition to solving the issues above, I believe that this change will create a mechanism in the compiler which will allow us to implement additional optimizations in the future.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

Because this is an internal compiler RFC, the affected group is the Sway compiler devs.

Specifically in the context of Sway terminology, the phrase "type checking" is often used to refer to the Sway compiler step in which untyped AST nodes are transformed to typed AST nodes. But really, the compier step we refer to "type checking" is actually doing type inference. This distinction is important because it allows us to understand the role of the declaration engine.

## Toy Example

(this is an elaborate explanation that most will already be profficient in---but it does build to a good point!)

For the purposes of illustration, imagine a new toy language that is statically and strongly typed, but allows for optional type annotations (like Sway and Rust). The toy compiler that we could write for this toy language would need to evaluate the types of objects at compile time to either correctly compile a program or fail to compile a program (like the Sway compiler and the Rust compiler). The toy compiler would have three broad-strokes steps (1) parsing, (2) type checking, and (3) code generation. Because the toy language allows for optional type annotations, after the parsing step, the toy compiler would know the types for either none, some, or all, of the objects in the program. To compensate for this, the toy compiler would perform type inference, where the types of untyped objects would be inferred from the types of typed objects. 

At it's most abstract, we can think of type inference as a constraint solving problem, where constraints are rules dictating how types relate to one another. The toy compiler cares very little about the _actual type_ of types (i.e. us as humans know that a `bool` means either `true` or `false`, or `on` or `off`, or "nod head" or "shake head", etc, but the compiler doesn't know that), and instead cares more about how the collection of types within the program relate to one other.

For example, imagine that our toy language includes variables and variable assignments. If we have a variable `x` of type `bool`, and then declare a different variable `y` and assign it to `x`, we can infer that `y` is of type `bool`.

But, this property is not exclusive to just `bool`s---variable assignment does not "work differently" for `bool`s than it does for `u64`s. Thus, we can make this example more abstract. If `x` is of type `T`, and we assign `y` to `x`, we can infer that `y` is of type `T`. Importantly, `T` could be any concrete type (`bool`, `u64`, etc), and that would not affect the type inference that we just made---no matter what `T` is, we still know that `y` is of type `T` because `x` is of type `T`.

But we take this one step furthur... when performing type inference, we don't even really need to know that `y` is type `T`, we simply only need to know that `y` _has the same type as `x`_. This is a constraint. The toy compiler can perform type inference for `y` by generating the constraint "`y` has the same type as `x`".

Now, imagine that the toy language includes if statements and the toy compiler encounters an if statement that uses `x` as the conditional. The toy compiler has this list of constraints:

1. `x` has type `T`
2. `y` has the same type as `x`

But when `x` is used as the conditional in an if statement, we can add an additional constraint:

3. the type of `x` is `bool`

With these three constraints, the toy compiler is able to perform constraint solving (unifying the constraints with unification) to determine that both `x` and `y` are of type `bool`.

Now, imagine that the toy language includes addition expressions and the toy compiler encounters an addition expression `y + 1u64`. This would generate the constraint:

4. `y` has type `u64`

With these four constraints, the toy compiler is unable to perform unification, as the constraints are unable to be unified and generate a type error.

We can see that the toy compiler would be able to perform type inference for a whole program by generating a list of constraints and then unifying these constraints.

(Type inference, constraint solving, and unification are defined here: https://papl.cs.brown.edu/2014/Type_Inference.html)

## Declaration Engine

The declaration engine takes the concept of constraints and unification and applies it to declarations.

For example, when type checking a function application, the compiler does not need to care about the contents of the body of the function, instead it is sufficient to create a constraint referring to "the return type of the function".

For example, given a typed function declaration `add`, we add this declaration to the declaration engine. Then when type checking a function application of `add`, instead of inlining the function body, we create constraints referring to "the body of `add`" and "the return type of `add`". When type checking a _function application_

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

I believe that the only drawbacks are developer time and implementation complexity.

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
