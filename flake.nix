{
  description = "Nix support for plane.so";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

		mach-nix = {
			url = "github:DavHau/mach-nix";
			inputs.nixpkgs.follows = "nixpkgs";
			inputs.pypi-deps-db.follows = "pypi-deps-db";
		};

		pypi-deps-db = {
			url = "github:jakehamilton/pypi-deps-db";
			inputs.nixpkgs.follows = "nixpkgs";
		};
  };

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;

      src = ./.;
    };
}
