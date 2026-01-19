# Tips and Workflow

- Start with a minimal set of modules (e.g. `base`, `shell`) and validate the loader before porting complex services.
- Use attribute name conventions (`nixos.<group>`, `homeManager.<group>`) to keep the tree discoverable.
- Document host-specific quirks inside their `hostConfig` record so modules remain generic.
- Keep secrets and credentials in SOPS or similar, and surface only references through metadata.
- Run linters (`statix`, `deadnix`) before committing to catch common issues early.
