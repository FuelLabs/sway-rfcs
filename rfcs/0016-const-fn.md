- Feature Name: `const_fn`
- Start Date: 2025-02-26
- RFC PR: [FuelLabs/sway-rfcs#44](https://github.com/FuelLabs/sway-rfcs/pull/44)
- Sway Issue: [FueLabs/sway#5907](https://github.com/FuelLabs/sway/issues/5907)

# Summary

[summary]: #summary

This RFC proposes the implementation of `const fn` in Sway, enabling
more expressive and flexible compile-time function evaluation.

# Motivation

[motivation]: #motivation

The primary motivation for `const fn` is to enable computations at compile time,
reducing runtime overhead and allowing for more efficient program execution. 
By expanding const fn, we provide more expressive power in defining constant
expressions. Const fn are a backbone of the storage initializations.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

## What is `const fn`?
A `const fn` is a function that can be evaluated at compile time. This allows
its results to be used in constant contexts such as `const` variables.

```sway
const fn add(x: u32, y: u32) -> u32 {
    x + y
}

const SUM: u32 = add(3, 4);
```

## Const context

A constant context is any place in the code where only constant values and
computations are allowed at compile time. These contexts require values that
can be fully determined by the compiler without executing any runtime code.

### Where do constant contexts occur?

#### 1. Constant Items

Constants must be initialized with a compile-time evaluable expression.

```sway
const SIZE: u64 = 1024;
const DOUBLE_SIZE: u64 = SIZE * 2; // Constant context
```

#### 2. Storage initialization

Values assigned to storage slots must be known at compile time.

```sway
storage {
    total_supply: u64 = 0, // Constant context
}
```

The `in` keyword expects also a compile time evaluable expression.

```sway
const HASH_KEY: b256 = 0x7616e5793ef977b22465f0c843bcad56155c4369245f347bcc8a61edb08b7645;
storage {
    current_owners in HASH_KEY: u64 = 0,
}
```

#### 3. Configurable initialization

Values assigned to configurable must be known at compile time.

```sway
configurable {
    DECIMALS: u8 = 9u8,
}
```

#### 4. Inside const fn

Within a const fn, all expressions must be evaluable at compile time.

```sway
const fn square(x: u32) -> u32 {
    x * x // Constant context
}
```

## `const fn` methods

`const fn` can be declared inside trait and impl block.

```sway
trait MyTrait {
    const fn foo(a:u64) -> u64;
}

struct MyStruct {}

impl MyTrait for MyStruct {
    const fn foo(a:u64) -> u64 {
        42
    };
}

impl MyStruct {
    const fn bar(a:u64) -> u64 {
        42
    };
}
```

## Calling other `const fn`

It is possible to call other `const fn` from another `const fn`, and non `const fn`
cannot be called from `const fn`.

```sway
const fn add_inner(x: u32, y: u32) -> u32 {
    x + y
}

const fn add(x: u32, y: u32) -> u32 {
    add_inner(x, y)
}

const SUM: u32 = add(3, 4);
```

## Generic `const fn`

`const fn` supports generic parameters.

```sway
trait Eq {
    fn eq(self, y:Self) -> bool;
}

impl Eq for u64 {
    fn eq(self, y:Self) -> bool {
        self == y
    }
}

fn eq<T>(x: T, y: T) -> bool where T:Eq {
    x.eq(y)
}

const EQUAL: bool = eq(3u64, 4u64);
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Parsing

Parsing needs to be changed so keyword `const` or `constexpr` can be used before
all the places the keyword `fn` is used.
This includes `fn`s in function, trait and impls.

## When are `const fn`s const-evaluated vs. downgraded to runtime?

A `const fn` can be evaluated at compile time under certain conditions, but in
other cases, it may be downgraded to runtime execution. This depends on where
and how the function is called.

### When is a `const fn` const-evaluated?

A `const fn` is evaluated at compile time only if it is used in a constant context,
meaning its result must be known during compilation. This happens in:

- Constant items
- Configurable initialization
- Storage initialization

When a `const fn` is called in a regular function and the `const fn` parameters are
known at compile time then the `const fn` can be evaluated at compile time.

```
fn main() {
    let a = add(10, 20); // Evaluated at compile time
}
```
### When is a `const fn` downgraded to runtime execution?

A `const fn` is executed at runtime when it is called in a normal function or an
expression that does not require compile-time evaluation.

When a `const fn` is called in a regular function and the `const fn` parameters are not
known at compile time then the `const fn` also needs to be called at compile time.

```
fn main() {
    let mut x = 0;
    while x < 20 {
        let a = add(x, x); // Downgraded to runtime execution
        x += 1;
    }
}
```

## Evaluation

The compiler needs to know how to evaluate `const fn`, two approaches are proposed.

### Compiler IR evaluation.

In this approach `const fn`s are evaluated by running an IR interpreter at the compiler level.

This approach implies us implementing incrementally an interpreter for the IR features
and ensure that const evaluation follows the same rules as VM execution.

As Fuel already has a fully implemented VM a better approach is to leverage this and
reuse it to do const evaluation as presented in the next section.

### VM evaluation

In this approach we compile a binary with all the `const fn` to be run by Fuel Virtual Machine.

The advantages of doing this are guaranteed similar behavior between `const fn` 
and non const counter part, as the same backend is used to compute the result 
thus also not requiring to maintain two separate code bases.

Using the VM interpreter also gives support out of the box for assembly blocks and all the VM opcodes.

Let us have the following program that initializes two `const` variables with the return of `const fn`s.
```sway
lib;

const fn add(x:u64, y:u64) -> u64 {
    x + y
}

const fn sub(x:u64, y:u64) -> u64 {
    x - y
}

const A: u64 = add(1,2);
const B: u64 = sub(A,2);
```

The VM const evaluation would be done by compiling and running the following program:

```sway
script;

fn add(x:u64, y:u64) -> u64 {
    x + y
}

fn sub(x:u64, y:u64) -> u64 {
    x - y
}

fn main() {
    let A = add(1,2);
    let B = sub(A, 2);

    let A_ptr = __addr_of(&A);
    let A_size = __size_of_val(A);

    let B_ptr = __addr_of(&B);
    let B_size = __size_of_val(B);

    __log(raw_slice::from_parts::<u8>(A_ptr, A_size)); // Outputs const A value
    __log(raw_slice::from_parts::<u8>(B_ptr, B_size)); // Outputs const B value
}
```

All the const evaluated values for the original program are returned using log.

The returned log data contains a `Vec<u8>` obtained by using the ABIEncode.

Using VM evaluation we can store the generated ABIEncoded byte array into the
final bytecode of the program.

To compile the example above it takes 0.76 seconds including core, without core
it takes less than 0.02 seconds to compile. To bootstrap the VM and run the
script it takes less than a millisecond.
Thus the overhead for doing `const fn` evaluation with the VM should be around
**tens of milliseconds**, which is negligible compared to compiling a program
with std which takes around 2.5 seconds.

## Enforcing constness rules

To ensure that `const fn`s maintain predictable compile-time behavior, we enforce a set of constness rules that restrict what can and cannot be done inside a `const fn`. These rules prevent operations that rely on runtime state while allowing deterministic computation at compile time.

- No access to storage
- Cannot use certain asm opcodes
- Error out when `const context` is assigned to a heap type.

### Non usable asm opcodes

The same opcodes that are disallowed to predicates are also disallowed in const fn:

- BAL
- BHEI
- BHSH
- BURN
- CALL
- CB
- CCP
- CROO
- CSIZ
- GM
- LOG
- LOGD
- MINT
- RETD
- SMO
- SRW
- SRWQ
- SWW
- SWWQ
- TIME
- TR
- TRO

### Heap types

Heap types are a challenge for `const fn` for multiple reasons.
First is the how to map the binary data section entry for a Heap type to the heap.
Another challenge is that to properly use heap types such as `Vec<T>` we want to
support methods such as: `fn push(ref mut self, value: T)`, and this would require
 `const fn`s to support `ref mut` parameters.

As heap types created in the binary data section would require additional effort to be 
used at runtime and in small cases this would offset the time required to recompute 
them. It would be better to disallow `const fn` from returning or receiving Heap 
types but still allow them to use Heap types inside the `const fn` code blocks.

Thus we propose to not try to serialize and deserialize the heap types in the 
binary data section instead throw warnings or errors when the compiler tries to store
the result of a const evaluation in the binary data section.

This allows `const fn`s to use heap types internally but restricts types in the data
sections to non heap types.

### `ref mut` parameters

Support of `ref mut` in `const fn` is a requirement for properly
handling heap type such as `Vec<T>` and function such as `fn push(ref mut self, value: T)`.

A `const fn` with a `ref mut` parameters is callable inside other regular and `const fn`s but
cannot be used directly in other `const contexts` such as constant items.

## Final binary

When a `const fn`is not called at runtime the final binary outputted by the compiler
won't have any opcodes related to the computation of `const fn`s.

All the `const fn`s results reside in the binary data section. `const fn` calls are
replaced by the respective const variable that is generated during the const evaluation.

When a `const fn` is called with the same arguments in different places a unique
data section const entry should be used.

# Prior art

[prior-art]: #prior-art

## Rust

Rust currently utilizes Miri, an interpreter for MIR (Mid-level Intermediate
Representation), to evaluate const fn at compile time. Miri allows Rust to
enforce strict safety checks and ensures that constant evaluation follows
the same rules as runtime execution.

Miri is used to:
 - Validate the correctness of const fn evaluations.
 - Ensure that const fn does not cause undefined behavior, such as out-of-bounds memory access.
 - Simulate execution of const fn in the compiler, ensuring predictable compile-time behavior.

While Miri provides a robust foundation, its interpretation speed and limitations
in heap allocations pose challenges for extending const fn capabilities.

## C++

C++ has a way of having a function that can be both used in const
 evaluation and that can also be used at runtime.
They do that by having the keyword `constexpr` before functions
 declarations that can be run both at runtime and at compile time, this is the equivalent of
`const fn` in Rust.
And `consteval` to make sure that a function is evaluated only at
 compile time and does not exists at runtime, which has no equivalent in Rust or this proposal.

# Future possibilities

[future-possibilities]: #future-possibilities

In the future we may also want to support `const blocks` that can be used without necessarily calling a `const fn`.

```sway
const SUM:u64 = const {
    let a = 1;
    let b = 2;
    a + b
};
```

