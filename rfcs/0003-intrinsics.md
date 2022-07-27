- Feature Name: `sway_intrinsics_support`
- Start Date: 2022-07-26
- RFC PR: [FuelLabs/sway-rfcs#12](https://github.com/FuelLabs/sway-rfcs/pull/12)
- Sway Issue: [FueLabs/sway#855](https://github.com/FuelLabs/sway/issues/855)

# Summary

[summary]: #summary

This is a discussion document on how Intrinsics must be modelled in the Sway compiler. At the time of writing, we have six intrinsics supported in the compiler, of which three (`SizeOfType`, `SizeOfValue` and `IsReferenceType`) get resolved at compile time, and the other three (`GetStorageKey`, `Eq` and `Gtf`),  have sway-ir `Instruction` representations. The document dives in deeper into the following aspects of supporting intrinsics in the Sway compiler.

- What are we going to gain from this?
- What intrinsics do we want to support?
- How should these intrinsics be represented?
- Testing plan.
- Documentation plan for all supported intrinsics.

# Motivation

[motivation]: #motivation
- Type checked core and std library implementation. Today, the implementations are in assembly, which aren’t type checked (just the wrapper functions are typed).
- These libraries, when rewritten using intrinsics instead of assembly, can be more easily ported if we decide to support other targets.
- More optimizations. When operations such as `add` are hidden behind assembly, it’s hard for the compiler to reliably perform optimizations. With explicit representation (either via IR opcodes, or as intrinsic+name - see next section), compiler analyses and transforms become simpler.
- A side effect of easier analysis is that, as an example, we can improve usability by allowing declarations such as `const X = Y + Z`, which we don’t today, because we cannot, yet, statically evaluate `+`.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

While the primary purpose of intrinsics is to expose VM op-codes
in Sway so that their usage in the core and standard libraries are
safer, there is nothing stopping from Sway programmers in using
these intrinsics directly in their code.

At the Sway programmer level, intrinsics work similar to the core and
standard library functions (i.e., they can be called as mere functions).
A comprehensive list of intrinsincs made available by the Sway compiler
can be referenced here (TBD).

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Representation of Intrinsics in the Compiler
- Treat intrinsics the same as function calls. They can always be
  distinguished because their name begins with `__`.

  In our current framework, this approach isn’t practical since we inline all function calls before even generating sway-ir.

  For some operations, such as the arithmetic ones, it may make more sense to give them a first-hand representation as IR opcodes (as is done in most languages and compilers), than as mere function calls. While this might make IR analysis and transformation a little simpler, I can’t say that that difference is significant.

- Treat intrinsics with `IntrinsicCall` AST nodes and lower them to
  unique op-codes in the IR. I can’t see a clear advantage to doing
  this, except for some intrinsics (such as the arithmetic ones) to
  be represented via IR op-codes. Overall, using IR op-codes for
  intrinsics (except in the special cases such as for `add` etc)
  doesn't seem like a good idea. LLVM, for example
  [discourages it](https://llvm.org/docs/ExtendingLLVM.html#introduction-and-warning).

Whatever be the representation we choose, a goal at this stage is for us to be able to type-check intrinsic calls with a table based approach. That is, the type constraints are expressed in a table and the type checker just references this table to type-check. As is visible today, even with just six intrinsics, without a table based approach, we already have a lot of code to typecheck each intrinsic, all of them doing the same thing, with just minor differences.

It is possible that we may come across some type constraints on intrinsics that cannot be encoded into our table. In such a case, it may be required to write code for it manually (or perhaps provide a lambda / closure in the table which will be called by the type checker).

A type-information table to type-check intrinsics could look like this:

| Intrinsic | Type parameters and types allowed on each type parameter |Type (parameter) of each argument and result type |
| ----------- | ----------- | ----------- |
| `add`       | `[ (T, [u64, u32, … ]) ]`   | `([T, T], T)` |
|  ...        |    ...      |  ...        |


## What intrinsics do we want to support?
To begin with, VM opcodes that are used through assembly wrappers in the core and std library implementations must be exposed as intrinsics. In the future, we could also provide intrinsics for other VM opcodes that need type checking; and  (gas / performance) optimized hand-written assembly code sequences that the compiler’s code generation cannot match.

A (non-exhaustive) list of intrinsics to support: `std::ops` (arithmetic, logical, comparison), `alloc`, `block::height`, `logging::log` etc.

Because of the possibility of Sway supporting other targets in the future
(such as EVM), VM specific intrinsics may be declared modularly, so that
the toolchain can choose the ones to load based on the target.

## Testing
For each core/std library function that we provide an intrinsic for, move the library function into the testsuite, and for every (prio) use of the library function in the testsuite, replace it with a call to the intrinsic and an assert that calls the (now in the testsuite) library function and asserts equivalence. For newly supported VM opcodes, add new tests

## Documentation
Given that Sway programmers are free to use intrinsics, it is essential
that we document all intrinsics categorically in a book, perhaps
alongside the standard library.

# Drawbacks

[drawbacks]: #drawbacks

A lot of operations that we want to support via intrinsics already have working assembly based implementations. The assembly we generate in the compiler for these intrinsics will probably be similar to the handwritten assembly, and from what I can tell, similarly done (i.e., manually) in the compiler. This makes me wonder if it’s all worth it, and instead can we just detect calls (by their path/name) to functions in the core/std libraries that we’re interested in involving in an analysis/optimization and act based on that (as if it were an intrinsic). This assumes that we don’t want to type-check / validate the core/std libraries and that they are going to be error-free.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

The main design choice to be made here is in representing Intrinsics
internally in the compiler. The two obvious choices were already
outlined in an earlier section.

# Prior art

[prior-art]: #prior-art

[Intrinsics](https://en.wikipedia.org/wiki/Intrinsic_function) / compiler builtins are a common feature provided by compilers across
many programming languages. While [GCC](https://gcc.gnu.org/onlinedocs/gcc-4.9.2/gcc/Other-Builtins.html#Other-Builtins) and [LLVM ](https://llvm.org/docs/ExtendingLLVM.html) provide a long list of
intrinsics, hardware vendors also provide their own set of intrinsics
to enable programmers to take advantage of special instructions
that the compiler does not directly / efficiently support. See
Intel's [AVX intrinsics](https://www.intel.com/content/www/us/en/develop/documentation/cpp-compiler-developer-guide-and-reference/top/compiler-reference/intrinsics/intrinsics-for-intel-advanced-vector-extensions/details-of-avx-intrinsics.html), for example.

To summarize, the idea is old and useful, and something that we can implement, without much surprises `¯\_(ツ)_/¯`. 

# Unresolved questions

[unresolved-questions]: #unresolved-questions

...

# Future possibilities

[future-possibilities]: #future-possibilities

...