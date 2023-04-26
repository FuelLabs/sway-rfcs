- Feature Name: evm_backend
- Start Date: 2022-12-22
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#EVM](https://github.com/FuelLabs/sway/issues?q=is%3Aissue+is%3Aopen+label%3AEVM)

# Summary

[summary]: #summary

Sway should target the Ethereum Virtual Machine.

# Motivation

[motivation]: #motivation

This proposal supports the objective for Sway to be a modular language to target multiple blockchain
virtual machine architectures. This will also provide EVM engineers with a good balance between gas
efficiency and safety.

Currently, Solidity is the most popular language, with Vyper, Fe, and Huff being distant
competitors. Solidity's object-oriented model, messy library support, and lack of abstract data
types makes for a clumsy developer experience, while Vyper does not support code-sharing at all and
makes optimization and safety tradeoffs that make it unsuitable for many modern use cases. Sway's
type system, library support, and in-line assembly support make it a good language for the EVM.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

An EVM Backend for the sway compiler means the compiled output will be valid EVM instructions. This
also introduces changes to the Application Binary Interface (ABI) generation to match that of the
EVM standards defined [here](https://docs.soliditylang.org/en/v0.8.17/abi-spec.html).

An EVM Sway contract may look as follows.

```rust
// imports all evm types
use std::evm_prelude::*;

// Storage definition
storage {
    // EVM Type: Uint256
    value: Uint256,
}

// Event definition
struct ValueSet {
    // Indexed<T> is a type to be used only in Event structs
    old: Indexed<Uint256>,
    new: Indexed<Uint256>,
}

// ABI definition
abi ValueHandler {
    #[storage(read, write)]
    fn set(new: Uint256);
    #[storage(read)]
    fn value() -> Uint256;
}

// Contract definition
impl ValueHandler for Contract {
    #[storage(read, write)]
    fn set(new: Uint256) {
        let old: Uint256 = storage.value;
        storage.value = new;

        log(ValueSet { old, new });
    }

    #[storage(read)]
    fn value() -> Uint256 {
        storage.value
    }
}
```

Compare this to a functionally equivalent Solidity contract.

```sol
// ABI definition
interface IValueHandler {
    function set(uint256 newValue) external;
    function value() external view returns (uint256);
}

// Contract definition
contract ValueHandler is IValueHandler {
    event ValueSet(uin256 indexed oldValue, uint256 indexed newValue);

    // Storage layout is implicit and follows C3 linearization with
    // lower-order alignment and is packed by each type's max size.
    // The `public` keyword implicitly creates a view function.
    uint256 public value;

    function set(uint256 newValue) external {
        uint256 oldValue = value;
        value = newValue;

        emit ValueSet(oldValue, newValue);
    }
}
```

EVM Code generation can be enabled by a new field in the `Forc.toml` file.

```toml
[project]
authors = ["user"]
entry = "main.sw"
license = "Apache-2.0"
name = "example"
target = "eofv1"
```

Development, Testing, and Deployment can be done through Hardhat or Foundry using a simple plugin
for each.

> Notice: Using Foundry requires tests to be written in Solidity and using hardhat requires tests to
> be written in Javascript or Typescript at the time of writing.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Code Generation

There are a few options for code generation, each with different tradeoffs.

### [Yul Intermediate Language](ttps://docs.soliditylang.org/en/latest/yul.html)

Using Yul is a high-level approach. Yul abstracts stack operations and manual jumps and introduces
high-level control flow such as `if` and `switch` conditionals, `for` loops, and internal functions.

This also abstracts away details of the series of Ethereum Improvement Proposals for changing the
format to EOFv1 for EVM executables. The relevant EIP's are as follows.

- [EIP-3540: EOF v1](https://eips.ethereum.org/EIPS/eip-3540)
- [EIP-3670: Code validation](https://eips.ethereum.org/EIPS/eip-3670)
- [EIP-4200: Static relative jumps](https://eips.ethereum.org/EIPS/eip-4200)
- [EIP-4750: Functions](https://eips.ethereum.org/EIPS/eip-4750)
- [EIP-5450: Stack validation](https://eips.ethereum.org/EIPS/eip-5450)

The disadvantages of this approach include the Yul compiler (C++), dependency on the Solidity team
(same team) for updates, lack of control over the stack, and external optimizations (Yul handles
optimization passes).

### [ETK Intermediate Language](https://quilt.github.io/etk/index.html)

Using EVM Toolkit introduces expressions, macros, and labels, making for a good intermediate
language to target. Due to its minimalism, we can perform optimization passes and manage the stack
in the Sway compiler instead of relying on an external compiler.

The main disadvantage of using ETK is dependency on the ETK team to change the language when the
EOFv1 changes are implemented. Given the scope of the changes, it would be in Sway's best interest
to target the new EOFv1 format, as Solidity is the only language that has code to target the new
format.

### [Raw EVM Bytecode](https://github.com/jtriley-eth/the-ethereum-virtual-machine/blob/main/src/instruction-reference.md/)

Generating EVM bytecode directly avoids dependencies on external languages and tools, with the
primary disadvantages being development overhead and necessity to update the code generation when
the EOFv1 changes are implemented.

## Standard Library

A submodule in the standard library to implement EVM types is needed, but abstract data types can
remain largely unchanged.

Necessary, unique modules include (but may not be limited to):

- external calls
    - payable
    - nonpayable
    - static
    - delegate
- (de)serialization
    - encode
    - encode packed
    - encode with selector
    - encode with signature
    - encode call
- code read
    - size
    - hash
    - copy
- deploy
    - create
    - create2
    - create3 (maybe)
- raw storage
    - store
    - load
    - sstore2
- reentrancy
    - detection
    - prevention
- math
    - unsafe
    - fixed point
- precompiles
    - ecrecover
    - sha256
    - ripemd160
    - identity
    - modexp
    - ecadd
    - ecmul
    - ecpairing
    - blake2f
- tx info
    - gasprice
    - origin
    - gasleft
- block info
    - hash
    - basefee
    - coinbase
    - prevrandao
    - gaslimit
    - number
    - timestamp
- call info
    - data
    - sender
    - selector
    - value

## Inline Assembly

Inline assembly is an important inclusion for low level control, both for optimizations and uncommon
patterns such as proxy contracts, data contracts, and custom "instructions".

Provided Yul is not used as an intermediate language, allowing manual stack management and all
instructions would be ideal. The instructions, if any, to be disallowed would include the following:

- `jump`
- `jumpi`
- `jumpdest`
- `callf` (post-EOFv1)

Disallowing arbitrary jumps will be necessary to avoid issues with EOFv1 validation, however, `retf`
may be allowed, provided it resides in an internal function and the stack matches the order of
return values defined in the internal function.

## Storage Optimization

Reading and writing storage is extremely expensive in the EVM, therefore strong optimizations must
be made to ensure tight storage packing.

Solidity has a well optimized storage layout, [documented here](https://docs.soliditylang.org/en/v0.8.17/internals/layout_in_storage.html),
but with on significant limitation, optional storage packing.

By default, all variables are packed tightly, based on order of declaration in a contract and it
follows c3 linearization. Either adding a field in the `Forc.toml` file for manual storage
modification or a modificaiton to the `storage` definition would be ideal.

As an example, the following is two contracts using a reentrnacy guard, but given the storage rules
defined by Solidity, the second is more efficient than the first by 153 gas.

```sol
pragma solidity 0.8.17;

error Reentrancy();

contract Expensive {
  uint8 internal someVar;
  bool internal reentrancyLock;
  uint8 internal anotherVar;

  modifier lock() {
    if (reentrancyLock) revert Reentrancy();
    reentrancyLock = true;
    _;
    reentrancyLock = false;
  }

  // 50_962 gas
  function a() external lock {}
}

contract Cheap {
  bool internal reentrancyLock;

  modifier lock() {
    if (reentrancyLock) revert Reentrancy();
    reentrancyLock = true;
    _;
    reentrancyLock = false;
  }

  // 50_809 gas
  function a() external lock {}
}
```

A few potential solutions to this may be something like the following:

```rs
storage {
    someVar: u8,
    reentrancyLock: PaddedBool,
    anotherVar: u8,
}

storage {
    someVar: u8,
    reentrancyLock: Padded<bool>,
    anotherVar: u8,
}

storage {
    someVar: u8,
    reentrancyLock: bool,
    anotherVar: u8,
}
```

## EOFv1

The Ethereum Object Format V1 (EOFv1) is significant enough to merit its own section in this
proposal because, at the time of writing, it is expected to be implemented in the Shanghai Hard Fork
assuming other changes go smoothly. This drastically changes the EVM executable format.

### Legacy Format

The legacy EVM executable format is strictly a bytestring with no particular format. There is no
deploy-time validation, no assertions that the stack will always be valid (no over/underflows), no
assertion that jumps are valid. A stream of bytes is interpreted starting at the beginning of the
executable and checks for are performed at runtime. It is also noteworthy to mention jumping is
relatively simple with `jump` and `jumpi` being the jump instructions and `jumpdest` being a no-op
instruction that marks a valid bytecode index to jump to. The jump instructions currently pops the
value from the stack, meaning jumps are dynamic.

Constants are embeded in the executable directly, generally they are copied, but in some cases they
can be jumped to.

The format is as follows:

```xml
<instructions />
```

A valid example of a legacy contract with a jump:

```
// bytecode
0x 60 03 56 5b

// mnemonic
push1 0x03
jump
jumpdest
```

#### EOFv1 Format

The EOFv1 format includes a standard layout for code containers separating code from data, removes
`jump`, `jumpi`, and `jumpdest`, and creates five opcodes for jumping in the bytecode.

The opcodes are as follows:

- `rjump <imm>` Static relative jump to `imm`
- `rjumpi <imm>` Conditional static relative jump to `imm`, pops condition from the stack
- `rjumpv <len> <jumptable>` Static relative jump within jump table, pops case from the stack
- `callf <imm>` Jumps to internal function defined in types and code section (alters return-stack)
- `retf` Jumps from internal function to last `callf` instruction (alters return-stack)

The format is as follows:

```xml
<header>
  <magic />
  <version />
  <type_section_start />
  <type_section_size />
  <code_section_start />
  <code_section_size />
  <number_of_code_sections />
  <code_section_size />
  <data_section_start />
  <data_section_size />
</header>
<body>
  <type_section />
  <inputs />
  <outputs />
  <max_stack_height />
  <instructions />
  <constants />
</body>
```

Internal functions to be accessed via `callf` and `retf` _MUST_ be defined using metadata in the
`type_section`. The metadata consists of three attributes and is four bytes long.

- `uint8` inputs
- `uint8` outputs
- `uint16` max_stack_height

A valid example of an EOFv1 contract with a callf:

```
// bytecode
0x ef 00 01 01 00 08 02 00 02 00 07 03 00 00 00 00 00 00 00 02 00 02 00 02 b0 01
f3 60 00 80 b1

// mnemonic

0xef00      // magic
0x01        // version
0x01        // type section marker
0x0008      // type section length
0x02        // code section marker
0x0002      // num of code sections
0x0008      // code section length
0x03        // data section marker
0x0000      // data section length
0x00        // end header
            // type section start
0x00000002  // entry point metadata (0 inputs, 0 outputs, max stack height 2)
0x00020002  // function 0 metadata (0 inputs, 2 outputs, max stack height 2)
            // code section start
            // entry point
callf 0x0001// callf on function at index 0x01
return      // return to caller
            // function0
push1 0x00  // stack: [0x00]
dup1        // stack: [0x00, 0x00]
retf        // return to callf with stack: [0x00, 0x00]
```

A valid example of an EOFv1 contract with rjump:

```
// bytecode

// mnemonic

0xef00      // magic
0x01        // version
0x01        // type section marker
0x0004      // type section length
0x02        // code section marker
0x0001      // num of code sections
0x0008      // code section length
0x03        // data section marker
0x0000      // data section length
0x00        // end header
            // type section start
0x00000002  // entry point metadata (0 inputs, 0 outputs, max stack height 2)
            // code section start
            // entry point
rjump 0x0001// jumps to `pc + 1 + 0x0001`
invalid     // jumped over
push1 0x00  // stack: [0x00]
dup1        // stack: [0x00, 0x00]
return      // return to caller
```

## Tooling

Tooling should be kept to a minimum outside of internal testing.

### [Foundry](https://book.getfoundry.sh/)

Using Foundry can be done by implementing a simple deployer library. This requires `ffi` to be
enabled in the `Forge.toml` file or the `--ffi` argument to the CLI. Foundry is the newest and best
designed development environment.

Building a library to integrate the Sway compiler can be done with minimal effort and minor
maintenance requirements. This is how Vyper, Huff, and Yul currently handle Foundry "integration".

Here is a [Vyper Deployer Library](https://github.com/pcaversaccio/snekmate/blob/main/lib/utils/VyperDeployer.sol) and its [Example Usage](https://github.com/pcaversaccio/snekmate/blob/main/test/tokens/ERC20.t.sol).

The main drawback to this approach is that Foundry only supports Solidity officially, so while
contracts may be written in Sway, tests will need to be written in Solidity. This may change if Sway
gains enough support to justify integrating officially.

### [Hardhat](https://hardhat.org/)

Using Hardhat can be done by implementing a simple deployer plugin using Typescript.

Hardhat has been around for longer than Foundry and is still a popular option, but is nowhere near
the fastest in terms of test time and its Javscript/Typescript interface to smart contracts is
largely unintuitive and more copmlex.

Here is a [Vyper Deployer Plugin](https://github.com/NomicFoundation/hardhat/tree/main/packages/hardhat-vyper) and its [Example Usage](https://github.com/jtriley-eth/offensive_vyper)

### [Ethers](https://github.com/gakonst/ethers-rs/) + [REVM](https://github.com/bluealloy/revm)

This approach would require a new development environment and is by far the most work. This would
allow contracts to be written in Sway and tests to be written in Rust.

Ethers is a rust library to interface with Ethereum in a high-level API.

REVM is a rust implementation of the EVM execution engine.

> Notice: REVM is unrelated to the Reth code-stealing allegations, REVM is strictly the execution
> environment, Reth is an Ethereum client.

For reference on what an Ethers + REVM development environment is like, see Foundry.

# Drawbacks

[drawbacks]: #drawbacks

- Upfront engineering cost
- Patchy tooling support (unless testing environment developed internally)
- Maintenance (unless high level intermediate language used)
- EOFv1 Format Change (unless high level intermediate language used)
- Standard Library partial rewrite

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

The primary alternative would be to write a transpiler from Fuel VM Assembly to EVM assembly.

Transpiled languages tend to make unacceptable tradeoffs in the context of a resource constrained
environment like the EVM. Other languages have tried transpiling with minimal success.

# Prior art

[prior-art]: #prior-art

## Existing Single Arch Smart Contract DSLs

### Solidity

- most popular
- in-line assembly support
- object oriented
- stores variables on the stack
- code sharing via inheritance, external libraries, internal libraries, and modules
- focuses on being generic
- poor type system
- bad developer guards

```sol
// example
contract ValueHolder {
    event ValueSet(uint256 indexed value);

    uint256 public value;

    function set(uint256 _value) external {
        value = _value;
        emit ValueSet(_value);
    }
}
```

### Vyper

- next most popular
- no code sharing, no library support, no inheritance
- dynamic types need bounds at compile time
- no in-line assembly
- stores variables in memory
- smaller binary size

```py
# example
event ValueSet:
    value: uint256

value: public(uint256)

@external
def set(value: uint256):
    self.value = value
    log ValueSet(value)
```

### Fe

- rust-like
- underdeveloped
- small community
- abstract data types unsupported

```rs
// example
struct ValueSet {
    pub value: u256,
}

contract ValueHolder {
    value: u256

    fn value(self) -> u256 {
        self.value
    }

    fn set(mut self, mut ctx: Context, value) {
        self.value = value;
        ctx.emit(ValueSet(value: value));
    }
}
```

### Yul

- assembly language
- high level control flow
- largely used in mev and compiler developer communities
- footgun hell

```sol
// example
object "ValueHolder" {
    code {
        datacopy(0x00, dataoffset("runtime"), datasize("runtime"))
        return(0x00, datasize("runtime"))
    }
    object "runtime" {
        code {
            switch shr(0xe0, calldataload(0x00))

            case 0x3fa4f245 {
                mstore(0x00, sload(0x00))
                return(0x00, 0x20)
            }

            case 0x60fe47b1 {
                let value := calldataload(0x04)
                sstore(0x00, value)
                log2(
                    0x00,
                    0x00,
                    0x012c78e2b84325878b1bd9d250d772cfe5bda7722d795f45036fa5e1e6e303fc,
                    value
                )
                return(0x00, 0x00)
            }

            revert(0x00, 0x00)
        }
    }
}
```

## Existing Multi Arch Smart Contract DSLs

### Reach

- targets both Ethereum and Algorand
- poor syntax
- have never seen an engineer use it

This language is poorly documented and unusually complex, so here is an [ERC20 example](https://github.com/reach-sh/reach-lang/blob/master/examples/ERC20/index.rsh).

# Unresolved questions

[unresolved-questions]: #unresolved-questions

- Internal Tooling
- Intermediate Language (if any)
- EOFv1 Format Change
- Foundry Official Support

# Future possibilities

[future-possibilities]: #future-possibilities

This would create a well-designed, rust-like language for the EVM ecosystem, which is currently
non-existent. This will allow EVM engineers to design more secure smart contracts on EVM and Fuel VM
alike, will boost Sway's total TVL in the [Defi LLama Language TVL Listings](https://defillama.com/languages),
and will spark interest in the language enough to bring engineers into the Fuel ecosystem with
marginal learning overhead.

## ERC Compliant Casing Option

A nice-to-have specifically for the EVM would be to have a way to modify the function signature and
selector to conform to "Etheruem Request for Comment" standards. Sway follows patterns of Rust,
which, according to the [Rust Style Guide](https://doc.rust-lang.org/1.0.0/style/style/naming/README.html),
functions should be defined in snake case, that is all lower case with words separated by
underscores. However, ERC standards almost exclusively define external functions in camel case, that
is the first word is lower case and following words have their first letter capitalized. This may
create issues with formatting, such as in Vyper contracts that conform to the Python style guide,
[PEP8](https://peps.python.org/pep-0008/#function-and-variable-names) where either all functions
must be in camel case, breaking style guides, or only internal functions may be snake case. The
[Snekmate Repository](https://github.com/pcaversaccio/snekmate) follows the latter pattern.

To avoid the issue of having to break style conventions, having an optional function attribute to
alter the final function signature may be desireable. The following is what this may look like.

```rs
abi Erc20 {
    fn balance_of(owner: Identity) -> b256;
    // -- snip --
}

impl Erc20 for Contract {
    #[camelcase]
    fn balance_of(owner: Identity) -> b256 {
        // -- snip --
    }
    // -- snip --
}
```

This would change the final ABI from the first JSON snippet to the second.

Without `#[camelcase]` attribute (default).

```json
{
    "name": "balance_of",
    "type": "function",
    "inputs": [
        { "name": "owner", "type": "address" }
    ],
    "outputs": [
        { "name": "", "type": "uint256" }
    ]
}
```

With `#[camelcase]` attribute.

```json
{
    "name": "balanceOf",
    "type": "function",
    "inputs": [
        { "name": "owner", "type": "address" }
    ],
    "outputs": [
        { "name": "", "type": "uint256" }
    ]
}
```

This changes the external ABI as well as the function selector.

| signature             | selector     |
| --------------------- | ------------ |
| `balance_of(address)` | `0xb144adfb` |
| `balanceOf(address)`  | `0x70a08231` |
