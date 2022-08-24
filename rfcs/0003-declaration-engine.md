- Feature Name: Declaration Engine
- Start Date: 2022-07-13
- RFC PR: [FuelLabs/sway-rfcs#0011](https://github.com/FuelLabs/sway-rfcs/pull/11)
- Sway Issue: [FueLabs/sway#1821](https://github.com/FuelLabs/sway/issues/1821), [FueLabs/sway#1692](https://github.com/FuelLabs/sway/issues/1692)

# Summary

[summary]: #summary

With its current design, the Sway compiler faces challenges regarding how declarations interact with the type system and code generation. These include:
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

Specifically in the context of Sway terminology, the phrase "type checking" is often used to refer to the Sway compiler step in which untyped AST nodes are transformed to typed AST nodes. But really, the compiler step we refer to "type checking" is actually doing type inference. This distinction is important because it allows us to understand the role of the declaration engine.

## Background Information: Sway's Type Inference

(this is an elaborate explanation that most will already be proficient in---but it does build to a good point!)

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

For example, given a typed function declaration `add`, we add this declaration to the declaration engine. Then when type checking a function application of `add`, instead of inlining the function body, we create constraints referring to "the body of `add`" and "the return type of `add`". When type checking a _function application_.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This design will take after the design of the [type engine](https://github.com/FuelLabs/sway/blob/2816c13698a35752136d4843dbfe5e1b95c26e10/sway-core/src/type_engine/engine.rs#L14). During type checking, the compiler will add information about declarations to the declaration engine. Then, in places where that declaration is used, a value representing that declaration can be generated in place of inlining the declaration.

### Definition

During type checking of a declaration, the compiler will add information about that declaration to the declaration engine:

```rust
struct DeclarationEngine {
    // function name to typed function declaration
    // this example code does not consider Paths, but we could use
    // a BTreeMap with Paths as the key
    functions: HashMap<String, TypedFunctionDeclaration>,

    // struct name to typed struct declaration
    // again, this does not consider Paths
    structs: HashMap<String, TypedStructDeclaration>,

    // enums and traits
}

impl DeclarationEngine {
    fn add_function(&mut self, function: TypedFunctionDeclaration) -> DeclarationDefinition {
        // add to self and return DeclarationDefinition
    }

    fn add_struct(&mut self, r#struct: TypedStructDeclaration) -> DeclarationDefinition {
        // add to self and return DeclarationDefinition
    },

    // enums and traits
}

enum DeclarationDefinition {
    // does not consider Paths
    Function(String),

    // does not consider Paths
    Struct(String),

    // enums and traits
}
```

Then in the typed AST, those declarations could look like (in pseudocode):

```rust
contract;

/// imports

DeclarationDefinition::Function(<function name>)
DeclarationDefinition::Struct(<struct name>)

/// storage declaration

DeclarationDefinition::Function("main")

```

Because inlining is still needed for the IR, these instances of `DeclarationDefinition` would be replaced in an additional step at the end of type checking called the [resolution step](https://github.com/FuelLabs/sway/issues/1820).

### Usage

When a declaration is referred to, a reference to the existence of a possible declaration in the declaration engine is generated. That is resolved during the resolution step. Given:

```rust
fn add(x: u64, y: u64) -> u64 {
    ..
}
```

The `TypedFunctionDeclaration` for `add` is added to the declaration engine. Then given:

```rust
let foo = add(1, 2);
```

`foo` will be a `TypedExpression` with a [`TypedExpressionVariant::FunctionApplication`](https://github.com/FuelLabs/sway/blob/dcaee960df9b3466c6897d0a86ea806c9abf7edd/sway-core/src/semantic_analysis/ast_node/expression/typed_expression_variant.rs#L18), where instead of storing the entire `TypedFunctionDeclaration` in the `TypedExpressionVariant::FunctionApplication` variant, there is a reference created `Function("add", vec![u64, u64])` which is stored [here](https://github.com/FuelLabs/sway/blob/dcaee960df9b3466c6897d0a86ea806c9abf7edd/sway-core/src/semantic_analysis/ast_node/expression/typed_expression_variant.rs#L23). The type of `foo` is some new `TypeInfo::ReturnType("add", vec![u64, u64])`. Both the reference `Function("add", vec![u64, u64])` and `TypeInfo::ReturnType("add", vec![u64, u64])` are resolved during the resolution step.

Importantly, introducing the declartion engine in this way means that during type checking before the resolution step, the references introduced during usages of declarations are assumptions. There is no check happening to ensure that `add` exists when creating `Function("add", vec!(u64, u64))`. The check to see if something exists happens in the resolution step. Once the _collection context_ is introduced, the concept of checking to see if things exist can happen earlier in compilation, even before type checking begins at all, if we wanted to do so.

# Drawbacks

[drawbacks]: #drawbacks

I believe that the only drawbacks are developer time and implementation complexity.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

I feel that this design offers the best compromise between current state and future growth. The concept of a "declaration engine" in general is very broad, which is a good thing! The design in this RFC is a good one to get us started, but I imagine that as the language progresses, it's needs and use cases for the declaration engine will expand and change. Introducing the declaration engine now gives us the opportunity to create a mechanism through which some of those changes could be introduced later down the road.

That being said, from a high-level perspective, the alternative design would be something similar to what we are doing now, which is more focused on inlining things.

# Prior art

[prior-art]: #prior-art

Well, I'm actually not sure. Off the top of my head, at a high-level there are languages that do not inline functions and instead use function tables, for instance. In those languages, I'm really not sure if this is done via a "declaration engine" or not. This RFC will not allow us to avoid inlining functions (we are still doing it in the IR), but it is a first step.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

I'd really like to get feedback on the fine-level details of the initial implementation that I described above. I can provide additional information or context if that is helpful too.

# Future possibilities

[future-possibilities]: #future-possibilities

This RFC preceeds an RFC introducing a collection context.
