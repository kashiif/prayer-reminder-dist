# Dist repo tooling.
#
# `make manifest` regenerates adhans.json from the adhan files under
# downloads/adhans. Run it after adding, removing, or relabelling an adhan.

.PHONY: manifest

manifest:
	@bash scripts/generate-manifest.sh
