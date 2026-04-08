# Pending Implementation Items

## 1. Dependency management CLI commands
**Files:** `crates/cli/src/handlers/{add,remove,list}.rs`

All three are stub functions that print "not yet implemented". These would form the
dependency management story for Lisette projects (`lis add`, `lis remove`, `lis list`).

## 2. External Go package cache lookup
**File:** `crates/semantics/src/module_graph/mod.rs:167`

When resolving `go:` imports, there's a `@TODO` to check a cache at `~/.lisette` for
non-stdlib Go packages. Currently only embedded stdlib typedefs are supported; third-party
Go interop would need this.

## 3. Test file support (`_test.lis`)
**File:** `crates/diagnostics/src/module_graph.rs:41-44`

Files ending in `_test.lis` are explicitly rejected with an error saying they're "reserved
for future testing support." A built-in test framework is a significant language feature gap.

## 4. Format specifiers in interpolated strings
**File:** `crates/syntax/src/parse/expressions.rs:995-997`

The parser recognizes format specifiers (like `{x:.2f}`) but emits a "Format specifiers
not supported" error. Supporting these would bring parity with Rust's `format!` expressiveness.

## 5. Float and imaginary literals in patterns
**File:** `crates/syntax/src/parse/patterns.rs:67,126`

Pattern matching on float and imaginary number literals is explicitly disallowed with
"not supported in patterns" errors. Float patterns are tricky (equality semantics), but
imaginary literal support would round out the numeric type story.
