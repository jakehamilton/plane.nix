{ ... }:

final: prev: {
	python3 = prev.python3.override {
		packageOverrides = self: super: {
			python-crontab = super.python-crontab.overridePythonAttrs (old: {
				# NOTE: This is currently broken in Nixpkgs for Python 3.10+ (have not tested on
				# 3.9 or below due to other incompatibilities).
				doCheck = false;
			});
		};
	};
}
