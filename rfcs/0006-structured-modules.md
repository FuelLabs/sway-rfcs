- Feature Name: standard_module_structure
- Start Date: 2023-02-14
- RFC PR: [FuelLabs/sway-rfcs#24](https://github.com/FuelLabs/sway-rfcs/pull/24)
- Sway Issue: [FueLabs/sway#4191](https://github.com/FuelLabs/sway/issues/4191)

# Summary

[summary]: #summary

This RFC proposes a change to the way defining modules works in Sway.

Instead of requiring programmers to specify a path to their module definitions
(as in: `dep dir1/dir2/dep_name;`) and a possibly different library name (as in
`library library_name;`), this proposes to have the programmers specify a
single name for a module through the Rust-like syntax of `mod module_name;` and
have the path to the file containing the associated source code and the library
name used for imports be implicitly defined.

# Motivation

[motivation]: #motivation

The current `dep` based import system is confusing and possibly error prone in
that it allows the definition of surprising and unpredictable module structures
that can be completely detached in name from how those modules are imported.

This permissive scheme also allows namespace collisions wherein two separate
packages or modules can be imported despite having the same name.

The proposed change should formalize a predictable module structure, reduce the
number of editions required when refactoring a module and eliminate the
possibility of namespace collisions between modules of the same package.


# Guide-level explanation

[guide-level-explanation]: #guide-level-explanation

`mod` declarations replace the now deprecated `dep` declarations. `mod`
declarations include a single ident specifying the name of the submodule. Note
that this is different to `dep` declarations which would supply a `/`-separated
file system path to the submodule. Since the name of the submodule is specified
in the declaration, submodules no longer need to supply their name via a
`library name;` header at the start of the file and can instead use the plain `library;`

The name of a submodule is used to find the source file for that submodule. For
a submodule named `bar` of a module `foo`, either the file `foo/bar.sw` or
`bar.sw` must exist. These paths are relative to the file defining the `foo`
module containing the `mod bar;` declaration. It is an error for both or none
of these paths to exist.

Module paths behave the same as they previously did except that they use module
names instead of library names.

## Example

These example sources show the rules in action.

* `src/lib.sw`
```sway
library;

mod foo;
mod bar;

use foo::fun1;
use bar::fun2;
use bar::bar::fun4;

pub fn function() -> u32 {
   fun1() + fun2() + fun4()
}
```

* `src/foo.sw`
```sway
library;

pub fn fun1() -> u32 { 1 }
```

* `src/bar.sw`
```sway
library;

mod foo;
mod bar;

use foo::fun3;
use bar::fun4;

pub fn fun2() -> u32 {
   fun3() + fun4()
}
```

* `src/bar/foo.sw`
```sway
library;

pub fn fun3() -> u32 {
   3
}
```

* `src/bar/bar.sw`
```sway
library;

pub fn fun4() -> u32 {
   4
}
```



# Reference-level explanation

[reference-level-explanation]: #reference-level-explanation

The implementation requirements of this change are deliberately small and
straightforward: introduce `mod` statements to replace `dep` statements, remove
the need for an ident argument to `library`, deduce the library name from
the source folder structure, add checks to ensure the structure isn't ambiguous.

The interactions with other features are minimal.
However we might be able to refactor some compiler behavior after establishing
that dependency and library names are no longer different.

# Drawbacks

[drawbacks]: #drawbacks

This is a breaking change and will require changing all sway module imports and
restructuring projects that use the existing permissive scheme in creative
ways, but this is both rare (it seems that most follow Rust like conventions
already in practice) and will result in better code structure and less
boilerplate.

# Rationale and alternatives

[rationale-and-alternatives]: #rationale-and-alternatives

We could also follow the existing Rust convention and allow both `submodule.sw`
and `submodule/mod.sw` or only allow the latter instead of the former as this
proposal does. But Rust's allowance of both is an artifact of backwards
compatibility rather than a deliberate design choice. It is likely best to
settle on and enforce a single convention.

If we do not enforce any module structure and hold to the current behavior,
the issues and confusion will remain and it will become harder to change in the
future.

# Prior art

[prior-art]: #prior-art

Rust's module structure is the prior art we are taking cues from, but there is
also a [previous, now abandoned,
RFC](https://github.com/FuelLabs/sway-rfcs/pull/8) that sought similar but more
wide changes to the way paths and module imports work in Sway.

The present RFC tries to make the change as small and painless as possible so
that we may build upon it later.

# Unresolved questions

[unresolved-questions]: #unresolved-questions

The elimination of file type headers such as `library;` or `contract;` when
they aren't needed is not considered here. Neither are wider issues about the
structure and type of package exports. But clarifying the module structure will
definitely give us a more stable base to consider these.

We also do not consider the visibility of modules here and reproduce the
public by default scheme of `dep`.

# Future possibilities

[future-possibilities]: #future-possibilities

We could consider eliminating module type headers like `library;`, `contract;`
and `predicate;` from the source altogether and defining the exports in the
`Forc.toml` or implicitly through usage.

We should also consider making the visibility of modules explicit through a
`pub mod` syntax and make them private by default.

Another extension could be to support `mod foo { /* ... */ }` syntax as Rust
does to specify, possibly nested, submodules inside of the same source file.
