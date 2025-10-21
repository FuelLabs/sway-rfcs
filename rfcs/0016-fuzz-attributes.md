- Feature Name: `fuzz_attributes`
- Start Date: 2025-09-09
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC introduces parsing support for `#[fuzz]` and `#[fuzz_param]` attributes in Sway to enable fuzz testing capabilities. These attributes allow developers to define fuzz test functions and specify parameters for fuzz testing operations.

# Motivation

[motivation]: #motivation

Fuzz testing is a critical software testing technique that helps discover edge cases, security vulnerabilities, and unexpected behaviors by feeding random or semi-random inputs to functions. Currently, Sway lacks native support for fuzz testing attributes, making it difficult for developers to implement comprehensive testing strategies that include fuzzing.

The introduction of `#[fuzz]` and `#[fuzz_param]` attributes will:
- Enable systematic fuzz testing of Sway functions
- Provide a standardized way to define fuzz test parameters
- Improve code quality and security through automated testing of edge cases
- Align with modern testing practices found in other programming languages

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

## Basic Fuzz Testing

The `#[fuzz]` attribute marks a function as a fuzz test. This function will be executed with randomly generated inputs to test for unexpected behaviors:

```sway
#[fuzz]
fn fuzz_my_function(input: u64) {
    // Test logic that will be executed with random u64 values
    let result = my_function(input);
    // Add assertions or checks here
}
```

## Parameterized Fuzz Testing

The `#[fuzz_param]` attribute allows you to specify parameters for more controlled fuzz testing:

```sway
#[fuzz]
#[fuzz_param(name = "input", iteration = 1000)]
#[fuzz_param(name = "seed", min_val = 0, max_val = 100)]
fn fuzz_with_params(input: u64, seed: u32) {
    // This will run 1000 iterations with:
    // - input: random u64 values
    // - seed: random u32 values between 0 and 100
}
```

## Usage Constraints

- A function cannot have both `#[test]` and `#[fuzz]` attributes
- The `#[fuzz]` attribute expects no arguments
- Multiple `#[fuzz_param]` attributes are allowed per function
- Only one `#[fuzz]` attribute is allowed per function
- `#[fuzz_param]` supports the following parameters:
  - `name`: The parameter name to configure
  - `iteration`: Number of test iterations
  - `min_val`: Minimum value for numeric types
  - `max_val`: Maximum value for numeric types

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

## Attribute Implementation

This RFC introduces two new attribute kinds:

1. **`AttributeKind::Fuzz`**: Marks a function as a fuzz test
2. **`AttributeKind::FuzzParam`**: Configures parameters for fuzz testing

## Parsing Infrastructure

The implementation adds:

- New attribute constants for fuzz testing recognition
- Enhanced function detection to identify fuzz functions
- Modified test entry processing to handle fuzz functions alongside regular tests
- Validation logic to ensure proper attribute usage

## Attribute Syntax

### `#[fuzz]` Attribute
```sway
#[fuzz]
fn function_name(parameters) {
    // test body
}
```

### `#[fuzz_param]` Attribute
```sway
#[fuzz_param(name = "param_name", option = value)]
```

Supported options:
- `name`: String identifying the parameter
- `iteration`: Integer specifying test iterations
- `min_val`: Minimum value for the parameter
- `max_val`: Maximum value for the parameter

## Validation Rules

The compiler enforces the following constraints:

1. **Mutual Exclusivity**: Functions cannot have both `#[test]` and `#[fuzz]` attributes
2. **Argument Validation**: `#[fuzz]` attributes must not contain arguments
3. **Parameter Consistency**: `#[fuzz_param]` attributes must reference valid function parameters
4. **Attribute Limits**: Only one `#[fuzz]` attribute per function is allowed

## Integration with Test Framework

Fuzz functions are processed similarly to test functions but with additional parameter generation logic. The test entry processing system is extended to:

1. Identify functions marked with `#[fuzz]`
2. Parse associated `#[fuzz_param]` configurations
3. Generate appropriate test entry points for fuzz execution

# Drawbacks

[drawbacks]: #drawbacks

1. **Parsing Complexity**: Adds additional complexity to the attribute parsing system
2. **Testing Infrastructure**: Requires corresponding runtime support for actual fuzz execution
3. **Maintenance Overhead**: Introduces new syntax that must be maintained and documented

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

## Why This Design

The attribute-based approach aligns with Sway's existing testing infrastructure (`#[test]`) and provides a familiar syntax for developers. The separation of `#[fuzz]` and `#[fuzz_param]` allows for both simple and complex fuzz testing scenarios.

## Alternative Approaches

1. **Function Naming Convention**: Using naming patterns like `fuzz_*` instead of attributes
   - Rejected: Less explicit and harder to configure
2. **Macro-based Approach**: Using macros to generate fuzz tests
   - Rejected: Would require more complex macro system implementation
3. **Separate File Format**: External configuration files for fuzz parameters
   - Rejected: Separates test configuration from code

## Impact of Not Implementing

Without this feature, Sway developers would need to:
- Implement custom fuzz testing frameworks
- Rely on external tools that may not integrate well with Sway
- Miss potential security vulnerabilities and edge cases

# Prior art

[prior-art]: #prior-art

Several programming languages provide fuzz testing support:

1. **Rust**: The `cargo-fuzz` tool and `#[quickcheck]` attributes
2. **Go**: Built-in fuzz testing with `func FuzzXxx(*testing.F)` pattern
3. **JavaScript**: Libraries like `fast-check` for property-based testing
4. **Haskell**: QuickCheck library with property-based testing

The proposed design draws inspiration from these existing implementations while adapting to Sway's attribute system and syntax conventions.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

1. **Runtime Integration**: How will the parsing infrastructure integrate with the actual fuzz testing runtime?
2. **Parameter Generation**: What algorithms will be used for generating fuzz inputs?
3. **Configuration Expansion**: Should additional `#[fuzz_param]` options be supported in the future?
4. **Performance Considerations**: How will fuzz testing performance be optimized for large parameter spaces?

# Future possibilities

[future-possibilities]: #future-possibilities

1. **Advanced Parameter Types**: Support for custom parameter generators and complex data types
2. **Coverage-Guided Fuzzing**: Integration with coverage analysis for more effective fuzzing
3. **Shrinking**: Automatic minimization of failing test cases
4. **Property-Based Testing**: Extension to support property-based testing paradigms
5. **Integration with CI/CD**: Native support for running fuzz tests in continuous integration
6. **Custom Generators**: Allow developers to define custom input generators for specific types
7. **Corpus Management**: Support for maintaining and evolving fuzz test input corpora

The parsing infrastructure introduced by this RFC provides a foundation for these future enhancements while maintaining backward compatibility.