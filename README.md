# ✈️ . ❄️

Bringing Nix & NixOS support to [Plane](https://plane.so), this repository provides packages
for each component of Plane as well as a NixOS module for bringing up an instance in production.

> [!NOTE]
> This repository has been created in a short amount of time and certain settings may not be fully
> configurable in the NixOS module. Contributions are welcome to help resolve any omissions!

## Installation

To use Plane on your NixOS machine, you will need to add this repository as an input to your
[Nix Flake](https://wiki.nixos.org/wiki/Flakes).

```nix
# flake.nix
{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

        # Add Plane as an input:
        plane-nix = {
            url = "github:jakehamilton/plane.nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };
}
```

Next, include the NixOS module on the system that you would like to host Plane with.

```nix
# flake.nix
{
    # ... inputs ...

    outputs = inputs: {
        nixosConfigurations.myHost = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";

            modules = [
                ./configuration.nix

                # Add Plane to your system:
                inputs.plane-nix.nixosModules."services/plane"
            ];
        };
    };
}
```

Finally, in your system configuration you can enable Plane and configure its settings.

```nix
# configuration.nix
{ pkgs, ... }:
{
    # Configure Plane
    services.plane = {
        enable = true;
        domain = "example.com";

        # A file containing the secret key used by the Plane apiserver.
        secretKeyFile = "/my/secret/key";

        database = {
            local = true;
            # A file containing the postgres password used by Plane.
            passwordFile = "/my/secret/password";
        };

        storage = {
            local = true;
            # A file containing the minio-style credentials used by Plane.
            # See services.minio.rootCredentialsFile for formatting information:
            # https://search.nixos.org/options?channel=24.05&show=services.minio.rootCredentialsFile&from=0&size=50&sort=relevance&type=packages&query=services.minio.rootCredentialsFile
            credentialsFile = "/my/secret/credentials";
        };

        cache = {
            local = true;
        };

        acme = {
            enable = true;
        };
    };
}
```
