# example-project

A sample consumer project that enables the **no-hallucinations** plugin for *this project only* —
no global install, nothing in your `~/.claude/`.

```text
example-project/
└── .claude/settings.json    # marketplace + plugin, scoped to this directory
```

## How it works

`.claude/settings.json` declares two things:

```jsonc
{
  "extraKnownMarketplaces": {
    "agenticdraft": {                                    // ① register the catalog
      "source": { "source": "github", "repo": "agenticDraft/plugins" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "no-hallucinations@agenticdraft": true               // ② turn the plugin on
  }
}
```

The key in `extraKnownMarketplaces` (①) and the part after `@` in `enabledPlugins` (②) must be
the same string, and it must match the `name` field in the marketplace's `marketplace.json`.
If they don't match, the plugin silently fails to resolve.

Open this directory in Claude Code, trust the folder when prompted, and the plugin installs
itself. Because these settings are committed, every teammate who opens the repo gets the same
setup.

## Verify it's working

- `/plugin` — `no-hallucinations` should be listed as enabled.
- `/context` — the rules injected by the plugin's `SessionStart` hook are part of the session.
- `/no-hallucinations:be-honest` — prints the rules on demand.
- `claude --debug` — shows whether the hook fired and what it printed.

## Manual install instead

If you'd rather not commit settings:

```bash
/plugin marketplace add agenticDraft/plugins
/plugin install no-hallucinations@agenticdraft
```

`enabledPlugins` then controls on/off per project, and `/plugin disable no-hallucinations`
turns it off everywhere.
