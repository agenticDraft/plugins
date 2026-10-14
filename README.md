# agenticDraft/plugins — Claude Code plugins

A Claude Code plugin marketplace with eight plugins: a delivery route that takes a work item from a tracker to a pull request (`agentic-core` and five packs), and two small behaviour plugins (`no-hallucinations`, `made-decision`).

**Start here:** [`plugins/README.md`](plugins/README.md) describes the whole project: the problem, the plugins, the route, what it looks like and its limits. To use the delivery route in a project, follow [`plugins/getting-started.md`](plugins/getting-started.md). To install one plugin, add the marketplace and pick it:

```text
/plugin marketplace add agenticDraft/plugins
/plugin install <plugin>@agenticdraft
```

Each plugin has its own README under [`plugins/`](plugins/). [`example-project/`](example-project/) shows a per-project install through a committed `.claude/settings.json`.

## Develop

```bash
git clone git@github.com:agenticDraft/plugins.git
cd plugins

# validate the catalog and every plugin it points to
claude plugin validate .

# validate one plugin (--strict turns unknown-field warnings into errors)
claude plugin validate ./plugins/<plugin-name> --strict

# try a plugin without installing it
claude --plugin-dir ./plugins/<plugin-name> -p "/<plugin-name>:<skill-name> <test prompt>"

# install from the local checkout
/plugin marketplace add ./
/plugin install <plugin-name>@agenticdraft
```

Run every test the repository ships, and the version rule CI applies to a pull request:

```bash
(cd plugins/agentic-core/shared/runner && npm ci)   # once; the runner's tests need it
bash scripts/run-tests.sh                           # every *.test.sh and *.test.mjs; prints files=<n> fail=<n>
bash scripts/check-plugin-versions.sh origin/main   # a changed plugin must carry a new version
```

Adding a plugin: create `plugins/<name>/.claude-plugin/plugin.json` and `plugins/<name>/skills/<skill>/SKILL.md`, add an entry to `.claude-plugin/marketplace.json`, then run both validate commands. [`CLAUDE.md`](CLAUDE.md) lists the details and the known gotchas.

## Layout

```text
.claude-plugin/marketplace.json          # the catalog, one entry per plugin
plugins/
├── no-hallucinations/                   # always-on truthfulness rules (hooks + skill)
├── made-decision/                       # on-demand OOCEMR decision interview (skill + evals)
├── agentic-core/                        # delivery route driver and its checks
├── agentic-eds/                         # Edge Delivery platform pack (its `core` link points at agentic-core/shared)
├── agentic-jira/  agentic-github/       # tracker and SCM provider packs
└── agentic-figma/ agentic-playwright/   # design and browser provider packs
scripts/                                 # run-tests.sh, check-plugin-versions.sh and the test for it
.github/workflows/                       # one validate workflow per plugin group, plus the version check
plugins/README.md                        # the whole project, described
plugins/getting-started.md              # a new project's settings.json, install and first route run
example-project/                         # per-project install via committed .claude/settings.json
```

## License

MIT — see [LICENSE](LICENSE).

---

Zoran Markovic · [linkedin.com/in/zoranzokimarkovic](https://www.linkedin.com/in/zoranzokimarkovic/)

Source: [github.com/agenticDraft/plugins](https://github.com/agenticDraft/plugins)
