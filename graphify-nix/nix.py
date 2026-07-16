"""High-fidelity Nix, NixOS, Home Manager, and flake graph extraction.

The per-file pass is deliberately deterministic: tree-sitter supplies syntax
boundaries and this module emits both ordinary graph nodes/edges and compact
``nix_facts``.  ``resolve_nix_semantics`` consumes those facts after graphify has
canonicalised IDs, which is the earliest safe point for cross-file semantics.
"""

from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from graphify.extractors.base import _file_stem, _make_id


_BUILTINS = frozenset(
    {
        "abort",
        "baseNameOf",
        "builtins",
        "derivation",
        "dirOf",
        "false",
        "fetchTarball",
        "import",
        "isNull",
        "map",
        "null",
        "placeholder",
        "removeAttrs",
        "throw",
        "toString",
        "true",
    }
)
_CONDITION_CALLS = frozenset(
    {
        "lib.mkIf",
        "lib.mkMerge",
        "lib.optional",
        "lib.optionals",
        "lib.optionalAttrs",
        "lib.mkOverride",
        "lib.mkDefault",
        "lib.mkForce",
    }
)
_OPTION_CONSTRUCTORS = frozenset(
    {"lib.mkOption", "lib.mkEnableOption", "mkOption", "mkEnableOption"}
)
_CONFIG_ROOTS = frozenset(
    {
        "boot",
        "console",
        "environment",
        "fonts",
        "gtk",
        "hardware",
        "home",
        "i18n",
        "networking",
        "nix",
        "nixpkgs",
        "programs",
        "qt",
        "security",
        "services",
        "stylix",
        "system",
        "systemd",
        "time",
        "users",
        "wayland",
        "xdg",
        "xresources",
        "fileSystems",
        "swapDevices",
        "virtualisation",
        "powerManagement",
        "documentation",
        "sound",
        "zramSwap",
    }
)
_DYNAMIC_SEGMENT = re.compile(r"\$\{[^}]+\}")
_STRING_RE = re.compile(r"""["']([^"']+)["']""")

# Edge weights describe semantic strength, not extraction confidence. Graphify
# uses them for clustering and the patched query traversal uses them to present
# the conceptual backbone before occurrence-level syntax.
_RELATION_WEIGHTS = {
    "contains": 0.5,
    "option_parent": 0.55,
    "accepts_argument": 0.5,
    "references": 0.7,
    "sets_option": 0.75,
    "uses_package": 0.8,
    "calls_nix_function": 0.8,
    "declares_option": 1.0,
    "imports": 1.25,
    "belongs_to_layer": 1.25,
    "part_of_architecture": 1.4,
    "passes_argument": 1.3,
    "references_imported_export": 1.3,
    "uses_flake_input": 1.3,
    "uses_input_package": 1.4,
    "uses_input_module": 1.5,
    "defines_flake_input": 1.4,
    "follows_input": 1.2,
    "configures_service": 1.5,
    "participates_in": 1.35,
    "defines_theme": 1.5,
    "selects_theme": 1.8,
    "uses_asset": 1.0,
    "uses_wallpaper": 1.5,
    "conditioned_by": 1.2,
    "documents": 1.35,
}
_PACKAGE_BUILDERS = frozenset(
    {
        "pkgs.callPackage",
        "pkgs.fetchFromGitHub",
        "pkgs.fetchPypi",
        "pkgs.mkShell",
        "pkgs.runCommand",
        "pkgs.stdenv.mkDerivation",
        "pkgs.writeShellApplication",
        "pkgs.writeShellScript",
        "pkgs.writeShellScriptBin",
        "pkgs.writeText",
        "pkgs.writeTextFile",
    }
)


def _edge_weight(relation: str) -> float:
    return _RELATION_WEIGHTS.get(relation, 1.0)


def _walk(node: Any, *, stop_at_bindings: bool = False) -> Iterable[Any]:
    yield node
    for child in node.children:
        if not child.is_named:
            continue
        if stop_at_bindings and child.type == "binding":
            continue
        yield from _walk(child, stop_at_bindings=stop_at_bindings)


def _line(node: Any) -> int:
    return node.start_point[0] + 1


def _normalise_attrpath(value: str) -> str:
    value = re.sub(r"\s+", "", value.strip())
    return value.strip(".")


def _option_key(value: str) -> str:
    value = _normalise_attrpath(value)
    if value.startswith("options."):
        value = value[len("options.") :]
    if value.startswith("config."):
        value = value[len("config.") :]
    value = _DYNAMIC_SEGMENT.sub("*", value)
    return value


def _resolve_nix_path(owner: Path, raw: str) -> Path | None:
    raw = raw.strip()
    if not raw.startswith(("./", "../", "/")):
        return None
    candidate = (
        (owner.parent / raw).resolve()
        if not raw.startswith("/")
        else Path(raw).resolve()
    )
    if candidate.is_dir():
        candidate = candidate / "default.nix"
    elif not candidate.suffix and candidate.with_suffix(".nix").is_file():
        candidate = candidate.with_suffix(".nix")
    return candidate if candidate.is_file() and candidate.suffix == ".nix" else None


def extract_nix(path: Path) -> dict:
    """Extract structural nodes plus facts for cross-file Nix resolution."""
    try:
        import tree_sitter_nix as tsnix
        from tree_sitter import Language, Parser
    except ImportError:
        return {"nodes": [], "edges": [], "error": "tree_sitter_nix not installed"}

    try:
        source = path.read_bytes()
        tree = Parser(Language(tsnix.language())).parse(source)
    except Exception as exc:
        return {"nodes": [], "edges": [], "error": str(exc)}

    str_path = str(path)
    stem = _file_stem(path)
    file_nid = _make_id(str_path)
    nodes: list[dict] = [
        {
            "id": file_nid,
            "label": path.name,
            "file_type": "code",
            "lang": "nix",
            "type": "module" if path.name != "flake.nix" else "flake",
            "graph_role": "module",
            "semantic_rank": 0.8,
            "source_file": str_path,
            "source_location": None,
        }
    ]
    edges: list[dict] = []
    facts: dict[str, Any] = {
        "source_file": str_path,
        "parameters": [],
        "bindings": [],
        "imports": [],
        "option_declarations": [],
        "option_assignments": [],
        "packages": [],
        "flake_inputs": [],
        "input_uses": [],
        "argument_providers": [],
        "conditions": [],
        "function_calls": [],
        "import_aliases": [],
        "selections": [],
        "assets": [],
        "root_string": None,
    }
    seen_nodes = {file_nid}
    seen_edges: set[tuple[str, str, str]] = set()

    def text(node: Any) -> str:
        return source[node.start_byte : node.end_byte].decode("utf-8", errors="replace")

    def add_node(nid: str, label: str, line: int | None, **extra: Any) -> None:
        if nid in seen_nodes:
            return
        seen_nodes.add(nid)
        node = {
            "id": nid,
            "label": label,
            "file_type": "code",
            "lang": "nix",
            "source_file": str_path,
            "source_location": f"L{line}" if line else None,
        }
        node.update(extra)
        nodes.append(node)

    def add_edge(
        src: str, dst: str, relation: str, line: int, *, context: str | None = None
    ) -> None:
        if src == dst or (src, dst, relation) in seen_edges:
            return
        seen_edges.add((src, dst, relation))
        edge = {
            "source": src,
            "target": dst,
            "relation": relation,
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str_path,
            "source_location": f"L{line}",
            "weight": _edge_weight(relation),
        }
        if context:
            edge["context"] = context
        edges.append(edge)

    def binding_attr(binding: Any) -> str | None:
        attr = next(
            (child for child in binding.children if child.type == "attrpath"), None
        )
        return _normalise_attrpath(text(attr)) if attr is not None else None

    def qualified_attr(binding: Any) -> str | None:
        parts: list[str] = []
        current = binding
        while current is not None:
            if current.type == "binding" and (attr := binding_attr(current)):
                parts.append(attr)
            current = current.parent
        return ".".join(reversed(parts)) if parts else None

    def is_let_binding(binding: Any) -> bool:
        current = binding
        while current is not None:
            if current.type == "binding_set" and current.parent is not None:
                if current.parent.type in {"let_expression", "legacy_let_expression"}:
                    return True
            current = current.parent
        return False

    root_expression = next(
        (child for child in tree.root_node.children if child.is_named), None
    )
    if root_expression is not None and root_expression.type == "string_expression":
        match = _STRING_RE.fullmatch(text(root_expression).strip())
        if match:
            facts["root_string"] = match.group(1)

    # Module function parameters are first-class nodes.  They are later joined
    # to specialArgs/extraSpecialArgs providers by name.
    outer_function = next(
        (node for node in _walk(tree.root_node) if node.type == "function_expression"),
        None,
    )
    parameter_names: set[str] = set()
    if outer_function is not None:
        formals = next(
            (child for child in outer_function.children if child.type == "formals"),
            None,
        )
        if formals is not None:
            for formal in (
                child for child in formals.children if child.type == "formal"
            ):
                ident = next(
                    (node for node in _walk(formal) if node.type == "identifier"), None
                )
                if ident is None:
                    continue
                name = text(ident).strip()
                parameter_names.add(name)
                nid = _make_id(stem, "param", name)
                add_node(
                    nid,
                    f"parameter {name}",
                    _line(ident),
                    type="parameter",
                    parameter_name=name,
                    graph_role="occurrence",
                    semantic_rank=0.3,
                )
                add_edge(file_nid, nid, "accepts_argument", _line(ident))
                facts["parameters"].append({"name": name, "line": _line(ident)})

    bindings: list[tuple[Any, str, str, bool]] = []
    for node in _walk(tree.root_node):
        if node.type != "binding" or not (attr := qualified_attr(node)):
            continue
        nid = _make_id(stem, attr)
        local = is_let_binding(node)
        bindings.append((node, attr, nid, local))
        add_node(
            nid,
            attr,
            _line(node),
            type="binding",
            scope="let" if local else "config",
            graph_role="occurrence",
            semantic_rank=0.2,
        )
        add_edge(file_nid, nid, "contains", _line(node))

    # Same-file references are exact only when a short name identifies one
    # definition. This avoids turning ubiquitous names such as enable/package
    # into accidental god nodes.
    by_short_name: dict[str, list[str]] = defaultdict(list)
    for _node, attr, nid, _local in bindings:
        short = attr.rsplit(".", 1)[-1]
        if "${" not in short:
            by_short_name[short].append(nid)
    unique_defs = {
        name: ids[0] for name, ids in by_short_name.items() if len(set(ids)) == 1
    }

    for binding, attr, owner_nid, local in bindings:
        own_attr = next(
            (child for child in binding.children if child.type == "attrpath"), None
        )
        identifiers: set[str] = set()
        selections: set[str] = set()
        calls: set[str] = set()
        paths: list[dict] = []
        value_text = text(binding)

        for node in _walk(binding, stop_at_bindings=True):
            if node is own_attr:
                continue
            if node.type == "identifier":
                name = text(node).strip()
                if name and name not in _BUILTINS:
                    identifiers.add(name)
                    if target := unique_defs.get(name):
                        add_edge(
                            owner_nid,
                            target,
                            "references",
                            _line(node),
                            context="identifier",
                        )
            elif node.type == "select_expression":
                selection = _normalise_attrpath(text(node))
                if selection:
                    selections.add(selection)
            elif node.type == "apply_expression":
                head = next((child for child in node.children if child.is_named), None)
                if head is not None:
                    call = _normalise_attrpath(text(head))
                    if call and len(call) < 160:
                        calls.add(call)
            elif node.type == "path_expression":
                raw = text(node).strip()
                if target_path := _resolve_nix_path(path, raw):
                    paths.append(
                        {"raw": raw, "target": str(target_path), "line": _line(node)}
                    )
                    add_edge(
                        file_nid,
                        _make_id(str(target_path)),
                        "imports",
                        _line(node),
                        context=attr,
                    )
                elif raw.startswith(("./", "../", "/")):
                    asset = (
                        (path.parent / raw).resolve()
                        if not raw.startswith("/")
                        else Path(raw).resolve()
                    )
                    if asset.is_file():
                        facts["assets"].append(
                            {"owner": attr, "path": str(asset), "line": _line(node)}
                        )

            # `with pkgs; [ foo bar ]` has no select_expression for foo/bar.
            # Capture the list body explicitly without treating the namespace
            # identifier itself as a package.
            if node.type == "with_expression":
                named = [child for child in node.children if child.is_named]
                if len(named) >= 2 and _normalise_attrpath(text(named[0])) in {
                    "pkgs",
                    "pkgsUnstable",
                }:
                    package_set = _normalise_attrpath(text(named[0]))
                    for item_node in _walk(named[1]):
                        if item_node.type != "identifier":
                            continue
                        package = text(item_node).strip()
                        if (
                            package
                            and package not in _BUILTINS
                            and package not in parameter_names
                            and package not in unique_defs
                            and f"{package_set}.{package}" not in _PACKAGE_BUILDERS
                        ):
                            facts["packages"].append(
                                {
                                    "package": package,
                                    "set": package_set,
                                    "owner": attr,
                                    "line": _line(item_node),
                                }
                            )

        fact = {
            "attr": attr,
            "line": _line(binding),
            "local": local,
            "identifiers": sorted(identifiers),
            "selections": sorted(selections),
            "calls": sorted(calls),
            "paths": paths,
        }
        facts["bindings"].append(fact)
        facts["selections"].extend(
            {"owner": attr, "value": value, "line": _line(binding)}
            for value in selections
        )
        facts["function_calls"].extend(
            {"owner": attr, "value": value, "line": _line(binding)} for value in calls
        )

        for path_fact in paths:
            facts["imports"].append({"owner": attr, **path_fact})
        if paths and re.search(r"\bimport\s+", value_text):
            for path_fact in paths:
                facts["import_aliases"].append(
                    {"alias": attr.rsplit(".", 1)[-1], "owner": attr, **path_fact}
                )

        option = _option_key(attr)
        if attr.startswith("options.") or calls.intersection(_OPTION_CONSTRUCTORS):
            facts["option_declarations"].append(
                {"option": option, "owner": attr, "line": _line(binding)}
            )
        elif (
            outer_function is not None
            and not local
            and option.split(".", 1)[0] in _CONFIG_ROOTS
        ):
            facts["option_assignments"].append(
                {"option": option, "owner": attr, "line": _line(binding)}
            )

        # Flake inputs and their consumers.
        if attr.startswith("inputs.") and not attr.startswith("outputs."):
            pieces = attr.split(".")
            if len(pieces) >= 2:
                input_name = pieces[1]
                url_match = re.search(
                    r"(?:github|gitlab|sourcehut|path|git\+https?|https?)[:=][^\s\"';]+",
                    value_text,
                )
                facts["flake_inputs"].append(
                    {
                        "name": input_name,
                        "owner": attr,
                        "line": _line(binding),
                        "url": url_match.group(0) if url_match else None,
                        "follows": (
                            _STRING_RE.search(value_text).group(1)
                            if attr.endswith(".follows")
                            and _STRING_RE.search(value_text)
                            else None
                        ),
                    }
                )
        for selection in selections:
            if selection.startswith("inputs."):
                parts = selection.split(".")
                if len(parts) >= 2:
                    facts["input_uses"].append(
                        {
                            "name": parts[1],
                            "selection": selection,
                            "owner": attr,
                            "line": _line(binding),
                        }
                    )

        # Package references include pkgs.foo, pkgsUnstable.foo, and longer
        # paths such as pkgs.python3Packages.requests.
        for selection in selections:
            parts = selection.split(".")
            if (
                len(parts) >= 2
                and parts[0] in {"pkgs", "pkgsUnstable"}
                and selection not in _PACKAGE_BUILDERS
            ):
                facts["packages"].append(
                    {
                        "package": ".".join(parts[1:]),
                        "set": parts[0],
                        "owner": attr,
                        "line": _line(binding),
                    }
                )

        if attr.endswith("specialArgs") or attr.endswith("extraSpecialArgs"):
            provided = sorted(
                name
                for name in identifiers
                if name not in {"inherit", "inputs", "self"}
            )
            # inputs/self are meaningful arguments too; include them explicitly
            # when present instead of filtering them as syntax noise.
            provided += [name for name in ("inputs", "self") if name in identifiers]
            facts["argument_providers"].extend(
                {"name": name, "owner": attr, "line": _line(binding)}
                for name in dict.fromkeys(provided)
            )
        else:
            for marker in (".extraSpecialArgs.", ".specialArgs."):
                if marker not in attr:
                    continue
                prefix, nested = attr.split(marker, 1)
                name = nested.split(".", 1)[0]
                owner = prefix + marker[:-1]
                if name:
                    facts["argument_providers"].append(
                        {
                            "name": name,
                            "owner": owner,
                            "line": _line(binding),
                        }
                    )
                break

        for call in calls.intersection(_CONDITION_CALLS):
            condition = None
            call_node = next(
                (
                    n
                    for n in _walk(binding, stop_at_bindings=True)
                    if n.type == "apply_expression"
                    and _normalise_attrpath(
                        text(next((c for c in n.children if c.is_named), n))
                    )
                    == call
                ),
                None,
            )
            if call_node is not None:
                named = [child for child in call_node.children if child.is_named]
                if len(named) > 1:
                    condition = text(named[1]).strip()[:200]
            facts["conditions"].append(
                {
                    "owner": attr,
                    "call": call,
                    "condition": condition,
                    "line": _line(binding),
                }
            )

    return {"nodes": nodes, "edges": edges, "nix_facts": facts}


def resolve_nix_semantics(
    per_file: list[dict], all_nodes: list[dict], all_edges: list[dict]
) -> None:
    """Resolve cross-file Nix concepts after graphify canonicalises node IDs."""
    fact_sets = [
        result.get("nix_facts") for result in per_file if result.get("nix_facts")
    ]
    if not fact_sets:
        return

    def source_key(value: str) -> str:
        try:
            return str(Path(value).resolve())
        except Exception:
            return value

    nodes_by_id = {node["id"]: node for node in all_nodes}
    by_source_label: dict[tuple[str, str], list[str]] = defaultdict(list)
    file_by_source: dict[str, str] = {}
    parameters: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for node in all_nodes:
        source = node.get("source_file")
        if not source or not str(source).endswith(".nix"):
            continue
        key = source_key(str(source))
        by_source_label[(key, str(node.get("label", "")))].append(node["id"])
        if node.get("source_location") is None and str(node.get("label", "")).endswith(
            ".nix"
        ):
            file_by_source[key] = node["id"]
        if node.get("type") == "parameter" or str(node.get("label", "")).startswith(
            "parameter "
        ):
            name = str(node.get("label", "")).removeprefix("parameter ")
            parameters[name].append((node["id"], key))

    # Basenames and option occurrences are intentionally repeated in Nix, but
    # repeated display labels make explain/path resolution arbitrary. Keep the
    # canonical concept concise and qualify only colliding occurrence nodes.
    nix_sources = sorted(file_by_source)
    try:
        import os

        common_root = Path(os.path.commonpath(nix_sources))
        if common_root.suffix == ".nix":
            common_root = common_root.parent
    except (OSError, ValueError):
        common_root = Path("/")

    def relative_source(node: dict) -> str:
        try:
            return str(
                Path(str(node.get("source_file", "")))
                .resolve()
                .relative_to(common_root)
            )
        except (OSError, ValueError):
            return str(node.get("source_file", ""))

    duplicate_occurrences: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for node in all_nodes:
        if node.get("lang") == "nix" and node.get("type") in {"binding", "module"}:
            duplicate_occurrences[
                (str(node.get("type")), str(node.get("label", "")))
            ].append(node)
    for (_kind, label), occurrences in duplicate_occurrences.items():
        sources = {str(node.get("source_file", "")) for node in occurrences}
        if label and len(sources) > 1:
            for node in occurrences:
                node["canonical_label"] = label
                node["label"] = f"{label} @ {relative_source(node)}"

    seen_edges = {
        (e.get("source"), e.get("target"), e.get("relation")) for e in all_edges
    }
    concept_ids: dict[tuple[str, str], str] = {}

    def find_binding(source: str, label: str) -> str | None:
        matches = by_source_label.get((source_key(source), label), [])
        return matches[0] if len(matches) == 1 else None

    def add_concept(
        kind: str, key: str, label: str, evidence: dict, **attrs: Any
    ) -> str:
        token = (kind, key)
        if token in concept_ids:
            return concept_ids[token]
        nid = _make_id("nix", kind, key)
        concept_ids[token] = nid
        if nid not in nodes_by_id:
            node = {
                "id": nid,
                "label": label,
                "file_type": "concept",
                "type": kind,
                "lang": "nix",
                "source_file": evidence.get("source_file", ""),
                "source_location": f"L{evidence['line']}"
                if evidence.get("line")
                else None,
                "graph_role": "concept",
                "semantic_rank": attrs.pop("semantic_rank", 1.0),
            }
            node.update(attrs)
            all_nodes.append(node)
            nodes_by_id[nid] = node
        return nid

    def add_edge(
        src: str | None,
        dst: str | None,
        relation: str,
        evidence: dict,
        confidence: str = "EXTRACTED",
        score: float = 1.0,
        context: str | None = None,
    ) -> None:
        if not src or not dst or src == dst or (src, dst, relation) in seen_edges:
            return
        seen_edges.add((src, dst, relation))
        edge = {
            "source": src,
            "target": dst,
            "relation": relation,
            "confidence": confidence,
            "confidence_score": score,
            "source_file": evidence.get("source_file", ""),
            "source_location": f"L{evidence['line']}" if evidence.get("line") else None,
            "weight": _edge_weight(relation),
        }
        if context:
            edge["context"] = context
        all_edges.append(edge)

    # Build import-alias/export facts before the main pass.
    exports_by_source_short: dict[tuple[str, str], list[str]] = defaultdict(list)
    aliases: dict[tuple[str, str], tuple[str, dict]] = {}
    input_nodes: dict[str, str] = {}
    module_adjacency: dict[str, set[str]] = defaultdict(set)
    imports_by_source: dict[str, list[dict]] = defaultdict(list)
    for facts in fact_sets:
        source = source_key(facts["source_file"])
        for binding in facts["bindings"]:
            nid = find_binding(source, binding["attr"])
            if nid:
                exports_by_source_short[
                    (source, binding["attr"].rsplit(".", 1)[-1])
                ].append(nid)
        for alias in facts["import_aliases"]:
            aliases[(source, alias["alias"])] = (
                source_key(alias["target"]),
                {**alias, "source_file": facts["source_file"]},
            )
        for item in facts["imports"]:
            evidence = {**item, "source_file": facts["source_file"]}
            imports_by_source[source].append(evidence)
            owner = item["owner"]
            if (
                owner == "imports"
                or owner.endswith(".imports")
                or ".modules" in owner
                or ".users." in owner
            ):
                module_adjacency[source].add(source_key(item["target"]))
        for item in facts["flake_inputs"]:
            owner = find_binding(source, item["owner"])
            if not owner:
                continue
            evidence = {**item, "source_file": facts["source_file"]}
            input_nid = input_nodes.setdefault(
                item["name"],
                add_concept(
                    "flake_input",
                    item["name"],
                    f"flake input {item['name']}",
                    evidence,
                    input=item["name"],
                    url=item.get("url"),
                ),
            )
            add_edge(owner, input_nid, "defines_flake_input", evidence)

    option_nodes: dict[str, str] = {}
    package_nodes: dict[str, str] = {}
    service_nodes: dict[str, str] = {}
    function_nodes: dict[str, str] = {}
    provider_facts: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    option_evidence: dict[str, dict] = {}
    theme_nodes: dict[str, str] = {}
    architecture_nodes: dict[str, str] = {}

    def architecture_layer(source: str) -> tuple[str, str] | None:
        value = source.replace("\\", "/")
        for marker, key, label in (
            ("/modules/nixos/core/", "nixos_core", "NixOS core"),
            ("/modules/nixos/desktop/", "nixos_desktop", "NixOS desktop"),
            ("/modules/nixos/profiles/", "nixos_profiles", "NixOS profiles"),
            ("/modules/nixos/hardware/", "nixos_hardware", "NixOS hardware"),
            ("/modules/home/", "home_manager", "Home Manager configuration"),
            ("/hosts/", "host_configuration", "Host configuration"),
            ("/themes/", "theme_system", "Theme system"),
            ("/lib/", "nix_library", "Nix library"),
        ):
            if marker in value:
                return key, label
        if value.endswith("/flake.nix"):
            return "flake_composition", "Flake composition"
        return None

    for facts in fact_sets:
        source = source_key(facts["source_file"])

        if layer := architecture_layer(source):
            evidence = {"source_file": facts["source_file"], "line": 1}
            layer_nid = add_concept(
                "architecture",
                layer[0],
                layer[1],
                evidence,
                architecture_layer=layer[0],
            )
            architecture_nodes[layer[0]] = layer_nid
            add_edge(
                file_by_source.get(source),
                layer_nid,
                "belongs_to_layer",
                evidence,
                "INFERRED",
                0.95,
            )

    # A small, explicit semantic backbone connects the conventional layers.
    # Architectural queries can cross NixOS/Home Manager/theme boundaries
    # without walking through hundreds of option and containment edges.
    architecture_root_evidence = {
        "source_file": fact_sets[0]["source_file"],
        "line": 1,
    }
    architecture_root = add_concept(
        "architecture",
        "nix_configuration",
        "Nix configuration architecture",
        architecture_root_evidence,
        architecture_layer="nix_configuration",
        semantic_rank=1.5,
    )
    for layer_nid in architecture_nodes.values():
        add_edge(
            layer_nid,
            architecture_root,
            "part_of_architecture",
            architecture_root_evidence,
            "INFERRED",
            0.95,
        )

    for facts in fact_sets:
        source = source_key(facts["source_file"])

        # Theme registries are ordinary Nix attrsets, but their top-level
        # bindings and selected-name file have strong project semantics.
        if "/themes/" in source.replace("\\", "/"):
            for binding in facts["bindings"]:
                name = binding["attr"]
                if "." in name or name in {"selected", "themes", "active"}:
                    continue
                evidence = {**binding, "source_file": facts["source_file"]}
                theme_nid = theme_nodes.setdefault(
                    name,
                    add_concept("theme", name, f"theme {name}", evidence, theme=name),
                )
                add_edge(
                    find_binding(source, name), theme_nid, "defines_theme", evidence
                )
            if selected := facts.get("root_string"):
                evidence = {"source_file": facts["source_file"], "line": 1}
                theme_nid = theme_nodes.setdefault(
                    selected,
                    add_concept(
                        "theme", selected, f"theme {selected}", evidence, theme=selected
                    ),
                )
                add_edge(
                    file_by_source.get(source), theme_nid, "selects_theme", evidence
                )

        for item in facts["option_declarations"] + facts["option_assignments"]:
            option = item["option"]
            if not option:
                continue
            evidence = {**item, "source_file": facts["source_file"]}
            option_nid = option_nodes.setdefault(
                option,
                add_concept(
                    "option",
                    option,
                    f"{option} (Nix option)",
                    evidence,
                    option_path=option,
                    semantic_rank=0.9,
                ),
            )
            option_evidence.setdefault(option, evidence)
            owner = find_binding(source, item["owner"])
            relation = (
                "declares_option"
                if item in facts["option_declarations"]
                else "sets_option"
            )
            add_edge(owner, option_nid, relation, evidence)
            parts = option.split(".")
            root = parts[0]
            service = parts[1] if len(parts) > 1 and root == "services" else ""
            if service:
                service_nid = service_nodes.setdefault(
                    service,
                    add_concept(
                        "service",
                        service,
                        f"service {service}",
                        evidence,
                        service=service,
                    ),
                )
                add_edge(option_nid, service_nid, "configures_service", evidence)
            if (
                root in {"stylix", "gtk", "qt", "xresources"}
                or "theme" in option.lower()
            ):
                theme_nid = add_concept(
                    "domain", "theming", "Desktop theming", evidence
                )
                add_edge(
                    option_nid, theme_nid, "participates_in", evidence, "INFERRED", 0.85
                )

        for item in facts["assets"]:
            evidence = {**item, "source_file": facts["source_file"]}
            asset_path = item["path"]
            asset_nid = add_concept(
                "asset",
                asset_path,
                Path(asset_path).name,
                evidence,
                asset_path=asset_path,
            )
            owner = find_binding(source, item["owner"])
            add_edge(owner, asset_nid, "uses_asset", evidence)
            theme_name = item["owner"].split(".", 1)[0]
            if theme_name in theme_nodes:
                add_edge(theme_nodes[theme_name], asset_nid, "uses_wallpaper", evidence)

        for item in facts["packages"]:
            evidence = {**item, "source_file": facts["source_file"]}
            key = f"{item['set']}.{item['package']}"
            package_nid = package_nodes.setdefault(
                key,
                add_concept(
                    "package",
                    key,
                    key,
                    evidence,
                    package=item["package"],
                    package_set=item["set"],
                ),
            )
            add_edge(
                find_binding(source, item["owner"]),
                package_nid,
                "uses_package",
                evidence,
            )

        for item in facts["input_uses"]:
            evidence = {**item, "source_file": facts["source_file"]}
            input_nid = input_nodes.get(item["name"])
            if input_nid:
                owner = find_binding(source, item["owner"])
                relation = "uses_flake_input"
                if (
                    ".nixosModules." in item["selection"]
                    or ".homeModules." in item["selection"]
                ):
                    relation = "uses_input_module"
                elif ".packages." in item["selection"]:
                    relation = "uses_input_package"
                add_edge(owner, input_nid, relation, evidence)

        for item in facts["flake_inputs"]:
            if not item.get("follows"):
                continue
            evidence = {**item, "source_file": facts["source_file"]}
            add_edge(
                find_binding(source, item["owner"]),
                input_nodes.get(item["follows"]),
                "follows_input",
                evidence,
            )

        for item in facts["argument_providers"]:
            evidence = {**item, "source_file": facts["source_file"]}
            owner = find_binding(source, item["owner"])
            if owner:
                provider_facts[item["name"]].append((owner, evidence))

        for item in facts["function_calls"]:
            call = item["value"]
            if not (
                call.startswith("lib.")
                or call.startswith("builtins.")
                or call in _PACKAGE_BUILDERS
            ):
                continue
            evidence = {**item, "source_file": facts["source_file"]}
            fn_nid = function_nodes.setdefault(
                call, add_concept("function", call, call, evidence, function=call)
            )
            add_edge(
                find_binding(source, item["owner"]),
                fn_nid,
                "calls_nix_function",
                evidence,
            )

        for item in facts["conditions"]:
            evidence = {**item, "source_file": facts["source_file"]}
            label = item.get("condition") or item["call"]
            condition_nid = add_concept(
                "condition", label, f"condition {label}", evidence, expression=label
            )
            add_edge(
                find_binding(source, item["owner"]),
                condition_nid,
                "conditioned_by",
                evidence,
            )

        # Resolve `alias.export` where alias was assigned from `import ./path`.
        for item in facts["selections"]:
            selection = item["value"]
            head, dot, remainder = selection.partition(".")
            if not dot or (source, head) not in aliases:
                continue
            target_source, alias_evidence = aliases[(source, head)]
            export_name = remainder.split(".", 1)[0]
            candidates = exports_by_source_short.get((target_source, export_name), [])
            if len(candidates) == 1:
                evidence = {**item, "source_file": facts["source_file"]}
                add_edge(
                    find_binding(source, item["owner"]),
                    candidates[0],
                    "references_imported_export",
                    evidence,
                )

    # Preserve the option namespace instead of leaving hundreds of settings as
    # unrelated leaves. Only connect to parents that actually occur in the
    # corpus, avoiding synthetic high-level god nodes.
    for option, option_nid in list(option_nodes.items()):
        parent = option.rpartition(".")[0]
        if not parent or "." not in parent:
            continue
        if parent not in option_nodes:
            evidence = option_evidence[option]
            option_nodes[parent] = add_concept(
                "option",
                parent,
                f"{parent} (Nix option)",
                evidence,
                option_path=parent,
                synthetic=True,
                semantic_rank=0.55,
            )
            option_evidence[parent] = evidence
        add_edge(
            option_nid,
            option_nodes[parent],
            "option_parent",
            option_evidence[option],
            "INFERRED",
            0.95,
        )

    def reachable_modules(seeds: set[str]) -> set[str]:
        seen = set(seeds)
        pending = list(seeds)
        while pending:
            current = pending.pop()
            for target in module_adjacency.get(current, set()):
                if target not in seen:
                    seen.add(target)
                    pending.append(target)
        return seen

    def provider_scope(evidence: dict) -> set[str]:
        source = source_key(evidence["source_file"])
        owner = evidence.get("owner", "")
        imports = imports_by_source.get(source, [])
        if owner.endswith("extraSpecialArgs"):
            prefix = owner.removesuffix("extraSpecialArgs")
            seeds = {
                source_key(item["target"])
                for item in imports
                if item["owner"].startswith(prefix) and ".users." in item["owner"]
            }
            if not seeds:
                seeds = {
                    source_key(item["target"])
                    for item in imports
                    if "/home/" in source_key(item["target"]).replace("\\", "/")
                }
            return reachable_modules(seeds)
        if owner.endswith("specialArgs"):
            prefix = owner.removesuffix("specialArgs")
            seeds = {
                source_key(item["target"])
                for item in imports
                if item["owner"].startswith(prefix + "modules")
                and ".home-manager.users." not in item["owner"]
            }
            return reachable_modules(seeds)
        return set()

    # Argument propagation is intentionally conservative: only names explicitly
    # provided by specialArgs/extraSpecialArgs are connected, and ambiguous
    # providers remain INFERRED instead of being silently dropped. When the
    # module graph identifies a provider's subtree, do not leak the argument to
    # unrelated library functions that happen to use the same parameter name.
    for name, providers in provider_facts.items():
        for parameter_nid, parameter_source in parameters.get(name, []):
            for provider_nid, evidence in providers:
                if source_key(evidence["source_file"]) == parameter_source:
                    continue
                scope = provider_scope(evidence)
                if scope and parameter_source not in scope:
                    continue
                add_edge(
                    provider_nid,
                    parameter_nid,
                    "passes_argument",
                    evidence,
                    "INFERRED",
                    0.85,
                    name,
                )

    enrich_nix_documentation({"nodes": all_nodes, "edges": all_edges})


def enrich_nix_documentation(extraction: dict) -> None:
    """Bridge semantic document nodes after AST and LLM fragments are merged."""
    nodes = extraction.get("nodes", [])
    edges = extraction.setdefault("edges", [])

    def label_key(value: object) -> str:
        return re.sub(r"[^a-z0-9]+", "", str(value).lower())

    bridge_targets: dict[str, list[str]] = defaultdict(list)
    target_by_kind_key: dict[tuple[str, str], str] = {}
    for node in nodes:
        kind = str(node.get("type", ""))
        if kind not in {
            "service",
            "theme",
            "architecture",
            "domain",
            "flake_input",
            "package",
            "option",
            "function",
        }:
            continue
        nid = node["id"]
        label = str(node.get("label", ""))
        aliases = {label_key(label)}
        for prefix in ("service ", "theme ", "flake input "):
            if label.lower().startswith(prefix):
                aliases.add(label_key(label[len(prefix) :]))
        if kind == "option" and node.get("option_path"):
            aliases.add(label_key(node["option_path"]))
        for alias in aliases:
            if alias:
                bridge_targets[alias].append(nid)
        semantic_key = str(
            node.get("service")
            or node.get("theme")
            or node.get("architecture_layer")
            or node.get("input")
            or ""
        )
        if kind == "domain" and label_key(label) == "desktoptheming":
            semantic_key = "theming"
        if semantic_key:
            target_by_kind_key[(kind, semantic_key)] = nid

    seen = {
        (edge.get("source"), edge.get("target"), edge.get("relation")) for edge in edges
    }
    for node in list(nodes):
        if node.get("lang") == "nix" or node.get("file_type") not in {
            "document",
            "concept",
            "rationale",
        }:
            continue
        if Path(str(node.get("source_file", ""))).suffix.lower() not in {
            ".md",
            ".mdx",
            ".qmd",
            ".txt",
            ".rst",
        }:
            continue
        key = label_key(node.get("label", ""))
        candidates = set(bridge_targets.get(key, []))
        if "theme" in key:
            for token in (("domain", "theming"), ("architecture", "theme_system")):
                if target := target_by_kind_key.get(token):
                    candidates.add(target)
        if "flake" in key:
            if target := target_by_kind_key.get(("architecture", "flake_composition")):
                candidates.add(target)
        if "nixos" in key and "configuration" in key:
            if target := target_by_kind_key.get(("architecture", "host_configuration")):
                candidates.add(target)
        if key == "homemanager":
            if target := target_by_kind_key.get(("architecture", "home_manager")):
                candidates.add(target)
        if "foundryvtt" in key:
            if target := target_by_kind_key.get(("service", "foundryvtt")):
                candidates.add(target)
        if key == "foundrywebui":
            if target := target_by_kind_key.get(("service", "foundryvtt")):
                candidates.add(target)
        if key == "dirtygraphoutputtolerance":
            if target := target_by_kind_key.get(("flake_input", "graphify")):
                candidates.add(target)
        # Phrase containment is deliberately limited to stable, named semantic
        # entities. It connects headings such as "Graphify Knowledge Graph"
        # and "Generated Hyprland Lua" without fuzzy all-to-all doc linking.
        for alias, targets in bridge_targets.items():
            if len(alias) >= 5 and alias in key:
                candidates.update(targets)
        if key == "systempackages":
            candidates.update(
                bridge_targets.get(label_key("environment.systemPackages"), [])
            )
        if key == "userpackages":
            candidates.update(bridge_targets.get(label_key("home.packages"), []))
        if "nixoshost" in key:
            if target := target_by_kind_key.get(("architecture", "host_configuration")):
                candidates.add(target)
        for target in sorted(candidates):
            edge_key = (node["id"], target, "documents")
            if edge_key in seen or node["id"] == target:
                continue
            seen.add(edge_key)
            edges.append(
                {
                    "source": node["id"],
                    "target": target,
                    "relation": "documents",
                    "confidence": "INFERRED",
                    "confidence_score": 0.85,
                    "source_file": node.get("source_file", ""),
                    "source_location": node.get("source_location"),
                    "weight": _edge_weight("documents"),
                }
            )
