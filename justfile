import 'plugin-dev/release.just'

# Release gate consumed by the `release` recipe (plugin-dev/release.just).
# Fails fast on plugin.json/marketplace.json version drift, then runs the
# full bats suite.
precommit:
    make check-version
    make test
