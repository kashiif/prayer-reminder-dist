# Dist repo tooling.
#
# `make manifest` regenerates adhans.json from the adhan files under
# downloads/adhans and the reminder tones under downloads/reminders. Run it after
# adding, removing, or relabelling an adhan or reminder.

.PHONY: manifest

manifest:
	@bash scripts/generate-manifest.sh
