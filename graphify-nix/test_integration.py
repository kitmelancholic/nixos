"""End-to-end tests for the graphify Nix extractor and semantic resolver."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from graphify.extract import extract
from graphify.extractors.nix import enrich_nix_documentation


class NixIntegrationTest(unittest.TestCase):
    def test_documentation_bridges_named_concepts(self) -> None:
        extraction = {
            "nodes": [
                {
                    "id": "service",
                    "label": "service foundryvtt",
                    "type": "service",
                    "service": "foundryvtt",
                    "lang": "nix",
                },
                {
                    "id": "input",
                    "label": "flake input graphify",
                    "type": "flake_input",
                    "input": "graphify",
                    "lang": "nix",
                },
                {
                    "id": "foundry_doc",
                    "label": "Foundry Web UI",
                    "file_type": "document",
                    "source_file": "README.md",
                },
                {
                    "id": "policy_doc",
                    "label": "Dirty Graph Output Tolerance",
                    "file_type": "concept",
                    "source_file": "AGENTS.md",
                },
            ],
            "edges": [],
        }
        enrich_nix_documentation(extraction)
        bridges = {
            (edge["source"], edge["target"])
            for edge in extraction["edges"]
            if edge.get("relation") == "documents"
        }
        self.assertIn(("foundry_doc", "service"), bridges)
        self.assertIn(("policy_doc", "input"), bridges)

    def test_cross_file_nix_semantics(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {
                "flake.nix": """
                {
                  inputs.demo.url = "github:example/demo";
                  outputs = { self, nixpkgs, ... }@inputs: {
                    nixosConfigurations.test = nixpkgs.lib.nixosSystem {
                      specialArgs = { inherit inputs; constants = { enabled = true; }; };
                      modules = [ ./module-a.nix ];
                    };
                  };
                }
                """,
                "module-a.nix": """
                { constants, inputs, pkgs, ... }:
                {
                  imports = [ ./module-b.nix ];
                  services.demo.enable = true;
                  environment.systemPackages = with pkgs; [
                    curl
                    git
                    (pkgs.writeShellApplication { name = "demo-tool"; text = "true"; })
                  ];
                  programs.demo.package = inputs.demo.packages.${pkgs.system}.default;
                }
                """,
                "module-b.nix": """
                { constants, lib, ... }:
                {
                  options.programs.demo.enable = lib.mkEnableOption "demo";
                  config.programs.demo.enable = lib.mkIf constants.enabled true;
                }
                """,
                "themes/themes.nix": """
                { ocean = { wallpaper = ./ocean.png; }; }
                """,
                "themes/selected.nix": '"ocean"\n',
            }
            for name, content in files.items():
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding="utf-8")
            (root / "themes/ocean.png").write_bytes(b"png")

            result = extract(
                [root / name for name in files],
                cache_root=root,
                parallel=False,
            )
            nodes = {node["id"]: node for node in result["nodes"]}
            edges = result["edges"]

            def edges_of(relation: str) -> list[dict]:
                return [edge for edge in edges if edge.get("relation") == relation]

            self.assertGreaterEqual(len(edges_of("imports")), 2)
            self.assertGreaterEqual(len(edges_of("passes_argument")), 2)
            self.assertTrue(edges_of("defines_flake_input"))
            self.assertTrue(edges_of("uses_input_package"))
            self.assertTrue(edges_of("uses_package"))
            self.assertTrue(edges_of("conditioned_by"))
            self.assertTrue(edges_of("option_parent"))
            self.assertTrue(edges_of("selects_theme"))
            self.assertTrue(edges_of("uses_wallpaper"))
            self.assertTrue(edges_of("part_of_architecture"))

            self.assertEqual(
                {edge["weight"] for edge in edges_of("contains")},
                {0.5},
            )
            self.assertEqual(
                {edge["weight"] for edge in edges_of("imports")},
                {1.25},
            )

            service_targets = {
                nodes[edge["target"]]["label"]
                for edge in edges_of("configures_service")
            }
            self.assertEqual(service_targets, {"service demo"})

            declared = {edge["target"] for edge in edges_of("declares_option")}
            assigned = {edge["target"] for edge in edges_of("sets_option")}
            self.assertIn("nix_option_programs_demo_enable", declared & assigned)
            self.assertEqual(
                nodes["nix_option_programs_demo_enable"]["label"],
                "programs.demo.enable (Nix option)",
            )

            builder_nodes = [
                node
                for node in nodes.values()
                if node.get("label") == "pkgs.writeShellApplication"
            ]
            self.assertEqual([node.get("type") for node in builder_nodes], ["function"])

            architecture = nodes["nix_architecture_nix_configuration"]
            self.assertEqual(architecture["semantic_rank"], 1.5)

            dangling = [
                edge
                for edge in edges
                if edge.get("source") not in nodes or edge.get("target") not in nodes
            ]
            self.assertEqual(dangling, [])


if __name__ == "__main__":
    unittest.main()
