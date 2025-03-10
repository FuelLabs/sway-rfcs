- Feature Name: `const_fn`
- Start Date: 2025-02-26
- RFC PR: 
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

### What is `const fn`?
A `const fn` is a function that can be evaluated at compile time. This allows
its results to be used in constant contexts such as `const` variables.

```sway
const fn add(x: u32, y: u32) -> u32 {
    x + y
}

const SUM: u32 = add(3, 4);
```

### `const fn` methods
`const fn` should be able to be declared inside trait and impl block.

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

### Calling other `const fn`
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

### Generic `const fn`
`const fn` should support generic parameters.

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
## Const in binary data section

## Heap types

Heap types are a challenge for `const fn` for multiple reasons.
First is the how to map the binary data section entry for a Heap type to the heap.
Another challenge is that to properly use heap types such as `Vec<T>` we want to
support methods such as: `fn push(ref mut self, value: T)`, and this would require
 `const fn`s to support `ref mut` parameters.
Changing `Vec::<T>::push` to be a `const fn` would also imply that the instance of
 `Vec<T>` should only be used inside a `const fn` because `const fn` do not exist
  at runtime.

As heap types created in the binary data section require additional effort to be 
used at runtime and in small cases this would offset the time required to recompute 
them. It would be better to disallow `const fn` from returning or receiving Heap 
types but still allow them to use Heap types inside the `const fn` code blocks.

Thus we propose to not try to serialize and deserialize the heap types in the 
binary data section instead throw warning or errors when Sway code has
`const fn`'s that return Heap types.

## `constexpr fn`

C++ actually has a way of having a function that can be both used in const
 evaluation and that can also be used at runtime.
They do that by having the keyword `constexpr` before functions
 declarations that can be run both at runtime and at compile time.
And `consteval` to make sure that a function is evaluated only at
 compile time and does not exists at runtime, this would be the equivalent of `const fn`.

Thus one possibility is Sway also having `constexpr` so that `const fn`
 can also use functions that would otherwise only be executable at runtime.

Using `constexpr` in the existing functions of our existing libraries
would empower us to quickly reuse types both in `const fn` and runtime functions.     

## `ref mut` parameters

Support of `ref mut` in `constexpr fn`s would be a requirement for properly
handling heap type such as `Vec<T>` and function such as `fn push(ref mut self, value: T)`.
But we do not want to support `ref mut` in `const fn` as it does not make
sense to modify some variable that exists at runtime using something that executes at compile time.

## Restrictions in `const fn` and `constexpr fn`

    - No access to storage
    - Cannot use certain asm opcodes

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Parsing

Parsing needs to be changed so keyword `const` or `constexpr` can be used before
all the places the keyword `fn` is used.
This includes `fn`s in function, trait and impls.

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

## Final binary

The final binary outputted by the compiler won't have any opcodes related to the
computation of `const fn`s. All the `const fn`s results will reside in the binary
data section. `const fn` calls will be replaced by using the respective const
variable that is generated during the const evaluation.

When a `const fn` is called with the same arguments in different places a unique
data section const entry should be used.

## Changes in Core and Std Libraries

# Prior art

[prior-art]: #prior-art

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

