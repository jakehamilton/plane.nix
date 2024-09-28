{ lib, pkgs }:

let
  inherit (pkgs.yarn2nix-moretea) mkYarnWorkspace;

	jq = lib.getExe pkgs.jq;

  src = pkgs.fetchFromGitHub {
    owner = "makeplane";
    repo = "plane";
		rev = "707570ca7ab95d6680953de939f6acf78480ae01";
		sha256 = "09kn6y8s6ziqmpn8x4cfsis3q5a9ii6ckvm3b71l73w7j78f70zq";

		# TODO: Upgrade to latest when `web` no longer fails to build.
    # rev = "0068ea93deeef5ef2f52f6116483a42c738bce06";
    # sha256 = "06pfjzzymf0kz1zbpqz6ql137bp0yizfhx34kspvljqrd9v362z5";
  };

	includeNodeModulesPath = ''
		export PATH=$(pwd)/node_modules/.bin:$PATH
	'';

	withLinkedModule = name: ''
		typescript_config_pkg=${workspace.${name}}/libexec/${workspace.${name}.pname}/deps/${workspace.${name}.pname}

		mkdir -p $(dirname ./node_modules/${workspace.${name}.pname})

		ln -s $typescript_config_pkg ./node_modules/${workspace.${name}.pname}
	'';

	# NOTE: The build system for some packages seems to choke when trying to stat this recursive link.
	# Thankfully we don't need it and can safely get rid of it for these cases.
	removeRecursiveSelfLink = ''
		rm -r deps/$pname/$(basename $pname)
	'';

	yarnBuild = ''
		pushd deps/$pname

		yarn build

		popd
	'';

	# NOTE: We have to use `--experimental-build-mode compile` here due to an error with builds failing otherwise.
	# Without it, there is an issue with `useContext` not finding the appropriate context for `usePathname`.
	# Potentially relevant issue:
	# https://github.com/vercel/next.js/issues/63123
	nextBuild = ''
		pushd deps/$pname

		./node_modules/.bin/next build --experimental-build-mode compile

		popd
	'';

	addServerBin = ''
		makeWrapper ${pkgs.nodejs}/bin/node $out/bin/server \
			--add-flags "$out/libexec/$pname/deps/$pname/.next/standalone/server.js"
	'';

  workspace = mkYarnWorkspace {
    inherit src;
    packageOverrides = {
			# TODO: Submit a PR to make this a proper dependency of the other packages.
			# Packages don't properly add this package to their dev dependencies so we have to link
			# it manually instead.
			# ${withLinkedModule "plane-typescript-config"}
      # plane-typescript-config = {};

      plane-helpers = {
        buildPhase = ''
					${includeNodeModulesPath}

					${yarnBuild}
				'';
      };

      plane-ui = {
        buildPhase = ''
					${includeNodeModulesPath}

					${yarnBuild}
				'';

				# TODO: Submit a PR to add "src/**" to the files array in package.json so that the packed
				# tarball includes the source files which other packages try to link to for types.
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

					${yarnBuild}
				'';
      };

      admin = {
				doDist = false;

				nativeBuildInputs = [
					pkgs.makeWrapper
				];

        buildPhase = ''
					${includeNodeModulesPath}

					pushd deps/admin
						rm -rf admin
					popd

					${nextBuild}
				'';

				postInstall = ''
					${addServerBin}
				'';
      };

      web = {
        buildPhase = ''
					${includeNodeModulesPath}

					pushd deps/web
						rm -rf web
					popd

					${nextBuild}
				'';
      };
    };
  };
in
	(builtins.trace (builtins.attrNames workspace))
workspace.admin
