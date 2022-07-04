- Feature Name: specify_path_resolution
- Start Date: (fill me in with today's date, YYYY-MM-DD)
- RFC PR: [FuelLabs/sway-rfcs#0000](https://github.com/FuelLabs/sway-rfcs/pull/001)
- Sway Issue: [FueLabs/sway#0000](https://github.com/FuelLabs/sway/issues/001)

# Summary

[summary]: #summary

This RFC proposes a change to the way paths and modules work in Sway.

Paths are sequences of `::`-delimited idents which are used to refer to a
specific item in a specific module. Paths can either be absolute or relative
depending on whether they start with a `::` token.

Under this proposal the first identifier in an absolute path is always the name
of a package. This package either could be a dependency declared in the
package's Forc.toml file, or the name of the current package. In contrast,
relative paths are always relative to the current module.

As part of the transition to this new system, this RFC also proposes to replace
`dep` declarations with `mod` declarations and to deprecate the use of program
kind headers at the start of Sway source files.

# Motivation

[motivation]: #motivation

There are currently several issues with the way modules and packages are named
and referred to in Sway.

* The name a library module gives itself does not need to match the name given
  in the `dep` declaration which includes it.
* The name the root library module of a library package gives itself does not
  need to match the name of the package.
* Due to the above two issues, its possible to have namespace collisions where
  two separate packages or modules can be imported despite having the same
  name.
* It's possible for modules under the root module of package to have name
  conflicts with dependency packages.

With the new rules proposed in this RFC, all modules that are in scope in (both
those in the current package and those in dependency packages) have a distinct
and unique absolute path. What's more, relative paths are always unambiguous
and refer to a specific item in a specific module.

# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

## Program kinds in Forc.toml

The `[project]` section of a package's Forc.toml is required to have a `kind`
field specifying the kind of the program. This value of this field must be one
of `"library"`, `"contract"`, `"script"` or `"predicate"`. This replaces the
now-deprecated program kind header at the start of a Sway source file.

Since a package's Forc.toml also specifies the name of the package this change
de-duplicates the library name which was previously also given by the `library
name;` program kind header.

## `mod` declarations

`mod` declarations replace the now-deprecated `dep` declarations. `mod`
declarations include a single ident specifying the name of the submodule. Note
that this is different to `dep` declarations which would supply a `/`-separated
file system path to the submodule. Since the name of the submodule is specified
in the declaration, submodules no longer need to supply their name via a
`library name;` program kind header at the start of the file.

The name of a submodule is used to find the source file for that submodule. For
a submodule named `foo`, either the file `foo/mod.sw` or `foo.sw` must exist.
These paths are relative to the file containing the `mod` declaration. It is an
error for both of these paths to exist.

## Path/namespace resolution

Paths can either be absolute or relative depending on whether they start with a `::` token.

### Absolute paths

The first identifier in an absolute path always refers to the name of a
package. For example, in the path `::std::hash::sha256`, `std` is the name of
the package, `hash` is the name of the root-level submodule in the package and
`sha256` is the name of an item in that module (this item may itself be another
module).

The package name may be the name of the current package, as specified in the
package's Forc.toml, otherwise it must be the name of an external dependency.
This external dependency must be specified in the package's Forc.toml unless it
is one of the two implicitly included dependencies `std` or `core`.

There are two important ways that this scheme differs from the current
path-resolution rules. Firstly, external libraries are not automatically in the
(relative) scope. For instance, to refer to the `sha256` function mentioned
above via the relative path `std::hash::sha256` would require that `std` is
explicitly brought into scope via a `use ::std` declaration. Secondly,
root-level submodules of the current package are only at the root level of the
current package, not at the root of the entire namespace heirarchy. For
instance, if a package `foo` contains a root-level submodule `bar`, then, even
within `foo`, the absolute path to this module is `::foo::bar`, not simply
`::bar`. 

### Relative paths

Relative paths are always relative to the current module. eg. if the path
`foo::bar` is used anywhere in a module then `foo` must be
declared or imported in that module.

## `use` declarations

Paths in `use` declarations behave exactly the same as paths used in any other
syntax position. It's an error for a name imported into a module to conflict
with a name declared locally in that module. The exception to this rule is
glob-imported names, which may be shadowed by an explicly-named declaration or
import. If a name is imported multiple times via multiple glob imports, and
that name is not shadowed by an explicit declaration or import, then it is an
error to refer to that name.

## Example

This extended example shows the proposed rules in action.

* my_cool_dependency/Forc.toml:
```
[project]
name = "my_cool_dependency"
kind = "library"
```

* my_cool_dependency/src/lib.sw:
```
pub mod dependency_file_submodule;
pub mod dependency_dir_submodule;

pub fn my_cool_function() -> u32 {
    1
}
```

* my_cool_dependency/src/dependency_file_submodule.sw:
```
pub fn returns_two() -> u32 {
    2
}
```

* my_cool_dependency/src/dependency_dir_submodule/mod.sw:
```
pub fn returns_three() -> u32 {
    // ERROR: dependency_file_submodule is not the name of a package
    // You may have meant:
    //     ::my_cool_dependency::dependency_file_submodule::returns_two
    /*
    1 + ::dependency_file_submodule::returns_two()
    */

    3
}
```

* my_other_cool_dependency/Forc.toml:
```
[project]
name = "my_other_cool_dependency"
kind = "library"
```

* my_other_cool_dependency/src/lib.sw:
```
pub fn my_cool_function() -> u32 {
    4
}
```

* my_cool_package/Forc.toml:
```
[project]
name = "my_cool_package"
kind = "library"

[dependencies]
my_cool_dependency = ...
```

* my_cool_package/src/lib.sw:
```
use ::my_cool_dependency::*;
use ::my_other_cool_dependency::*;

mod submodule;

pub fn my_cool_function() -> u32 {
    5
}

fn my_other_cool_function() -> u32 {
    // refers to the locally-defined my_cool_function
    let x = my_cool_function();

    // dependecy_file_submodule has been brought into scope via a glob import
    let y = dependency_file_submodule::returns_two();

    // returns 7
    x + y
}

fn yet_another_function() -> u32 {
    // submodule is defined in this module as so can be referred to with a
    // relative path
    submodule::returns_nine()
}
```

* my_cool_package/src/submodule.sw:
```
use ::my_cool_dependency::*;
use ::my_other_cool_dependency::*;

fn returns_nine() -> u32 {
    // ERROR: my_cool_function is ambiguous.
    // The following two items are imported but must be referred to explicitly:
    //     ::my_cool_dependency::my_cool_function
    //     ::my_other_cool_dependency::my_cool_function
    /*
    let x = my_cool_function();
    */

    // calls my_cool_function from this package
    let x = ::my_cool_package::my_cool_function();

    // calls my_cool_function from my_other_cool_dependency
    let y = ::my_other_cool_dependency::my_cool_function();

    x + y
}
```

# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

Since this RFC proposed several breaking changes we would need to upgrade the compiler in phases. From a high-level view, seemingly a good upgrade path would be:
1. Replace `dep` statements with `mod` statements, and check that the module name matches the name that `library`-kinded source file assigns itself
2. Require the addition `kind` field in forc manifest files, and likewise require that this matches the kind of the root source file.
3. Remove program-kind headers from the language.
4. Make the contents of a package available to itself under the `::package_name` path.
5. Disallow referring to root-level items of a package via the path `::item`, requiring `::package_name::item` instead.
6. Disallow referring to external libraries using non-global paths.

# Drawbacks

[drawbacks]: #drawbacks

None known.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

Alternatively, we could make the behaviour for path resolution identical to
Rust's. However Rust's behaviour has some warts. In fact, one of the main
motivations for the introduction of Rust's editions system was to make the
import rules less baroque. Some of these problems still exist in the 2018
edition however.

For instance, if `foo` is a locally-declared item then paths starting with
`foo` can refer to either that item or to a dependency named `foo`. It's
possible to unambiguously refer to either using `self::foo` or `::foo`
respectively, but the existance of the ambiguity can make code harder to read
for humans (since it requires more contextual understanding of the code) and
creates extra work for the compiler authors. In the system proposed here,
`self`-prefixed paths are redudant and unnecessary. Additionally, Rust's path
resolution behaves differently in `use` statements compared to elsewhere since
`use` statements are required to be unambiguous rather than resolving one way
or the other depending on context. The inability to refer to the current crate
by name in Rust also creates problems for macros, leading to the need for the
`$crate` meta-variable.

# Prior art

[prior-art]: #prior-art

The most relevant prior art is Rust's import rules, as described above.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

None known.

# Future possibilities

[future-possibilities]: #future-possibilities

One thing that might be nice would be to have a short-hand way of referring to
the current package other than by name. In Rust, users can write `crate::foo`
to refer to `foo` under the root of the current `crate`. Since Sway doesn't
have "crates" a different syntax would be needed. Perhaps `::self` (since
`self` is already a keyword and can't conflict with the name of a dependency)
or `::pkg` (though `pkg` would have to be made a keyword).

