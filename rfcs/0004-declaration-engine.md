- Feature Name: `declaration_engine`
- Start Date: 2022-07-13
- RFC PR: [FuelLabs/sway-rfcs#0011](https://github.com/FuelLabs/sway-rfcs/pull/11)
- Sway Issue: [FueLabs/sway#1821](https://github.com/FuelLabs/sway/issues/1821), [FueLabs/sway#1692](https://github.com/FuelLabs/sway/issues/1692)

# Summary

[summary]: #summary

With its current design, the Sway compiler faces challenges regarding how declarations interact with the type system and code generation. These include:
1. it is currently impossible to implement trait constraints without extensive special casing/dummy definitions ([FueLabs/sway#970](https://github.com/FuelLabs/sway/issues/970))
2. function bodies must be inlined during type checking ([FueLabs/sway#1557](https://github.com/FuelLabs/sway/issues/1557))
3. monomorphization of declarations is unnecessarily duplicated ([FueLabs/sway#862](https://github.com/FuelLabs/sway/issues/862))

This RFC proposes a solution to this---the "declaration engine". The declaration engine is a redesign of how the compiler thinks about type checking of declarations, and seeks to solve the problems described above. At a high level, the declaration engine stores typed declarations and allows the compiler to reference those typed declarations during type checking, in a more abstract way.

[*prototype system*](https://github.com/emilyaherbert/declaration-engine-and-collection-context-demo/tree/master/de)

**Note:**

This RFC does not include plans to target out of order declarations and dependencies or recursive data structures and functions. This is intentional, as it requires the introduction of the collection context 'on top' of the declaration engine, and I feel that adding the declaration engine first would allow other devs to start working on trait constraints, etc. See the [future possibilities](#future-possibilities) for more details on this (and a preview of the design that I'm thinking about).

# Motivation

[motivation]: #motivation

With the changes introduced by this RFC, the compiler will be able to think about declarations more abstractly and will not be required to inline AST nodes during type checking. In addition to solving the issues above, I believe that this change will create a mechanism in the compiler which will allow us to implement additional optimizations in the future.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

This is probably best explained through some examples.

## Trait Constraints ([FueLabs/sway#970](https://github.com/FuelLabs/sway/issues/970))

Adding trait constraints to the compiler is the primary motivation for adding the declaration engine.

Take this (currently does not compile) Sway code that uses trait constraints as an example:

```rust
script;

trait Eq {
    fn eq(self, other: Self) -> bool;
}

enum Either<L, R> {
    Left(L),
    Right(R)
}

impl<L, R> Eq for Either<L, R> where L: Eq, R: Eq {
    fn eq(self, other: Self) -> bool {
        match (self, other) {
            (Either::Left(a), Either::Left(b)) => a.eq(b),
            (Either::Right(a), Either::Right(b)) => a.eq(b),
            _ => false
        }
    }
}

fn main() -> bool {
    let foo = Either::Left::<u64, bool>(0u64);
    let bar = Either::Right::<u64, bool>(false);
    foo == bar
}
```

The need for a declaration engine comes from the fact that currently, it is intractable to add trait constraints to the compiler. Currently, when type checking a method application, the method declaration for that method is inlined into the expression node of the method application itself. In the case where the 'parent' for that method (in the `a.eq(b)` example, `a` is the parent) is a generic type, it becomes intractable to inline the method declaration, because the compiler does not know what the method declaration is yet, because the type is generic! The method declaration could be from any `impl` block that implements the trait associated with the method (in this example `Eq`).

## Recursive Functions ([FueLabs/sway#1557](https://github.com/FuelLabs/sway/issues/1557))

The intractability of inlining declarations can also be seen in the case of recursive functions. There are a handful of different reasons as to why the Sway compiler is currently unable to support recursive functions, and one of them is infinite computation and infinite code size, resulting from this problem.

Take this simple example:

```rust
script;

fn zero_to_n(n: u8) -> u8 {
    if n == 0 {
        0
    } else {
        n + zero_to_n(n-1)
    }
}

fn main() -> u8 {
    zero_to_n(100)
}
```

This code size and computation would explode infinitely without use of the declaration engine.

## Monomorphization Optimizations ([FueLabs/sway#862](https://github.com/FuelLabs/sway/issues/862))

Currently, the compiler performs one iteration of monomorphization per "use" of a declaration. A "use" of a declaration includes function applications, method applications, struct expressions, and enum expressions. But, as you can imagine, this leads to quite a bit of repeated computation. By adding the declaration engine, this gives us the opportunity to introduce a cache system to reduce the number of monomorphizations.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

This design will take after the design of the [type engine](https://github.com/FuelLabs/sway/blob/2816c13698a35752136d4843dbfe5e1b95c26e10/sway-core/src/type_engine/engine.rs#L14). During type checking, the compiler will add the typed declarations to the declaration engine. Then, in places where that declaration is used, a value representing that declaration can be generated in place of inlining the declaration.

### Declarations

During type checking of a declaration, the compiler inserts the typed declaration to the declaration engine:

```rust
struct DeclarationId(usize);

enum DeclarationWrapper {
    Function(TypedFunctionDeclaration),
    Trait(TypedTraitDeclaration),
    TraitFn(TypedTraitFn),
    TraitImpl(TypedTraitImpl),
    Struct(TypedStructDeclaration),
}

struct DeclarationEngine {
    slab: ConcurrentSlab<DeclarationId, DeclarationWrapper>,
    // *declaration_id -> vec of monomorphized copies
    // where the declaration_id is the original declaration
    monomorphized_copies: LinkedHashMap<usize, Vec<DeclarationId>>,
}

impl DeclarationEngine {
    fn look_up_decl_id(&self, index: DeclarationId) -> DeclarationWrapper {
        self.slab.get(index)
    }

    fn add_monomorphized_copy(
        &mut self,
        original_id: DeclarationId,
        new_id: DeclarationId,
    ) {
        match self.monomorphized_copies.get_mut(&*original_id) {
            Some(prev) => {
                prev.push(new_id);
            }
            None => {
                self.monomorphized_copies.insert(*original_id, vec![new_id]);
            }
        }
    }

    fn insert_function(&self, function: TypedFunctionDeclaration) -> DeclarationId {
        self.slab.insert(DeclarationWrapper::Function(function))
    }

    fn get_function(
        &self,
        index: DeclarationId,
    ) -> Result<TypedFunctionDeclaration, String> {
        self.slab.get(index).expect_function()
    }

    fn add_monomorphized_function_copy(
        &mut self,
        original_id: DeclarationId,
        new_copy: TypedFunctionDeclaration,
    ) {
        let new_id = self.slab.insert(DeclarationWrapper::Function(new_copy));
        self.add_monomorphized_copy(original_id, new_id)
    }

    fn get_monomorphized_function_copies(
        &self,
        original_id: DeclarationId,
    ) -> Result<Vec<TypedFunctionDeclaration>, String> {
        self.get_monomorphized_copies(original_id)
            .into_iter()
            .map(|x| x.expect_function())
            .collect::<Result<_, _>>()
    }

    // omit equivalent methods for structs, enums, traits, etc
}
```

Then in the typed AST, those declaration nodes look like:

```rust
contract;

// imports

TypedDeclaration::Function(<unique DeclarationId>)
// omit equivalents for structs, enums, traits, etc

// storage declaration

TypedDeclaration::Function(<unique DeclarationId>) // "main" function
```

### Usages

When type checking an expression that references a declaration the compiler uses the unique `DeclarationId` that corresponds with the relevant declaration. For example, in a function application, the compiler uses the unique `DeclarationId` for the corresponding function declaration to retrieve the function declaration, apply monomorphization, perform any necessary type unification, and then access the function's return type to apply to the expression.

Function application becomes:

```rust
enum TypedExpressionVariant {
    FunctionApplication {
        call_path: CallPath,
        declaration_id: DeclarationId,
        arguments: Vec<(Ident, TypedExpression)>,
        // omitting other fields
    },
    // omitting other variants
}
```

# Drawbacks

[drawbacks]: #drawbacks

I believe that the only drawbacks are developer time and implementation complexity.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

I feel that this design offers the best compromise between current state and future growth. The concept of a "declaration engine" in general is very broad, which is a good thing! The design in this RFC is a good one to get us started, but I imagine that as the language progresses, it's needs and use cases for the declaration engine will expand and change. Introducing the declaration engine now gives us the opportunity to create a mechanism through which some of those changes could be introduced later down the road.

That being said, from a high-level perspective, the alternative design would be something similar to what we are doing now, which is more focused on inlining things.

# Prior art

[prior-art]: #prior-art

1. [rustc item collection for monomorphization](https://github.com/rust-lang/rust/blob/8fe936099a3a2ea236d40212a340fc4a326eb506/compiler/rustc_monomorphize/src/collector.rs)
2. [rustc collection item context](https://github.com/rust-lang/rust/blob/a8f7e244b785feb1b1d696abf0a7efb5cb7aed30/compiler/rustc_hir_analysis/src/collect.rs)
3. [idris has a context it uses to resolve types](https://github.com/idris-lang/Idris2/blob/86c060ef13fd8194f849e2a4a4295cd37c0d061c/src/Core/Context/Context.idr)
4. @tritao wrote [something similar](https://github.com/tritao/CppSharp/blob/22c15789c551ed5d64b05ce48d0353b117865368/src/AST/ASTContext.cs) in his older project.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

I'd really like to get feedback on the fine-level details of the initial implementation that I described above. I can provide additional information or context if that is helpful too.

# Future possibilities

[future-possibilities]: #future-possibilities

This RFC precedes an RFC introducing a collection context.

### Collection Context

Sway wants to support 'out of order' declarations and dependencies and recursive declarations and dependencies. The former has pretty good support already, with some bugs, but the latter is not currently possible because the compiler requires all declarations to be in the 'proper' ordering before type checking can begin.

I propose two new passes, a "node collection" pass, which constructs a graph of the untyped program relative to any one node. The information collected from this stage is used provide a "look ahead" ability for the "type collection" pass.

And a "type collection" pass, which performs type checking on the "high-level" information for declarations. "High-level" information would include type checking a function signature (but not a function body), type checking a struct definition and the function signatures of its methods (but not the method bodies). Rust does this same step actually: https://rustc-dev-guide.rust-lang.org/type-checking.html#type-collection

Once these are added, the compile would roughly look like:

1. parsing
2. node collection
3. type collection
4. type inference (the stuff remaining after type collection)
5. code generation

**Note:**

We probably won't be able to support recursive structs and certain recursive enums until we introduce pointer types.
