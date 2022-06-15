- Start Date: 2022-06-15
- RFC PR: [FuelLabs/sway#1](https://github.com/FuelLabs/sway-rfcs/pull/1)

_This RFC process is inspired by, and mostly copied from, Rust's RFC process. 
See [here](https://github.com/rust-lang/rfcs/blob/master/text/0002-rfc-process.md)
for Rust's version of this.

Rust's RFC process has proven efficiency that we'd like to emulate._

# Summary

The "RFC" (request for comments) process is intended to provide a
consistent and controlled path for new features to enter the language
and standard libraries, so that all stakeholders can be confident about
the direction the language is evolving in.

# Motivation

The freewheeling way that we add new features to Sway has been good for
early development, but for Sway to become a mature platform we need to
develop some more self-discipline when it comes to changing the system.
This is a proposal for a more principled RFC process to make it
a more integral part of the overall development process, and one that is
followed consistently to introduce features to Sway.

# Detailed design

Many changes, including bug fixes and documentation improvements can be
implemented and reviewed via the normal GitHub pull request workflow.

Some changes though are "substantial", and we ask that these be put
through a bit of a design process and produce a consensus among the Sway
community and the [core team].

## When you need to follow this process

You need to follow this process if you intend to make "substantial"
changes to the Sway distribution. What constitutes a "substantial"
change is evolving based on community norms, but may include the following.

   - Any semantic or syntactic change to the language that is not a bugfix.
   - Removing language features, including those that are feature-gated.
   - Changes to the interface between the compiler and libraries,
including lang items and intrinsics.
   - Eventually, when we reach stdlib maturity, we will want to use RFCs for
     stdlib design as well.

Some changes do not require an RFC:

   - Rephrasing, reorganizing, refactoring, or otherwise "changing shape
does not change meaning".
   - Additions that strictly improve objective, numerical quality
criteria (warning removal, speedup, better platform coverage, more
parallelism, trap more errors, etc.)
   - Additions only likely to be _noticed by_ other developers-of-sway,
invisible to users-of-sway.

If you submit a pull request to implement a new feature without going
through the RFC process, it may be closed with a polite request to
submit an RFC first.

## What the process is

In short, to get a major feature added to Sway, one must first get the
RFC merged into the RFC repo as a markdown file. At that point the RFC
is 'active' and may be implemented with the goal of eventual inclusion
into Sway.

* Fork the RFC repo https://github.com/FuelLabs/sway-rfcs (or make a branch if you are core-team).
* Copy `0000-template.md` to `rfcs/0000-my-feature.md` (where
'my-feature' is descriptive. don't assign an RFC number yet).
* Fill in the RFC.
* Submit a pull request. The pull request is the time to get review of
the design from the larger community.
* Build consensus and integrate feedback. RFCs that have broad support
are much more likely to make progress than those that don't receive any
comments.

Eventually, somebody on the [core team] will either accept the RFC by
merging the pull request, at which point the RFC is 'active', or
reject it by closing the pull request.

Whomever merges the RFC should do the following:

* Assign an id, using the PR number of the RFC pull request. (If the RFC
  has multiple pull requests associated with it, choose one PR number,
  preferably the minimal one.)
* Add the file in the `rfcs/` directory.
* Create a corresponding issue on [Sway repo](https://github.com/FuelLabs/sway).
* Fill in the remaining metadata in the RFC header, including links for
  the original pull request(s) and the newly created Sway issue.
* Add an entry in the [Active RFC List] of the root `README.md`.
* Commit everything.

Once an RFC becomes active then authors may implement it and submit the
feature as a pull request to the Sway repo. An 'active' is not a rubber
stamp, and in particular still does not mean the feature will ultimately
be merged; it does mean that in principle all the major stakeholders
have agreed to the feature and are amenable to merging it.

Modifications to active RFC's can be done in followup PR's. An RFC that
makes it through the entire process to implementation is considered
'complete' and is removed from the [Active RFC List]; an RFC that fails
after becoming active is 'inactive' and moves to the 'inactive' folder.

[core team]: https://github.com/orgs/FuelLabs/teams/sway-compiler
