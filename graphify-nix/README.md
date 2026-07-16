# Graphify Nix integration

This integration adds deterministic Tree-sitter extraction and a cross-file
semantic resolver for Nix expressions, NixOS modules, Home Manager modules, and
flakes. It is packaged by `modules/home/graphify.nix` and copied into graphify at
build time; `patches/graphify-nix-support.patch` only wires the language into
graphify's detector, dispatcher, resolver registry, and cache namespace.

## Extracted semantics

- Nix file, binding, and module-parameter nodes
- local module/import dependencies, including directory `default.nix`
- precise same-file references and imported-export references
- canonical NixOS/Home Manager option nodes with declaration, assignment, and
  option-parent edges
- `specialArgs` and `extraSpecialArgs` propagation scoped through the module
  import graph
- canonical flake-input nodes, `follows`, module use, package use, and general use
- package references from `pkgs.*`, `pkgsUnstable.*`, and `with pkgs; [...]`
- service concepts derived from `services.<name>.*`
- `lib.*`/`builtins.*` function calls and conditional configuration
- theme definitions, selected themes, imported theme exports, and wallpaper assets
- conventional architecture layers for NixOS core/desktop/profile/hardware,
  Home Manager, hosts, libraries, themes, and flake composition
- a weighted semantic backbone joining those layers under the Nix configuration
  architecture, while retaining every low-level occurrence in the raw graph
- canonical option labels and source-qualified duplicate occurrences for
  unambiguous `query`, `path`, and `explain` resolution
- Nix package builders classified as functions instead of package dependencies
- semantic-first, bounded traversal for high-fanout Nix nodes

All syntax-proven relationships are `EXTRACTED` with confidence `1.0`.
Convention-based architecture, option hierarchy, and argument propagation are
marked `INFERRED` with explicit confidence scores.

## Verification

Run the integration test with the Python interpreter from the built graphify
environment:

```sh
python -m unittest graphify-nix/test_integration.py
```

After changing the extractor, increment the `+nix-vN` namespace in the graphify
cache patch so stale per-file AST entries cannot hide new facts.
