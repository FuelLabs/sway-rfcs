- Feature Name: `error_type`
- Start Date: 2024-11-18
- RFC PR: [FuelLabs/sway-rfcs#43](https://github.com/FuelLabs/sway-rfcs/pull/43)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC aims to standardize error handling in Sway so that there is a
deliberate and clear way to produce error messages that are easily consumable by
language tools while keeping error strings out of on-chain artifacts.

# Motivation

[motivation]: #motivation

Currently, reverting a Sway program only produces an opaque error code.
Sometimes this code is unusual enough that with the source code of the contract
it is possible to figure out what is going on, but a lot of the time it's a
meaningless number that only means that some failure happened somewhere.

It's not reasonable to expect people to be able to debug Sway programs in these
conditions, so we need to improve this.

We want irrecoverable errors to carry user defined error messages and source
information about where the error was invoked. We want those error types to be
something that can also be used for recoverable errors.

To this end we want to introduce a mechanism that makes error codes an
understandable part of the ABI, and language features that allow the user to
define error messages, error types and invoke those errors with the appropriate
information being generated.

We also want recoverable errors to connect to this mechanism so that all error
handling in a given Sway program can go through one or a small set of user
defined types and error strings don't affect the final bytecode size.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

## Error types

Error types are special enums that allow developers to signal that each variant
is associated with an error message.

An error type implements the `Error` trait, but it is not recommended that you
do so manually.

Instead, to create a new error type, use the following syntax and annotations on
an enum:

```sway
#[error_type]
enum MyError {
  #[error("error A")]
  A: (),
  #[error("error B")]
  B: (u64, u8),
}
```

This will automatically implement the `Error` marker trait for this enum
and let the compiler know what error messages correspond to what variants of
the enum.

It will also populate the ABI specification file with error messages in the
metadata of the enum type. Allowing users to check the meaning of an error
without the need to store and decode error messages on chain.

For instance, the following contract method may return a `MyError` variant which
will be compact but can still be associated with an error message:

```sway
fn do_something(self) -> Result<(), MyError> {
  // ...
  return Err(MyError::A); // user will know that this means "error A"
  // ...
}
```

## `panic`

When encountering an irrecoverable error in a Sway program, it is customary to
revert and produce an informative error code.

The recommended way of doing this is to use the `panic` intrinsic.

`panic` is a compiler intrinsic that will
produce a unique revert code for each of its invocations and populate the ABI
specification file with a list of such codes and corresponding information about
where it was invoked and with what kind of arguments.

If all you want is an error message, you can panic with a string literal:

```sway
// ...
// some error happened
panic("some error happened");
```

But if you want more functionality, you should use an error type:

```sway
panic(MyError::A);
// ...
panic(MyError::B((1024, 42)));
```

Panicking with an error type will do two things: log the error so that a
corresponding log receipt is produced, and revert with an error code that
corresponds to the invocation location.

## Revert codes

All revert codes after `0xffff_ffff_ffff_0000` are reserved for use by the
compiler and standard library.

Codes produced by `panic` start at `0xffff_ffff_0000_0000` but may be allocated
at will by the compiler, they are not guaranteed to be sequential.

Let's go through how to decode a set of error codes for the following example
program:

```sway
script;

#[error_type]
enum MyError {
  #[error("error A")]
  A: (),
  #[error("error B")]
  B: (u64, u8),
}

pub fn main(a: u8) {
  match a {
    0 => panic("a str panic"),
    1 => panic("another str panic"),
    2 => panic(MyError::A),
    3 => panic(MyError::A),
    4 => panic(MyError::B((1024, 42))),
    5 => panic(MyError::B((0, 16))),
    _ => {}
  }
}
```

this would produce, when compiled, the following ABI specification file:

```json

{
  "programType": "script",
  "specVersion": "1",
  "encodingVersion": "1",
  "concreteTypes": [
    {
      "type": "()",
      "concreteTypeId": "2e38e77b22c314a449e91fafed92a43826ac6aa403ae6a8acb6cf58239fbaf5d"
    },
    {
      "type": "enum MyError",
      "concreteTypeId": "44781f4b1eb667f225275b0a1c877dd4b9a8ab01f3cd01f8ed84f95c6cd2f363",
      "metadataTypeId": 1
    },
    {
      "type": "u8",
      "concreteTypeId": "c89951a24c6ca28c13fd1cfdc646b2b656d69e61a92b91023be7eb58eb914b6b"
    }
  ],
  "metadataTypes": [
    {
      "type": "(_, _)",
      "metadataTypeId": 0,
      "components": [
        {
          "name": "__tuple_element",
          "typeId": 2
        },
        {
          "name": "__tuple_element",
          "typeId": "c89951a24c6ca28c13fd1cfdc646b2b656d69e61a92b91023be7eb58eb914b6b"
        }
      ]
    },
    {
      "type": "enum MyError",
      "metadataTypeId": 1,
      "components": [
        {
          "name": "A",
          "errorMessage": "error A",
          "typeId": "2e38e77b22c314a449e91fafed92a43826ac6aa403ae6a8acb6cf58239fbaf5d"
        },
        {
          "name": "B",
          "errorMessage": "error B",
          "typeId": 0
        }
      ]
    },
    {
      "type": "u64",
      "metadataTypeId": 2
    }
  ],
  "functions": [
    {
      "inputs": [
        {
          "name": "a",
          "concreteTypeId": "c89951a24c6ca28c13fd1cfdc646b2b656d69e61a92b91023be7eb58eb914b6b"
        }
      ],
      "name": "main",
      "output": "2e38e77b22c314a449e91fafed92a43826ac6aa403ae6a8acb6cf58239fbaf5d",
      "attributes": null
    }
  ],
  "loggedTypes": [
    {
      "logId": "4933727799282657266",
      "concreteTypeId": "44781f4b1eb667f225275b0a1c877dd4b9a8ab01f3cd01f8ed84f95c6cd2f363"
    }
  ],
  "messagesTypes": [],
  "configurables": [],
  "errorCodes": {
    "18446744069414584320": {
        "pos": {
          "file": "main.sw",
          "line": 13,
          "col": 10
        },
        "logId": null,
        "msg": "a str panic"
    },
    "18446744069414584321": {
        "pos": {
          "file": "main.sw",
          "line": 14,
          "col": 10
        },
        "logId": null,
        "msg": "another str panic"
    },
    "18446744069414584322": {
        "pos": {
          "file": "main.sw",
          "line": 15,
          "col": 10
        },
        "logId": "4933727799282657266",
        "msg": null,
    },
    "18446744069414584323": {
        "pos": {
          "file": "main.sw",
          "line": 16,
          "col": 10
        },
        "logId": "4933727799282657266",
        "msg": null,
    }
    "18446744069414584324": {
        "pos": {
          "file": "main.sw",
          "line": 17,
          "col": 10
        },
        "logId": "4933727799282657266",
        "msg": null,
    },
    "18446744069414584325": {
        "pos": {
          "file": "main.sw",
          "line": 18,
          "col": 10
        },
        "logId": "4933727799282657266",
        "msg": null,
    }
  }
}
```

If you run the script with argument `0`, you will get a revert code
`18446744069414584320` and no log receipts. Looking in the `"errorCodes"`
section of the ABI spec, you can see that this code corresponds to no log and a
message `"a str panic"`.

If you run the script with argument `4`, you will get a revert code
`18446744069414584324` and a log receipt. Looking in the `"errorCodes"`
section of the ABI spec, you can see that this code corresponds
to no immediate message and a `"logId": "4933727799282657266"`. In
`"loggedTypes"` you can see that this id corresponds to a `"concreteTypeId":
"44781f4b1eb667f225275b0a1c877dd4b9a8ab01f3cd01f8ed84f95c6cd2f363"`, which in
turn corresponds to type `"enum MyError"` with a `"metadataTypeId": 1`, which in
turn contains variants as components with an `errorMessage` field. When decoding
the corresponding log, you'll get a `MyError::B((1024, 42))` value which
corresponds to error message `"error B"`.

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Error types

Error types are recognized using the `Error` trait, but it is a simple marker
that does not carry behavior (for now).

```sway
trait Error: AbiEncode {}
```

We need to introduce two new annotations.

`#[error_type]` generates an implementation of `Error` for a given type
and should let the compiler know that it should carry around error message
information about this type.

`#[error("")]` should only be usable in a `#[error_type]` marked enum definition,
and to not exhaustively mark variants of such an enum with an error message
annotation is considered an error.

When generating ABI files, the compiler should populate the `"metadataTypes"`
section accordingly and include a `"errorMessage"` field in the components of
marked enums.

## `panic` intrinsic

The `panic` intrinsic has two modes which determine what kind of fields are
produced in the (new) `"errorCodes"` section of the ABI file.

Either it is used with a `str` literal (or a const-evaluable such value) and
produces `"msg"` fields. Or it is used with an `Error` implementing type, and
produces `"logId"` fields. Any other use is an error.

In any valid case, it also records in the `"errorCodes"` section location
information about every `panic` invocation's position in the codebase.

As for runtime behavior, if the argument is an error type, it logs it before
reverting, and in every valid case, it eventually reverts with a unique error
code for every `panic` invocation, which is recorded in the `"errorCodes"`
section.

## Integration considerations

Manual reverts with custom codes should still be available to developers, but
discouraged.

The standard library should henceforth strive to use error types for both
recoverable and irrecoverable errors. Ideally the standard library should
never produce a revert code that doesn't have a corresponding documented error
message.

We should also introduce compiler warnings for manually producing revert codes
that may conflict with either the reserved code range or the auto-generated panic
code range.

SDK integration of this feature is open ended, but we should at least aim to
be able to use error message information to decode revert codes and error types
that are directly returned.

The existing special error codes produced by the standard library (such as `FAILED_ASSERT_SIGNAL`) should be migrated
to use this mechanism.


# Drawbacks

[drawbacks]: #drawbacks

Using a special intrinsic is the main drawback of this solution for a number of reasons.

It muddles how intrinsics are identified since unlike other compiler intrinsics
`panic` does not have a `__` prefix. 
This is necessary since it needs to
be directly invoked at the error site for the location information to be
meaningful.

It also pollutes the namespace with yet another reserved word.

And ultimately it moves more complexity to the compiler rather than let the user define it.
This is a shared problem with the error type annotations.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

There are drawbacks to moving more special behavior the compiler. However, we
do not have sufficiently powerful meta-programming features that would allow
developers to define features of this caliber. Therefore, the language must
shoulder the burden of this complexity.

Given the benefits of having standardized errors, these trade-offs seem
acceptable, so long as we allow the solution to be extended in the future to
be more user defined. The `Error` trait is the main vector of such future
changes in this case.

Letting the errors be populated directly in the bytecode would be a lot simpler,
but it is not desirable because it extends the size of the binary for no gain.

Moreover, the question of the location of error strings can be asked. Why
put them in the ABI specification file? ABI files are soon to benefit from
a registry that will allow users to easily fetch them, they already contain
type metadata that can be extended, and they ultimately are our equivalent to
headers, encompassing all the required information to call a contract and get
a meaningful answer. Errors are part of making this answer meaningful and it is
typical for error messages to live in headers.

If we do not specify some kind of error standard, debugging any sort of complex
Sway error will remain extremely difficult and supporting Sway contracts may be
a nigh impossible task.

# Prior art

[prior-art]: #prior-art

This RFC is somewhat inspired by Rust's error library ecosystem. We do not
have enough metaprogramming facilities to allow users to define their own way
of producing errors, but one can identify two kinds of Rust error handling
libraries. Those that like `anyhow` care most about letting the user add some
string based error context. And those like `thiserror` that allow one to build
complex error types.

We attempt here to cater to both crowds through `panic`'s dual modes.

Moreover, Ethereum style embedding of errors in a `b256` isn't practical for us
or generally desirable since the FuelVM uses 64 bit error codes and we aim to
minimize the footprint of errors on deployed contracts.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

The extent of the SDK integration of this feature is quite open ended. But
implementation of this should give a good enough base to decide how much support
we want and to extend it in the future.

# Future possibilities

[future-possibilities]: #future-possibilities

In the future we may want to include more metadata for panic invocations or
error types.

We may also allow error strings to be format strings so that you may use your
enum's values in the error message.

Improvements to our const evaluation facilities may also prompt a rework of the
`Error` trait so that the error messages are generated arbitrarily through
a `const fn` instead of statically defined through annotations. This would also
allow us to do away with custom annotations.

