# Language cache integration

Supported inventory markers are Cargo manifests/targets, Python and uv metadata, Conda/venv directories, Bundler metadata, and Go module/cache locations inside authorized roots. Project configuration, Python/Ruby imports, build scripts, and network access are never evaluated.

Virtual environments, Conda environments, installed toolchains, and local Bundler paths are permanently report-only. Cargo targets and download caches also remain read-only until exact owners and producer leases exist. Broad `go clean -modcache`, Cargo cleanup, environment deletion, and arbitrary cache roots are unavailable.
