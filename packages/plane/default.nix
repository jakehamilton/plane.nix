{ lib, pkgs }:

let
  inherit (pkgs.yarn2nix-moretea) mkYarnWorkspace;

	jq = lib.getExe pkgs.jq;

  src = pkgs.fetchFromGitHub {
    owner = "makeplane";
    repo = "plane";
    rev = "0068ea93deeef5ef2f52f6116483a42c738bce06";
    sha256 = "06pfjzzymf0kz1zbpqz6ql137bp0yizfhx34kspvljqrd9v362z5";
  };

	includeNodeModulesPath = ''
		export PATH=$(pwd)/node_modules/.bin:$PATH
	'';

	withLinkedModule = name: ''
		typescript_config_pkg=${workspace.${name}}/libexec/${workspace.${name}.pname}/deps/${workspace.${name}.pname}

		mkdir -p $(dirname ./node_modules/${workspace.${name}.pname})

		ln -s $typescript_config_pkg ./node_modules/${workspace.${name}.pname}
	'';

	yarnBuild = ''
		pushd deps/$pname

		yarn build

		popd
	'';

  workspace = mkYarnWorkspace {
    inherit src;
    packageOverrides = {
      plane-typescript-config = {};

      plane-helpers = {
        buildPhase = ''
					${includeNodeModulesPath}

					# Packages don't properly add this package to their dev dependencies so we have to link
					# it manually instead.
					${withLinkedModule "plane-typescript-config"}

					${yarnBuild}
				'';
      };

      plane-ui = {
        buildPhase = ''
					${includeNodeModulesPath}

					# Packages don't properly add this package to their dev dependencies so we have to link
					# it manually instead.
					${withLinkedModule "plane-typescript-config"}

					${yarnBuild}
				'';

				postInstall = ''
					pushd $out/libexec/$pname/deps/$pname

					${jq} '.files += ["src/**"]' package.json > package.json.tmp
					mv package.json.tmp package.json

					popd
				'';
      };

      plane-editor = {
        buildPhase = ''
					${includeNodeModulesPath}

					# Packages don't properly add this package to their dev dependencies so we have to link
					# it manually instead.
					${withLinkedModule "plane-typescript-config"}

					${yarnBuild}
				'';
      };

      web = {
        buildPhase = ''
					${includeNodeModulesPath}

					# Packages don't properly add this package to their dev dependencies so we have to link
					# it manually instead.
					${withLinkedModule "plane-typescript-config"}

					ls -la $(realpath node_modules/@plane/ui)
					exit 1

					pushd deps/web
						rm -rf web
					popd

					${yarnBuild}
				'';
      };
    };
  };
in
	(builtins.trace (builtins.attrNames workspace))
workspace.web
