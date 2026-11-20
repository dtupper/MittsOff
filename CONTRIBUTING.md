# Contributing

## Running tests

The tests are plain Lua with no dependencies and need Lua 5.2 or later. From the repo root:

```
lua tests/run.lua
```

It prints the pass and fail counts and exits non-zero on failure. The game runs Lua 5.1, so `Rules.lua`, `Core.lua` and `Options.lua` must stay 5.1 compatible. CI checks this with `luac5.1 -p` on every file the TOC loads.

## Builds and releases

Packages are built with [BigWigsMods/packager](https://github.com/BigWigsMods/packager). `.pkgmeta` leaves out `tests`, `README.md`, `CONTRIBUTING.md` and all dotfiles, so the zip holds a single `MittsOff/` folder with the TOC, the Lua files and a generated `CHANGELOG.md`. The `@project-version@` token in the TOC is replaced with the tag name, or with something like `v0.1.0-3-gabc1234` for untagged commits. A plain git checkout shows the raw token as its version in game, which is harmless.

Every push to any branch and every pull request runs the tests, then builds an unstable zip and attaches it to the workflow run as an artifact.

Every push to `main` also refreshes a prerelease called "Unstable build" on the rolling `unstable` tag, with the zip attached as `MittsOff-unstable.zip`. The tag is moved by CI and ignored when the packager works out version names, so do not use it for anything else.

Pushing a tag that starts with `v`, such as `v0.1.0`, runs the tests, builds the release zip and creates a GitHub release with it. A tag containing `alpha` or `beta` is published as a GitHub prerelease. After that the CurseForge job runs. Until it is set up it skips with a notice and the workflow still passes.

## Turning on CurseForge uploads

1. Create the project on CurseForge for the WoW Forever game flavor and note its project ID from the "About Project" box.
2. Create an API token at https://authors.curseforge.com/#/settings/api-tokens.
3. In the GitHub repo, add a repository secret named `CF_API_TOKEN` holding that token (Settings, Secrets and variables, Actions).
4. In `MittsOff.toc`, replace the commented `# ## X-Curse-Project-ID:` line with `## X-Curse-Project-ID: 123456`, using your project ID.

The next `v` tag then uploads to CurseForge as well. If CurseForge rejects the file or files it under the wrong game version, set `CF_GAME_VERSION` in `.github/workflows/release.yml` to the exact game version name CurseForge lists for Forever.
