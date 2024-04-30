/// This file contains detailed examples of the syntax and semantics of references.

/// # Major design decisions
/// 1. References have their own mutability and can point to mutable or immutable values.
///    Thus, we support mutable references to mutable values and any combination of the two.
///    Target mutability is not automatically taken over from the referenced value, and
///    must be specified explicitly. E.g.:
///
///    let mut m_i = 0u64;
///    let r_m_i = &mut m_i; // Immutable reference to a mutable `m_i`.
///    let mut m_r_m_i = &mut m_i; // Mutable reference to a mutable `m_i`.
///    let r_m_i = &m_i; // Immutable reference to an immutable (via reference) `m_i`.
///    let mut r_m_i = &m_i; // Mutable reference to an immutable (via reference) `m_i`.
///
///    The need to specify `mut` in the second case is likely cumbersome because it will be
///    the default wanted behavior, but it gives us clear syntax later on when having references
///    in aggregates and when sending and returning them from functions.
///
///    let i = 0u64;
///    let r_m_i = &mut i; // ERROR: `i` is not mutable.
///
/// 2. & operator defines the reference. * operator is dereferencing.
///
/// 3. . and [] operators also dereference if the reference is a reference to a struct/tuple or array, respectively.
///
/// 4. `&mut T` coerces into `&T`.

fn built_in_types_and_enums() {
    let i = 0u64;
    let mut m_i = 0u64;
    let x = 0u64;

    // ---- Immutable references to mutable or immutable built-in types. ----
    let r_i = &i; // Reference to an immutable `u64`: r_i: &u64.
    let r_m_i = &mut m_i; // Reference to a mutable `u64`: r_m_i: &mut u64. The reference itself is not mutable.
    let r_n_m_i = &m_i; // Reference to a `u64`: r_n_m_i: &u64. It is not possible to change `m_i` via the reference although it is per se mutable.
    let err = &mut i; // ERROR: `i` is not mutable.

    *r_i = 1; // ERROR: Referenced value is not mutable.
    r_1 = &x; // ERROR: `r_1` is not a mutable reference.

    *r_m_i = 1; // OK: Changes `m_i`.
    r_m_i = &x; // ERROR: `r_m_i` is not a mutable reference.
    // ----

    // ---- Mutable references to mutable or immutable built-in types. ----
    let mut r_i = &i; // Mutable reference to immutable a `u64`: r_i: &u64.
    let mut r_m_i = &mut m_i; // Mutable reference to a mutable `u64`: r_i: &mut u64.

    *r_i = 1; // ERROR: Referenced value is not mutable.
    r_1 = &x; // OK: `r_1` is mutable.

    *r_m_i = 1; // OK: Changes `m_i`.
    r_m_i = &x; // OK: `r_m_i` is mutable.
    // ----

    // ---- Coersion of `&mut T` into `&T` ----
    r_i = r_m_i;
    // ----

    // Accessing built-in types and enums over reference via dereferencing operator (*).
    let a = 2 * *r_i; 

    let e = Enum::A;
    let r_e = &e;

    match *e { // Actually, there is (mostly) no need to dereference (*) here. See the section on Pattern Matching below.
        _ => {}
    }
}

fn structs_and_tuples() {
    // Same as above with the addition that the . operator dereferences the reference.
    // Operator . is defined for references to structs and tuples using this recursive definition:
    //   <reference>.<field/element name> := (*<reference>).<field/element name>.

    let mut s = Struct { x: 0u64 };
    let r_s = &mut s; // `r_s` is immutable reference to a mutable struct.

    r_s.x = 1; // Same as `(*r_s).x = 1`.

    match *r_s { // Actually, there is (mostly) no need to dereference (*) here. See the section on Pattern Matching below.
        _ => {}
    }

    let mut t = (0u64, 0u64);
    let r_t = &mut t; // `r_s` is immutable reference to a mutable tuple.

    r_t.0 = 1; // Same as `(*r_t).0 = 1`.

    match *r_t { // Actually, there is (mostly) no need to dereference (*) here. See the section on Pattern Matching below.
        _ => {}
    }

    let x = r_t.0 + r_t.1;

    let r_r_r_s = &s;
    let x = r_r_r_s.x; // Same as `(***r_r_r_s).x`.
}

fn arrays() {
    // Same as above with the addition that the [] operator dereferences the reference.
    // Operator [] is defined for references to arrays using this recursive definition:
    //   <reference>[<index>] := (*<reference>)[<>]

    let mut a = [0, 0, 0];
    let r_a = &a;

    r_a[0] = 1; // Same as `(*r_a)[0] = 1`.

    let x = r_a[0] + r_a[1];

    let r_r_r_a = &a;
    let x = r_r_r_a[x]; // Same as `(***r_r_r_a)[x]`.
}


/// # Embedding references in aggregates
/// A reference can be a part of an aggregate.
/// E.g., we can have an array of references, or a struct field that is a reference.
/// In the following examples, references to the struct `A` get embedded in aggregates.
struct A {
    x: u64,
}

/// The mutability of references `a_i` and `a_m` is the mutability of
/// the aggregated object.
struct B {
    r_i_a: &A, // Reference to an immutable `A`.
    r_m_a: &mut A, // Reference to a mutable `A`.
}

/// References allow to define recursive structures.
struct Node<T> {
    parent: Option<&Node<T>>,
    data: T,
}

fn embedding_in_aggregates() {
    let mut m_a_1 = A { x: 0 };
    let mut m_a_2 = A { x: 0 };
    let mut m_b = B { r_i_a: &m_a_1, r_m_a: &mut m_a_1 };

    m_b.r_i_a = &m_a_2;
    m_b.r_m_a = &m_a_2;

    m_b.r_m_a.x = 1; // OK.

    let i_b = B { r_i_a: &m_a_1, r_m_a: &mut m_a_1 };

    i_b.r_i_a = &m_a_2; // ERROR: `i_b` is immutable, thus `r_i_a` is an immutable reference.
    i_b.r_m_a = &m_a_2; // ERROR: `i_b` is immutable, thus `r_m_a` is an immutable reference.

    m_b.r_m_a.x = 1; // OK: `r_m_a` references a mutable value.

    // Same is with arrays, tuples, and enums.
    let a = [&m_a_1, &m_a_2];
}


/// # Referencing references
/// It is possible to reference references.
fn referencing_references() {
    let mut a = A { x: 0 };
    let mut m_r_a = &mut a;
    let mut m_r_m_r_a = &mut m_r_a;
    let r_m_r_m_r_a = &mut m_r_a;

    let x = r_m_r_m_r_a.x; // OK: Operator . dereferences recursively.
    let x = ***r_m_r_m_r_a.x; // OK.
    let x = **r_m_r_m_r_a.x; // OK.
}


/// # References and pattern matching
/// It is possible to both match references (`match <reference expression> { ... }`)
/// and to declare pattern variables as refrences via `ref` keyword.
///
/// When pattern matching a reference:
/// - in case of a requirement we actually match the value behind the reference.
/// - in case of a variable declaration, a reference is declared. That reference is `&mut` if the matched reference is `&mut`.
/// - as with other variables declared in pattern matching, the reference variable itself is immutable unless declared as `mut`.
///
/// Thus, dereferencing matched references is usually not necessary (and is actually
/// very likely unwanted because it would potentially create unnecessary copies).
/// It only affects the definition of variables declared in match arms,
/// if they are going to be references or not.

enum E {
    A: (&mut A),
    B: (&B),
    T: (&mut u64, &u64)
}

fn references_and_pattern_matching() {
    let mut x = 123u64;

    match x {
        mut a => {
            a = 22; // `a` is a mutable copy of `x`. `x` remainds unchanged.
                    // We will issue a warning in case only `mut` is used,
                    // because it is very likely that `ref mut` was intended.
        },
        ref a => assert_eq(*a, x), // `a` is `&u64` referencing `x`.
        ref mut a => { // `a` is `&mut u64` referencing `x`. OK because `x` is mutable, otherwise an error.
            *a = 44; // Changes `x`.
            a = &mut 321; // ERROR: `a` itself is not mutable. It just refers to a mutable value.
        },
        _ => {},
    }

    match &x {
        0 => {}, // Matching `x` with `0`.
        &1 => {} // OK. Matching `x` with `1`.
        &&2 => {} // ERROR: Expected &u64 if referencing constants is used.
        a => assert_eq(*a, x), // `a` is `&u64` referencing `x`.
        mut a => {// `a` is a mutable reference to `&u64` referencing `x`.
            a = &33; // Changes `a` to reference the result of the expression `33`.
                     // `x` remains unchanged.
        },
        ref a => {}, // `a` is `& &u64`, a reference referencing the reference to `x`.
        ref mut a => { // `a` is `&mut &u64`, a reference referencing the mutable reference to `x`.
            *a = &55; // Changes `a` to reference the result of the expression `55`.
                      // `x` remains unchanged.
            a = &mut &321; // ERROR: `a` itself is not mutable. It just refers to a mutable value.
        },
        _ => {},
    }

    // Similar as above.
    match &&&x {
        0 => {}, // Matching `x` with `0`.
        &1 => {} // ERROR.
        &&&2 => {} // OK.
        a => assert_eq(***a, x), // `a` is `&&&u64` referencing `x`.
        mut a => {// `a` is a mutable reference to `&&&&u64` referencing `x`.
            a = &&& 33; // Changes `a` to reference the result of the expression `33`.
                        // `x` remains unchanged.
        },
        ref a => {}, // `a` is `& &&&u64`.
        ref mut a => { // `a` is `&mut &&&u64`.
            *a = &&& 55; // Changes `a` to reference the result of the expression `55`.
                         // `x` remains unchanged.
            a = &mut &&&321; // ERROR: `a` itself is not mutable. It just refers to a mutable value.
        },
        _ => {},
    }

    match &mut x {
        0 => {}, // Matching `x` with `0`.
        &mut 1 => {} // OK. Matching `x` with `1`.
        &1 => {} // ERROR. Must be `&mut`.
        a => assert_eq(*a, x), // `a` is `&mut u64` referencing `x`.
        mut a => {// `a` is a mutable reference to `&mut u64` referencing `x`.
            a = &mut 33; // Changes `a` to reference the result of the expression `33`.
                         // `x` remains unchanged.
        },
        ref a => {}, // `a` is `& &mut u64`, a reference referencing the reference to mutable `x`.
        ref mut a => { // `a` is `&mut &mut u64`, a reference referencing the mutable reference to mutable `x`.
            *a = &mut 55; // Changes `a` to reference the result of the expression `55`.
        },
        _ => {},
    }

    let mut a = A { x: 0 };
    let e = E::A(&mut a);

    match e { // Note that `e` itself is not a reference.
        E::A( A { x: 111 }) => {}, // Matches the referenced value's `x` against 111. 
        E::A( &mut A { x: 111 }) => {}, // Same as above.
        E::A( &A { x: 111 }) => {}, // ERROR: Must be `&mut`.
        E::A(a) => { // `a` is `&mut A`.
            a.x = 222; // The original value `a.x` is changed.
        },
        E::B( B { r_i_a: A { x: 111 }, .. }) => {},
        E::T(x, 555) => { // Match the second value (dereferenced) against 555.
            *x = 222; // `x` is a reference to a mutable `u64`.
        },
        E::T(_, &777) => {} // OK.
        _ => {},
    };

    // Detailed behavior in case of referencing aggregates and embedding references will be 
    // defined at the later stage and prior to the implementation of the feature.
}


/// # Referencing parts of aggregates
/// References can reference parts of aggregates.
/// This allows avoiding copying of values when e.g. passing an array element to a function.
/// At the moment, we cannot pass individual array elements by reference to functions.
///
/// On the other hand, referencing parts of aggregates can lead to dangling references.
/// Technically, they might not be dangling, in a sense that the occupied memory will be
/// available and valid (ensured by the compiler for all code that does not involves direct
/// pointer manipulation). But semantically they could, in a sense e.g., that we have a reference
/// to an, e.g., array element, of an array that is not used anymore.
///
/// Library authors will need to take a special care, either not to provide possibility for
/// dangling references, or to warn the library users about potential possibility of dangling
/// references.
///
/// Let's take a `Vec` as an example. If `Vec` provides access to the elements, only by returning
/// the copies, the possibility of dangling references is removed by the API design.
/// But if it provides a method like `get_elem_by_ref(self, index: usize)` we can have a situation where
/// the caller keeps the reference to an element, calls, e.g., `Vec::clear()`, and by mistake continues
/// using the reference to a semantically non-existing value.
///
/// The question if something can be done on the language level to avoid dangling references
/// is out of scope of the References RFC.
struct C {
    a: A,
    t: (u64, u64)
}

fn referencing_parts_of_aggregates() {
    let mut c = C { a: A { x: 0 }, t: (0, 0) };
    let r_c_a = &mut c.a;
    let r_c_a_x = &mut c.a.x;
    let r_c_t_0 = &mut c.t.0;
    let r_c_t_1 = &mut c.t.1;

    r_c_a.x = 1;
    *r_c_a_x = 2;

    // We can reuse existing reference to obtain a reference to a part.
    let r_c_t = &c.t;
    let r_c_t_0 = &r_c_t.0;

    let array = [c, c, c];
    let r_first_elem = &array[0];
    let r_second_elem = &array[1];

    let x = r_first_elem.a.x + r_second_elem.a.x;

    // We can use pattern matching/destructing to obtain a reference to a part.
    let C { a: A { x }, t: (_, y) } = &c; // `x` and `y are references to `u64`.

    let x = *x * *y;
}


/// # Passing and returning references from functions
/// References can be passed and return from functions.
/// It is valid to return a reference to a local value.
/// The lifetime of the referenced value will automatically be extended by the compiler.
/// References returned from functions are l-values.

// Ideally, we want to have escape analysis so that in the case of the function below, we can
// generate a warning for the first argument similar to this one:
//   Copying immutable structs is expensive and in this case not necessary. Consider using `a: &A` instead. 

// The first two parameters are passed by-value. The remaining parameters are passed
// by-reference.
fn fn_takes_references(a: A, mut m_a: A, r_a: &A, r_m_a: &mut A, mut m_r_m_a: &mut A) {
    let x = a.x + m_a.x + r_a.x + m_r_a.x + m_m_r_a.x;

    a.x = 1; // ERROR: `a` is not mutable.
    m_a.x = 1; // OK. The change does not affect the original (passed) value.
    
    r_a.x = 1; // ERROR: `r_a` is a reference to a non mutable `A`.
    r_m_a.x = 1; // OK. Changes the original (passed) value.
    m_r_m_a.x = 1; // OK. Changes the original (passed) value.

    let new_a = A { x: 0 };
    let new_m_a = A { x: 0 };

    a = new_a; // ERROR. `a` is not mutable.

    m_a = new_a; // OK. Replaces `a` but the change does not affect the original.

    r_a = &new_a; // ERROR. `r_a` is not mutable.

    r_m_a = &new_a; // ERROR. `r_m_a` is not mutable.

    // Reassigning `m_r_m_a` does not create a copy of the RHS.
    // Sunce `m_r_m_a` is a reference, the semantics of the reassignment
    // is setting `m_r_m_a` to refer to a different value,
    // without creating a copy of that value.
    m_r_m_a = &mut new_a; // ERROR: `new_a` is not mutable.
    m_r_m_a = &mut new_m_a; // OK. Redirecting the mutable reference to a new mutable value.
    m_r_m_a = &new_m_a; // ERROR: If redirected, `m_r_m_a` must be still a reference to a mutable value.
}

fn fn_returns_ref() -> &A { // Reference to immutable A.
    &A { x: 0 } // Returning references to local values is allowed.
}

fn fn_returns_ref_to_mut() -> &mut A { // Reference to mutable A.
    let mut m_a: A { x: 0 };
    let i_a: A { x: 0 };

    if true {
        &mut m_a // Returning references to local values is allowed.
    }
    else if true {
        &mut i_a // ERROR: `i_a` is not mutable.
    }
    else {
        &m_a // ERROR: We must return `&mut`.
    }
}

fn passing_references_to_functions() {
    let a = A { x: 0 };
    let mut m_a = A { x: 0 };

    fn_takes_references(a, a, &a, &mut m_a, &mut m_a); // OK.
    fn_takes_references(m_a, m_a, &m_a, &mut m_a, &mut m_a); // OK.
    fn_takes_references(a, a, &a, &mut a /* ERROR */, &mut a /* ERROR */); // ERROR.

    let r_a = &a;
    let r_m_a = &mut m_a;
    let mut m_r_a = &a;
    let mut m_r_m_a = &mut m_a;

    // `&mut T` coerce to `&T`.
    fn_takes_references(a, a, r_m_a /* Coercion. */, r_m_a, r_m_a); // OK.
}

fn returning_references_from_functions() {
    let r_a = fn_returns_ref(); // OK.
    let mut m_r_a = fn_returns_ref(); // OK.

    r_a.x = 1; // ERROR.
    m_r_a.x = 1; // ERROR.
    m_r_a = &A { x: 0 }; // OK.

    let r_m_a = fn_returns_ref_to_mut(); // OK.
    let mut m_r_m_a = fn_returns_ref_to_mut(); // OK.

    r_m_a.x = 1; // OK.
    m_r_m_a.x = 1; // OK.
    m_r_m_a = &mut A { x: 0 }; // OK.
    
    // Returned references are l-values and can be used in assignments.
    fn_returns_ref_to_mut().x = 1;
}


/// # References and iterators
/// Once we implement iterators and the `for` loop we can have semantic equivalents to
/// Rust `iter()`, `iter_mut()`, and `into_iter()`. By semantic equivalents we mean
/// - having references in Sway where borrowed value would be in Rust
/// - having values where consuming the collection would be done in Rust.
fn references_and_iterators() {
    let i_a = [1, 2, 3];

    // By default, iteration returns values, means copies of elements.
    let mut sum = 0;
    for x in i_a { // x: u64.
        sum = sum + x;
    }

    let i_a_s = [A { x: 1 }, A { x: 2 }];

    let mut sum = 0;
    for s in i_a_s { // s: A.
        sum = sum + s.x;
    }

    // Same as above, copies are returned.
    for x in i_a.into_iter() {
        // x: u64.
    }
    
    // References to elements are returned.
    for x in i_a.iter() {
        // x: &u64.
    }

    for x in i_a.iter_mut() { // ERROR: `i_a` is not mutable.
    }

    let mut m_a = [1, 2, 3];

    // References to mutable elements are returned.
    for x in m_a.iter_mut() {
        // x: &mut u64.
        *x = 0;
    }

    // Using `mut` when declaring `let` variable is not allowed.
    for mut x in i_a { }  // ERROR.
    for mut x in i_a.into_iter() { }  // ERROR.
    for mut x in i_a.iter() { }  // ERROR.
    for mut x in m_a.iter() { }  // ERROR.
}


/// # References and generic types
struct GenStruct<&T> {} // ERROR: Not allowed.

struct GenStruct<T> {
    x: &T, // OK.
}


/// # References and constants and literals
/// It is possible to take a reference to a constant or a literal.
/// References themselves can be constants only if they reference other constants or literals.
fn references_and_constants_and_literals() {
    const X = 0u64;
    let r_x = &X; // OK: `r_x: &u64`.
    let r_m_x = &mut X; // ERROR: `X` is a constant.
    let mut m_r_x = &X; // OK: `m_r_x: &u64`.

    let r_x = &0u64; // OK: `r_x: &u64`.
    let r_m_x = &mut 0u64; // ERROR: `0u64` is a literal.
    let mut m_r_x = &0u64; // OK: `m_r_x: &u64`.

    // Immutable references to constants and literals are considered in the const evaluation.
    let x = *r_x; // Const evaluation detects `x` to be a constant.
    let x = *m_r_x; // `x` is not a constant.

    const R = &X; // OK: `R: &u64`.
    const R = &1; // OK: `R: &u64`.

    let a = 0u64;

    const R_A = &a; // ERROR: Const reference cannot reference a variable, even if it is immutable.
}


/// # References and type aliases
/// We can have references as type aliases.
type RefToU64 = &u64;
type RefToTupleOfRefs = &(&u64, &u64);

fn references_and_type_aliases() {
    let r: RefToU64 = &0u64;
    let t: RefToTupleOfRefs = &(r, r);

    let _ = passing_and_returning_ref_type_aliases(t);
}

fn passing_and_returning_ref_type_aliases(x: RefToTupleOfRefs) -> RefToU64 {
    x.0
}


/// # `self` keyword
/// `self` is always a reference, to a mutable or immutable self, and must be marked as such.
/// That means, in case of built-in types, to access the value, the dereferencing (*) will
/// must be used.
/// `Self` behaves like a regular type and complies to all the rules listed in the
///  chapter "Passing and returning references from functions".
struct S {
    x: u64,
}

impl S {
    fn immutable_access(&self) { }
    fn immutable_access_error(self) { } // ERROR: `&` is mandatory.
    fn mutable_access(&mut self) { }
    fn mutable_access_error(mut self) { } // ERROR: `&` is mandatory.
    fn self_is_immutable_ref_01(mut &self) {} // ERROR: `self` is always an immutable reference.
    fn self_is_immutable_ref_02(mut &mut self) {} // ERROR: `self` is always an immutable reference.
}

impl Add for u64 {
    fn add(&self, other: Self) -> Self { // `other` is passed by-value.
        __add(*self, other) // `self` must be dereferenced to get the value.
    }
}

impl MyInc for u64 {
    fn inc_me_for_one(&mut self) {
        *self = *self + 1;
    }

    fn inc_me_for_other(&mut self, other: &Self) {
        *self = *self + *other;
    }
}


/// # References and storage
/// References cannot be stored in storage.
/// It is not allowed to take a reference to a storage element.
const X = 0u64;

storage {
    x: &X, // ERROR: References cannot be stored in storage.
    y: 0u64,
    z: 0u64,
    s: S { x: 0 }
    a: &A { x: 0 } // ERROR: References cannot be stored in storage.
}

fn references_and_storage {
    let r_y = &storage.y; // ERROR: It is not allowed to take a reference to a storage element.
    let r_s_x = &storage.s.x; // ERROR: It is not allowed to take a reference to a storage element.

    let r = &storage.s.x.read(); // OK: Taking the reference to the copy returned by `read()`.
}


/// # References and ABIs and `main()` functions
/// References cannot be used on the boundaries.
abi References {
    fn accept_reference_error(x: &u64); // ERROR.
    fn return_reference_error() -> &u64; // ERROR.
}

fn main(x: &u64) {} // ERROR.
fn main() -> &u64 {} // ERROR.


/// # Equality of references
/// References will allow us to redefine the `core::ops::Eq` trait to avoid creating copies.
/// Currently, the `core::ops::Eq`'s `eq` method is defined as:
///
///   fn eq(self, other: Self) -> bool;
///
/// Both `self` and `other` are passed by-value which is problematic from the performance point
/// of view. E.g., in examples of comparing arrays of structs, arrays are always copied, and then
/// each individual struct, before getting the copies compared.
///
/// The new definition fo `eq` will be:
///
///   fn eq(&self, other: &Self) -> bool;
///
/// Calling the operator `==` on `x` and `y` will be semantically translated to `(&x).eq(&y)`.
/// `core::ops` will provide a standard implementation for `impl<T> Eq for &T where T: Eq`. 
///
/// From the programmers perspective, operator `==` will compare the referenced content,
/// if the referenced type implements `core::ops::Eq`.
/// To compare references as pointers (checking if they point to the same memory location), the 
/// `__eq` intrinsic has to be used.
fn equality_of_references() {
    let r_a = &2;
    let r_b = &(1 + 1);

    assert(r_a == r_b);       // Comparing referenced values.
    assert(!__eq(r_a, r_b));  // Comparing memory locations.

    let r_s_a = S { x: 0 };
    let r_s_b = S { x: 0 };

    assert(r_s_a == r_s_b); // ERROR: `S` does not implement `core::ops::Eq`.

    // It is not possible to compare references and values without referencing or dereferencing.
    assert(r_a == 2); // ERROR.
    assert(*r_a == 2); // OK.
    assert(r_a == &2); // OK.
    assert(&&&&42 == &&&&42); // OK.
}


/// # References and pointers
/// When used with references, `__addr_of` returns the address the reference references to.
/// To obtain the address of the reference itself, take the `__addr_of` of its reference.
fn references_and_pointers() {
    let s = S { x: 0 };

    let p_s = __addr_of(s);
    let r_s = &s;

    let p_r_s = __addr_of(r_s);

    assert(__eq(p_s, p_r_s));

    let r_r_s = &r_s;
    let p_r_r_s = __addr_of(r_r_s); // Returns the memory location at which `r_s` is stored.
}


/// # References in ASM blocks
/// Internally, same as pointers, references are just `u64` values that are interpreted
/// as a memory addresses.
///
/// References can be passed as arguments to ASM blocks.
/// The input register will in this case contain the address to the referenced value.
///
/// References can be returned from ASM blocks.
/// In this case, the content of the returned register is interpreted as an address
/// and casted to a reference.

// E.g., ASM block getting references as input.
pub fn replace<T>(dest: &mut T, src: &T) {
    if __addr_of(dest) == __addr_of(src) {
        return;
    }

    let count = if __is_reference_type::<T>() {
        __size_of_val(src)
    } else {
        __size_of::<T>()
    };

    // `dest` and `src` references in the input are addresses to the
    // referenced values.
    asm(dest: dest, src: src, count: count) {
        mcp dst src count;
    };
}

pub fn alloc_and_return_reference<T>() -> &T {
    asm(size: __size_of::<T>(), ref_t) {
        aloc size;
        move ref_t hp;
        ref_t: &T // Return reference to immutable T.
    }
}

pub fn alloc_and_return_reference_to_mutable<T>() -> &mut T {
    asm(size: __size_of::<T>(), ref_t) {
        aloc size;
        move ref_t hp;
        ref_t: &mut T // Return reference to mutable T.
    }
}


/// # References and impls
/// Since references are types, it is possible to write `impl`s for them,
/// including implementing traits.
/// `&T` and `&mut T` are different types, but they coerce.
/// Methods declared on `&T` are available on values of type `&mut T`.
/// As with other impls on types, we can also declare associated functions.
/// As with other impls on types that are not `Ty::Path` types, the only way
/// to call associated functions is via type alias.
impl<T> &T { // A reference to an immutable T.
    pub fn deref(&self) -> T {
        **self // `self` is a reference to a reference. That's why double dereferencing to get the value.
    }

    pub fn redirect_me(&mut self, other: &T) {
        *self = other;
    }

    pub fn change_the_referenced(&self, new_value: T) {
        // `self` is a reference to a reference. That's why double dereferencing to get the value.
        **self = new_value; // ERROR: `self` is a reference to an immutable T.
    }

    // It is also possible to declare associated functions.
    pub fn associated_function(_t: T) { }
}

impl<T> &mut T { // A reference to a mutable T.
    pub fn change_the_referenced(&self, new_value: T) {
        **self = new_value; // `self` is a reference to a reference. That's why double dereferencing to get the value.
    }
}

impl &u64 {
    pub fn change_me_to_123(&mut self) {
        *self = 123;
    }
}

impl MyTrait for &u64 {
    fn my_method(&self) {
        // ...
    }
}

type RefToU64 = &u64;

fn references_and_impls() {
    let a = 0u64;

    assert((&a).deref() == a);

    let r_a = &a;
    r_a.redirect_me(&0); // ERROR: `r_a` is not mutable.

    let mut m_r_a = &a;
    mut_r_a.redirect_me(&0); // OK: `m_r_a` is mutable.

    // Associated function can be called via type alias.
    RefToU64::associated_function(0u64);

    // General remark aside of references:
    // We can think of extend the syntax to allow calling associated functions declared on types
    // that are not `Ty:Path` types.
    // E.g, in the above example something like:
    //   (&u64)::associated_function(0u64); // Parentheses would be necessary to disambiguate declaration of a reference to the function call result.
    // In case of other non-path types, an example could be an array:
    //   [u64;5]::associated_function(0u64);

    let mut b = 0u64;
    let r_m_b = &mut b;

    assert(r_m_b.deref() == b); // OK. Coersion of `&mut u64` to `&u64`.

    r_m_b.change_the_referenced(123u64);
    assert(b == 123);
}


/// # References in contract call parameters
/// References can occure in contract call parameters
/// (`gas`, `asset_id`, `coins`) but must be dereferenced
/// when assigned to parameters.
fn references_in_contract_call_parameters() {
    let contract = abi(MyConstract, CONTRACT_ID);

    let r_n = &5000;
    let r_asset_id = &ASSET_ID;

    contract.some_function {
        gas: r_n, // ERROR.
        asset_id: r_asset_id, // ERROR.
        coins: r_n // ERROR.
    }();

    contract.some_function {
        gas: *r_n, // OK.
        asset_id: *r_asset_id, // OK.
        coins: *r_n // OK.
    }();
}


/// # Future considerations
/// These are some language and library features related to references
/// that might be useful in Sway context. Judging their usefulness can
/// be postponed to after references are implemented, and is thus out
/// of scope of this RFC.
///
/// ## `Deref` and `DerefMut` traits
/// Similar to Rust, Sway could provide `Deref` and `DerefMut` traits
/// together with the deref coercion.