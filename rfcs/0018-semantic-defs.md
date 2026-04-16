* Feature Name: (fill me in with a unique ident, my_awesome_feature)
* Start Date: (fill me in with today’s date, YYYY-MM-DD)
* RFC PR: FuelLabs/sway-rfcs#0000
* Sway Issue: FueLabs/sway#0000

# Summary

SemanticDefinition will unify all the necessary work for the semantic pass: unification,
monomorphization and checks, simplifying and decreasing the fragility of the current manual approach.

# Motivation

The current type system relies on scattered calls to unify types, multiple passes of type checking (code blocks, method/function resolution), and symbol unification.

Apart from that, we need multiple visitors (SubtsStype, ReplaceDecl, MaterializeConstGenerics etc…)
for monomorphization.

To make matters worse, there is no go-to mechanism to check or do additional work after a type
reaches its final concrete form. Which leads us to hijack existing visitors, like TypeCheckAnalysis.

All this not only increases complexity (a lot), but also leads to bugs
where certain code patterns do not have unification, substitution and or checks in the correct
order.

This proposal introduces a SemanticDefinition-based approach that will unify and simplify all the above.

Instead of attempting to do the whole analysis immediately when the AST is being traversed the first time,
the compiler will emit “constraints” and “deferred tasks” that will be run in very specific points.

## No ideal place to check the final concrete types

The first very clear problem with the current architecture can be seen when the compiler is type-checking literals. A numeric literal might be assigned a generic Numeric type.

Later on, because of type inference, it might be more specifically typed to u32. At this point, the compiler needs to check
if the literal actually “fits” into u32 , and return an error to the user.

Currently, there is no ideal place to put this check. The best possible solution would be to visit the typed tree and check if all literals fo indeed fit into their types.

To avoid creating extra visitors, we started to hijack existing ones, like TypeCheckAnalysis.

Something very similar happens for “explicit arrays”. There is no ideal place to unify/check the final concrete types of all array elements. We also hijacked TypeCheckAnalysis for this.

## Conditional symbol resolution

Although we do support associated items, they do not work in all cases. As described above, the cause for some of the limitations is that it depends on the order of how unification, substitution and others run.

One specific limitation is that the type system do not allow for conditional types. We “carry” these types as unsolved types using Custom until unification manages to “concretise” the type.

## Reflection

To implement a sound TrivialEnum<Enum> we need the unwrap function to be able to check if a blob of bytes will decode into a valid instance of its enum. For that, we need to check if the first 8 bytes of the blob is a valid discriminant for the enum.

The only way to do this at runtime is to generate something, an array of bool, for example, with each value stating if that variant is trivially decodable or not.

To be able to monormorphize one single unwrap to each instantiation, we need to be able to compile an array where each element depends on the final concrete type of the TrivialEnum generic type.

Currently, there is no way to know that a generic type reached concreteness. Again, the only viable solution is to have a visitor that runs at the end of type checking.

# Guide-level explanation

SemanticDefinition unifies all the necessary work to be done by the semantic pass, today called casually as “type check”.
The definition is stored inside the DefinitionEngine together with other engines inside Engines, so we can share them with
all the other monomorphized instances.

SemanticDefinition has a method called solve which receives values from the “outside world” and iterates its solver. For example:

```rust
let args = definition.args()
    .arg(TypeInfo::Generic, TypeInfo::U32)
    .build();
definition.solve(SolveArgs {
    args,
});
```

solve returns a list of unsolved definitions, and the caller decides what to do with it. In some cases, this can mean partial monomorphization; in other cases, the list will be empty, signalling monomorphization is complete and the item has reached its final and stable form - nothing else inside it can change.

To get a definition from an item, one can do

```rust
let id = <item as SemanticDefinitionContainer>::semantic_def_id();
let definition: SemanticDefinition = engines.sde().get(id);
```

# Reference-level explanation

Introduce a SemanticDefinition that will store all pending work of the semantic analysis.

Initially, we foresee the following definition items:

1 - Type constraints;
2 - Unifications;
3 - Conditional Symbol Resolution;
4 - Type and Decl concretisation
5 - General Work

SemanticDefinition will be used in the semantic analysis pass, as we are calling our current “type_check” methods,
we will also collect all the above items. All checks on types that exist inside these functions will also be deferred to when the type will reach concretiness.

These SemanticDefinitions will always have all the necessary constraints because they will be shared by all monomorphizations
of Decls. The idea here is to minimise memory cost.

The only real optimisation that SemanticDefinition will do is to avoid saving trivial deferred work. For example, if there is a check on a type, and the type is already concrete, we can run the check immediately. There is no need to defer this check and use more memory than needed.

Initially, we will move the “Unification Collection” away from the type engine. This will be the first item implemented for the definition. At this stage, Solve will not need any arguments; it will simply run something akin to the ARC3 solver. Unifying types and queues, changing types and their unification until the whole process stabilises.

After that, we can start implementing the necessary items to fix the problems listed above.

Ultimately, we can also try to solve monomorphization and replace SubsType, ReplaceDecls and other visitors. This will enable
a more pipelined version of the whole semantic pass. Where we will iterate everything once, generate all the necessary definitions, and just call solve for the necessary monomorphizations, following call paths from entries.

# Drawbacks

This will be an improvement that will last multiple versions. There is always the danger of introducing one more half-baked way of doing things. So instead of unifying other processes, we just create another one.

# Rationale and alternatives

Another possible solution is to implement another visitor that just runs at the end of the semantic pass. It will be limited what can be done at such a late stage, but it will work in some cases.

# Prior art

Using a constraint solver for type-checking and type inference is nothing new:

* A Relational Solver for Constraint-based Type Inference
https://arxiv.org/html/2408.17138
* Constraint-based type inference for FreezeML
https://homepages.inf.ed.ac.uk/slindley/papers/freezeml-constraints-draft-march2022.pdf
* InferType: A Compiler Toolkit for Implementing Efficient Constraint-Based Type Inference
https://drops.dagstuhl.de/entities/document/10.4230/DARTS.10.2.11

and many, many others.

# Unresolved questions

* It remains an open question if we can implement all the use cases of type checking, inference, etc., that we need
using this system.
* Solver will run in a loop. Although we can prvent infinite loops, it is not certain if this can decrease performance in general or not. At first glance, solving the system should be faster than all the visitors we have, but we have no way to be certain at this point.

# Future possibilities

With the SemanticDefnition complete, we can also improve the concepts of Decls and Refs that are still blurry. With this, we can finally move monomorphization to after the semantic pass is finished and be certain that the only Decls that exist in the DeclEngine are the canonical ones (from source code).

Not storing extra Decls and consequently extra types, etc. We can substantially improve both time and memory performance of the compiler. This can have a direct consequence in the LSP server and others.
