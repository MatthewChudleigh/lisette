# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Lisette is a statically-typed language inspired by Rust that compiles to Go.
The compiler is written in Rust (edition 2024, MSRV 1.94).
The Go runtime/prelude lives in `prelude/`.

## Build & Dev Commands

All commands use `just` (run `just --list` for the full set):

```sh
just build            # release build
just test             # test suite + LSP tests
just test-e2e         # compile Lisette → Go → run
just check            # format-check + test + lint
just lint             # clippy --all-targets -D warnings
just format           # cargo fmt
just run <file>       # compile and execute a .lis file
just test-review      # review snapshot diffs (cargo insta review)
just test-accept      # accept all snapshot changes
```

Single test: `cargo test -p tests --test suite <test_name>`

Stdlib typedefs: `just regenerate-stdlib-typedefs` rebuilds Lisette type defs from Go via `tools/bindgen/`.

## Compiler Pipeline

Source flows through three phases in `crates/cli/src/pipeline.rs`:

1. **Syntax** (`crates/syntax`) — Lex → Parse → Desugar → `AstBuildResult`
2. **Semantics** (`crates/semantics`) — Module graph, HM type inference, linting → `SemanticResult`
3. **Emit** (`crates/emit`) — Go code generation → `Vec<OutputFile>` written to `target/`

`check` stops after phase 2. `build`/`run` go through all three.

## Crate Map

| Crate | Role |
|-------|------|
| `cli` | Binary `lis`, arg parsing, handlers, pipeline |
| `syntax` | Lexer, parser, desugaring, AST types |
| `semantics` | Type checker, inference, scopes, linting, module graph |
| `emit` | Go code generation |
| `diagnostics` | Error/warning rendering via miette |
| `format` | Lisette code pretty-printer |
| `stdlib` | Prelude + Go stdlib typedefs (embedded at build time) |
| `lsp` | Language Server via tower-lsp |

## Common Edit Patterns

**Adding a new AST node** (Expression variant) — touch these in order:
1. `crates/syntax/src/ast.rs` — add variant to `Expression` enum
2. `crates/syntax/src/parse/expressions.rs` — parse it
3. `crates/syntax/src/desugar.rs` + `ast_folder.rs` — traverse/transform
4. `crates/semantics/src/checker/infer/expressions/mod.rs` — add match arm in `infer_expression_inner()`
5. `crates/semantics/src/checker/infer/expressions/<category>.rs` — type inference logic
6. `crates/emit/src/go/statements/assignments.rs` — add match arm in `emit_statement()`
7. `crates/emit/src/go/<category>/` — Go code generation
8. `crates/format/src/formatter.rs` — add match arm in `doc()`
9. Add snapshot tests in `tests/spec/` using the appropriate macro (e.g., `assert_emit_snapshot!`, `assert_parse_snapshot!`). Snapshot files auto-generate in `tests/spec/<category>/snapshots/<test_fn_name>.snap`.

**LSP updates** — needed when the new node binds variables or is navigable:
- `crates/lsp/src/hover.rs` — add match arm in `extract_doc_from_expression()` if it carries docs or sub-items
- `crates/lsp/src/completion.rs` — add match arm in `resolve_variable_type()` if it introduces bindings
- `crates/lsp/src/definition.rs` — add match arm in `resolve_definition_span()` for go-to-definition

**Adding a new diagnostic**: Define a factory function in `crates/diagnostics/src/lint.rs` (or `infer.rs` for type errors), call it from `crates/semantics/src/lint/` and push to the `DiagnosticSink`.

**Adding a new emit pattern**: The entry point is `emit_statement()` in `crates/emit/src/go/statements/assignments.rs`. Subdirectories under `crates/emit/src/go/` are organized by category: `expressions/`, `statements/`, `definitions/`, `calls/`, `patterns/`, `types/`, `names/`.

## Testing

Tests live in `tests/` (a workspace member). Test functions are snake_case describing what's tested (e.g., `binary_addition`, `struct_pattern_binding`).

Snapshot tests use macros from `tests/_harness/macros.rs`: `assert_lex_snapshot!`, `assert_parse_snapshot!`, `assert_desugar_snapshot!`, `assert_emit_snapshot!`, and error variants. Snapshot files auto-land in `tests/spec/<category>/snapshots/<test_fn_name>.snap`. After changing compiler output, `just test-review` to inspect diffs, `just test-accept` to update.

Infer tests are split into submodules under `tests/spec/infer/` (basics, types, expressions, etc.) due to volume.

## Prelude vs Inline Emit

Code goes in `prelude/` (Go) when it needs multiple statements, panic recovery, or is a type definition with methods (Option, Result, Partial, Range types, channel helpers). Code is emitted inline when it maps directly to a Go builtin or is a one-liner — these are defined as `InlineRule` templates in `crates/emit/src/go/calls/native.rs` (e.g., `len({r})`, `strings.Contains({r}, {0})`).

## Error Handling

No `Result`/`anyhow` error propagation. Diagnostics are accumulated in a shared `DiagnosticSink` (`RefCell<Vec<LisetteDiagnostic>>`), then extracted at the end of analysis. Build diagnostics with the fluent API:

```rust
LisetteDiagnostic::warn("Unused variable")
    .with_lint_code("unused_variable")
    .with_span_label(span, "never used")
    .with_help("prefix with _ to suppress")
```

Severities: `.error()` / `.warn()`. Codes: `.with_lint_code()` / `.with_infer_code()` / `.with_parse_code()` / `.with_resolve_code()`.

## Type Inference Internals

- Type variables created via `Checker::new_type_var()` in `crates/semantics/src/checker/mod.rs`
- Main dispatch: `infer_expression_inner()` in `checker/infer/expressions/mod.rs` (40+ match arms)
- Unification: `try_unify()` in `checker/infer/unify.rs` — links type variables via `TypeVariableState::Link`, with occurs check and undo log for backtracking failed match arms
- Type variable states: `Unbound { id, hint }` or `Link(Type)` (in `crates/syntax/src/types.rs`)

## Emitted Go Conventions

Preserve these patterns when modifying the emit crate:

- **Prelude imports**: always `lisette "github.com/ivov/lisette/prelude"`, qualified as `lisette.Option[T]`, `lisette.Result[T,E]`
- **Enum layout**: tag field `Tag`, tag type `{Enum}Tag`, variant constants `{Enum}{Variant}`, constructors `Make{Enum}{Variant}()`
- **Reserved word escaping**: Go keywords get trailing underscore (`range_`, `len_`, `make_`) — see `emit/src/go/names/go_name.rs`
- **Temp variables**: numbered `tmp_1`, `copy_1`, `subject_1`, `ref_1` — auto-incremented for collisions
- **Struct spread**: always copies to temp before mutating fields
- **Generic types**: Go square brackets with `any` constraint: `Box[T any]`
- **Static methods**: emitted as `{Type}_{Method}` functions

## Import & Code Conventions

- **Explicit imports only** — no wildcard `use *` anywhere
- **FxHash aliases**: `use rustc_hash::{FxHashMap as HashMap, FxHashSet as HashSet}` — use these, not `std::collections`
- **EcoString** (`ecow::EcoString`): copy-on-write strings used throughout, not `String`
- **Size assertions**: AST node sizes are statically asserted in `syntax/lib.rs` — update if changing `Expression` (408 bytes), `Pattern` (152 bytes), or `Type` (80 bytes)
- **Conventional commits**: enforced by lefthook (`feat:`, `fix:`, `chore:`, etc.), max 72 chars

## Things to Avoid

- Don't use `anyhow`, `thiserror`, or `Result` for compiler diagnostics — use `DiagnosticSink`
- Don't use `std::collections::HashMap/HashSet` — use the `FxHash` aliases
- Don't use `String` for AST-level strings — use `EcoString`
- Don't add wildcard imports
- Don't forget to update the size assertion in `syntax/lib.rs` when changing AST node layout

## Large Files

These files exceed 1000 lines — read targeted ranges rather than the whole file:

| Lines | File | Content |
|-------|------|---------|
| 2147 | `diagnostics/src/infer.rs` | Type error diagnostic factories |
| 1871 | `format/src/formatter.rs` | Formatter with match over all AST nodes |
| 1717 | `syntax/src/ast.rs` | AST type definitions |
| 1396 | `syntax/src/parse/expressions.rs` | Expression parser |
| 1322 | `lsp/src/lib.rs` | LSP server setup and handlers |
| 1296 | `syntax/src/lex/mod.rs` | Lexer |
| 1095 | `emit/src/go/patterns/decision_tree.rs` | Pattern match compilation |
| 1015 | `semantics/src/checker/infer/expressions/functions.rs` | Function call inference |
| 923 | `semantics/src/checker/infer/expressions/dot_access.rs` | Dot access inference |
| 901 | `emit/src/go/definitions/toplevel.rs` | Top-level Go definition emission |
