{ lib, pkgs, inputs }:

let
  inherit (pkgs.yarn2nix-moretea) mkYarnWorkspace;

	mach-nix = import inputs.mach-nix {
		inherit pkgs;
		python = "python310";
		pypiData = "${inputs.pypi-deps-db}";
	};

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
				'';
      };

      space = {
				doDist = false;

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
				'';
      };

      web = {
				doDist = false;

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
				'';
      };
    };
  };

	jsonmodels = pkgs.python3.pkgs.buildPythonPackage rec {
		pname = "jsonmodels";
		version = "2.7.0";
		format = "setuptools";

		src = pkgs.fetchPypi {
			inherit pname version;
			hash = "sha256-jAGb8b0lKsPkARJ1B9c16g/WzjCSGAK1/Fx2HNQaGLs=";
		};

		dependencies = with pkgs.python3.pkgs; [
			jinja2
			markupsafe
			pygments
			sphinx
			coverage
			docutils
			flake8
			invoke
			importlib-metadata
			mccabe
			pep8
			py
			pyflakes
			pytest-cov
			sphinxcontrib-spelling
			tox
			virtualenv
			wheel
		];
	};

	apiserverPython = pkgs.python3.withPackages (ps: with ps; [
		django
		djangorestframework
		psycopg
		dj-database-url
		redis
		django-redis
		django-cors-headers
		celery
		django-celery-beat
		whitenoise
		faker
		django-filter
		jsonmodels
		sentry-sdk
		django-storages
		# django-crum
		uvicorn
		channels
		openai
		# slacksdk
		# scout-apm
		openpyxl
		python-json-logger
		beautifulsoup4
		posthog
		cryptography
		lxml
		boto3
		# zxvbn
		pytz
		pyjwt
	]);

	apiserver = mach-nix.buildPythonApplication {
		pname = "plane-apiserver";
		version = "v0.22-dev";

		src = "${src}/apiserver";

		patches = [
			./runtime-dir.patch
		];

		python = "python310";

		format = "other";

		nativeBuildInputs = [
			pkgs.makeWrapper
		];

		setuptoolsBuildPhase = "";

		installPhase = ''
			rm -rf bin

			mkdir -p $out/libexec/$pname

			cp -r ./* $out/libexec/$pname/

			mkdir -p $out/bin

			makeWrapper ${pkgs.python310}/bin/python $out/bin/apiserver \
				--set PYTHONPATH "$PYTHONPATH" \
				--add-flags "$out/libexec/$pname/manage.py"

			# cp ${./apiserver.sh} $out/bin/apiserver
			#
			# substituteInPlace $out/bin/apiserver \
			# 	--replace "python" $(${pkgs.which}/bin/which python) \
			# 	--replace "file" $out/libexec/$pname/manage.py
			#
			# chmod +x $out/bin/apiserver
		'';

		_.psycopg-c.nativeBuildInputs.add = [
			pkgs.postgresql_15
		];

		requirements = ''
			gunicorn
			# django
			Django
			# rest framework
			djangorestframework
			# postgres 
			psycopg
			psycopg-binary
			psycopg-c
			dj-database-url
			# redis
			redis
			django-redis
			# cors
			django-cors-headers
			# celery
			celery
			django_celery_beat
			# file serve
			whitenoise
			# fake data
			faker
			# filters
			django-filter
			# json model
			jsonmodels
			# sentry
			sentry-sdk
			# storage
			django-storages
			# user management
			django-crum
			# web server
			uvicorn
			# sockets
			channels
			# ai
			openai
			# slack
			slack-sdk
			# apm
			scout-apm
			# xlsx generation
			openpyxl
			# logging
			python-json-logger
			# html parser
			beautifulsoup4
			# analytics
			posthog
			# crypto
			cryptography
			# html validator
			lxml
			# s3
			boto3
			# password validator
			zxcvbn
			# timezone
			pytz
			# jwt
			PyJWT
		'';
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
				inherit workspace;
			};
		}
		''
			mkdir -p $out/bin

			makeWrapper ${workspace.admin}/bin/serve $out/bin/admin
			makeWrapper ${workspace.space}/bin/serve $out/bin/space
			makeWrapper ${workspace.web}/bin/serve $out/bin/web

			mkdir -p $out/libexec

			ln -s ${apiserver}/libexec/${apiserver.pname} $out/libexec/apiserver
		'';
in
	(builtins.trace (builtins.attrNames workspace))
apiserver
