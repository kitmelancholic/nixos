{
  description = "kitOS v0.1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

    outputs = { self, nixpkgs, home-manager, ... }@inputs: {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

	modules = [ 
	  ./hosts/nixos/configuration.nix

	  home-manager.nixosModules.default

	  {
	    home-manager = {
	      useGlobalPkgs = true;
	      useUserPackages = true;
	      backupFileExtension = "hm-backup";

	      users.kit = import ./home/kit.nix;
            };
          }
        ];
      };
    };
}
