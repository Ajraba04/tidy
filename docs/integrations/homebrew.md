# Homebrew integration

Known Homebrew cache and Cellar locations are inventoried only when they are inside an authorized scan root. Allocation reads are bounded and no auto-update environment or ambient executable lookup is used.

No Homebrew parser/tool version is accepted for mutation. `brew cleanup`, uninstall, autoremove, update, and network operations are forbidden. Unsupported installations remain visible inventory with unknown ownership and no effect specification.
