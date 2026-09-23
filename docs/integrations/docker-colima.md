# Docker and Colima integration

Only explicit `unix:///absolute/path` endpoint syntax can proceed to identity checks. SSH, TCP, newline/NUL input, symbolic-link sockets, non-sockets, unapproved identities, and replaced sockets are denied before a client call. Ambient `DOCKER_HOST`, contexts, and daemon startup are never consulted.

The supported fixture parser is bounded JSON (`fixture-json-v1`) for exact image/container IDs, state, reference count, and writable-data warning. Exact intended argv is `--host <approved-endpoint> image rm <64-hex-id>` for an unreferenced image, or `--host <approved-endpoint> container rm <64-hex-id>` for a stopped container after explicit data-loss acknowledgement. Force, prune, volumes, build-cache bulk removal, and VM disk deletion are forbidden. Process dispatch is not registered, so all effect specifications remain unavailable.
