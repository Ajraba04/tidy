# Local model integration

Ollama, Hugging Face, and MLX stores are inventoried from fixed locations inside authorized roots. Traversal is bounded, follows no symbolic links, and accounts hard-linked/shared blobs once by file identity. It does not start a daemon, hash model contents, download metadata, or contact a registry.

Aliases, blobs, and model stores are permanently inventory-only. No generic filesystem delete effect or model-process control is supplied.
