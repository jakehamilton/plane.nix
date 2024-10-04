{
	lib,
	pkgs,
	API_BASE_URL ? "/api",
	ADMIN_BASE_URL ? "/admin",
	SPACE_BASE_URL ? "/space",
}:

let
  inherit (pkgs.yarn2nix-moretea) mkYarnWorkspace;

	poetry2nix = lib.poetry2nix.mkPoetry2Nix {
		inherit pkgs;
	};

	jq = lib.getExe pkgs.jq;

  src = pkgs.fetchFromGitHub {
    owner = "makeplane";
    repo = "plane";
		# v0.22-dev
		rev = "707570ca7ab95d6680953de939f6acf78480ae01";
		sha256 = "sha256-gu1AaE3NpRhTA5US3Chpa/tAqVnQdDFGwJR6AzzSUjI=";

		postFetch = ''
			cd $out

			patch -p1 < ${./patches/poetry.patch}
			patch -p1 < ${./patches/runtime.patch}
			patch -p1 < ${./patches/x-forwarded-for.patch}
		'';
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

	addStatic = ''
		pushd $out/libexec/$pname/deps/$pname

		mkdir -p .next/standalone/.next

		ln -s $(pwd)/.next/static .next/standalone/.next/static
		ln -s $(pwd)/.next/static $out/static

		if [ -d public ]; then
			ln -s $(pwd)/public .next/standalone/public
			ln -s $(pwd)/public $out/public
		fi

		popd
	'';

	addServerBin = ''
		makeWrapper ${pkgs.nodejs}/bin/node $out/bin/serve \
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

				NEXT_PUBLIC_API_BASE_URL = API_BASE_URL;
				NEXT_PUBLIC_ADMIN_BASE_PATH = ADMIN_BASE_URL;
				NEXT_PUBLIC_SPACE_BASE_PATH = SPACE_BASE_URL;

				nativeBuildInputs = [
					pkgs.makeWrapper
				];

        buildPhase = ''
					${includeNodeModulesPath}

					${removeRecursiveSelfLink}

					${nextBuild}
				'';

				postInstall = ''
					${addServerBin}
					${addStatic}
				'';
      };

      space = {
				doDist = false;

				NEXT_PUBLIC_API_BASE_URL = API_BASE_URL;
				NEXT_PUBLIC_ADMIN_BASE_PATH = ADMIN_BASE_URL;
				NEXT_PUBLIC_SPACE_BASE_PATH = SPACE_BASE_URL;

				nativeBuildInputs = [
					pkgs.makeWrapper
				];

        buildPhase = ''
					${includeNodeModulesPath}

					${removeRecursiveSelfLink}

					${nextBuild}
				'';

				postInstall = ''
					${addServerBin}
					${addStatic}
				'';
      };

      web = {
				doDist = false;

				NEXT_PUBLIC_API_BASE_URL = API_BASE_URL;
				NEXT_PUBLIC_ADMIN_BASE_PATH = ADMIN_BASE_URL;
				NEXT_PUBLIC_SPACE_BASE_PATH = SPACE_BASE_URL;

				nativeBuildInputs = [
					pkgs.makeWrapper
				];

        buildPhase = ''
					${includeNodeModulesPath}

					${removeRecursiveSelfLink}

					${nextBuild}
				'';

				postInstall = ''
					${addServerBin}
					${addStatic}
				'';
      };
    };
  };

	apiserver = poetry2nix.mkPoetryEnv {
		projectDir = "${src}/apiserver";

		preferWheels = true;

		overrides = poetry2nix.overrides.withDefaults (final: prev: {
			psycopg-c = prev.psycopg-c.overridePythonAttrs (old: {
				nativeBuildInputs = old.nativeBuildInputs ++ [
					pkgs.postgresql
					prev.tomli
				];
			});
		});
	};

	plane = pkgs.runCommandNoCC
		"plane"
		{
			nativeBuildInputs = [
				pkgs.makeWrapper
			];

			meta = {
				description = "Open Source JIRA, Linear, Monday, and Asana Alternative.";
				homepage = "https://plane.so";
				license = lib.licenses.agpl3Only;
				platforms = lib.platforms.all;
			};

			passthru = {
				inherit workspace apiserver src;
			};
		}
		''
			mkdir -p $out/bin

			makeWrapper ${workspace.admin}/bin/serve $out/bin/admin
			makeWrapper ${workspace.space}/bin/serve $out/bin/space
			makeWrapper ${workspace.web}/bin/serve $out/bin/web

			makeWrapper ${apiserver}/bin/python $out/bin/apiserver \
				--chdir "${src}/apiserver" \
				--add-flags "${src}/apiserver/manage.py"

			mkdir -p $out/libexec

			ln -s ${src} $out/libexec/plane
		'';
in
	plane
