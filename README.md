# srcKit

A Docker image (Ubuntu 26.04, linux/amd64 and linux/arm64) with the srcML
toolchain built from source:

- [srcML](https://github.com/srcML/srcML): `srcml`
- [srcSlice](https://github.com/srcML/srcSlice): `srcslice`
- [srcDiff](https://github.com/srcDiff/srcDiff): `srcdiff`

Each tool is built at a pinned upstream commit in throwaway build stages.
The published image holds only the binaries and their runtime libraries,
plus `jq` for working with srcSlice's JSON.

## Using the image

```sh
docker run --rm -v "$PWD:/work" -w /work <user>/srckit srcml foo.cpp -o foo.xml
docker run --rm -v "$PWD:/work" -w /work <user>/srckit srcdiff old.cpp new.cpp
```

srcSlice needs srcML input with positions and hashes:

```sh
srcml --position --hash foo.cpp -o foo.xml
srcslice foo.xml | jq .
```

The image runs as root by default. Add `--user "$(id -u):$(id -g)"` so files
written to a bind mount belong to you. On SELinux hosts, add `:z` to the
mount (`-v "$PWD:/work:z"`).

`/usr/local/share/srckit/versions` records the exact commit each tool was built
from and which srcKit patches were applied:

```sh
docker run --rm <user>/srckit cat /usr/local/share/srckit/versions
```

## Local development

`compose.yaml` builds the image from this repo as `srckit:local` and mounts the
repo at `/work`. Containers run as uid/gid 1000; set `SRCKIT_UID` and
`SRCKIT_GID` if yours differ.

```sh
docker compose build                              # build srckit:local
docker compose run --rm srckit tests/run.sh       # smoke test
docker compose run --rm srckit srcml --version    # run any tool
docker compose run --rm srckit                    # shell
docker compose run --rm srckit-hub srcml --version   # the published image (SRCKIT_IMAGE overrides the name)
```

There is also a devcontainer (`.devcontainer/`) built on the same Compose
service. Open the repo in VS Code and run **Reopen in Container**, or use
`devcontainer up --workspace-folder .`. The image has no git, so do git
work on the host.

Building the `test` target runs the smoke test as part of the build. This is
the same gate CI uses:

```sh
docker buildx build --target test .
```

## Choosing upstream versions

Repos and refs are `ARG`s at the top of the [Dockerfile](Dockerfile):

| Arg | Default |
|---|---|
| `SRCML_REPO` / `SRCML_REF` | `srcML/srcML` at a pinned `develop` commit |
| `SRCSLICE_REPO` / `SRCSLICE_REF` | `srcML/srcSlice` at a pinned `develop` commit |
| `SRCDIFF_REPO` / `SRCDIFF_REF` | `srcDiff/srcDiff` at a pinned `develop` commit |

A ref can be a full commit SHA, a tag or a branch name. Override one for a
single build:

```sh
docker buildx build --build-arg SRCDIFF_REF=develop -t srckit:local .
```

To move the pins to the current branch heads:

1. Run `scripts/bump-refs.sh`, or `scripts/bump-refs.sh srcdiff` for just one
   tool. It prints a GitHub compare link for each change. It follows `develop`
   by default; set e.g. `SRCSLICE_BRANCH=main` to follow another branch.
2. Rebuild with `docker compose build`.
3. Regenerate the expected outputs with
   `docker compose run --rm srckit tests/run.sh --update`.
4. Review `git diff`. Changed expected output means upstream changed
   behaviour, so check that it makes sense, then commit.

## Patches

`patches/<tool>/*.patch` are applied to that tool's source tree, in name order,
before building. `patches/srcsax/` is applied to the srcSAX copy vendored in
both srcSlice (`srcDispatch/srcSAX`) and srcDiff (`src/srcSAX`).

| Patch | Why |
|---|---|
| `srcsax/0001-use-xmlNewIOInputStream.patch` | srcSAX uses a private copy of a libxml2 struct whose layout changed in libxml2 2.14 (26.04 has 2.15). Without the patch, AddressSanitizer reports a heap overflow when srcSAX parses. Ported from srcML's own copy of the file. |

To add a patch:

1. Check out the same commit locally.
2. Make the change and run `git diff > patches/<tool>/NNNN-description.patch`.
   For files inside a submodule, run `git diff` inside the submodule.
3. Put a short "why" at the top of the file. Text before the first `diff` line
   is ignored.

A patch that no longer applies, or that upstream has already merged, fails the
build. When that happens, update or delete the patch.

## Smoke test

[tests/run.sh](tests/run.sh) uses the tools on `PATH` and works on
[tests/fixtures](tests/fixtures), where `v2` is `v1` with a small edit. It
checks that all shared libraries resolve and compares each output with
[tests/expected](tests/expected):

| Expected file | Command |
|---|---|
| `srcml.xml` | `srcml v1/example.cpp` |
| `srcslice.json` | `srcml --position --hash v1/example.cpp`, then `srcslice`, then `jq -S .` |
| `srcdiff.xml` | `srcdiff v1/example.cpp v2/example.cpp` |
| `srcdiff-unified.txt` | `srcdiff -u v1/example.cpp v2/example.cpp` |

Any output on stderr also fails a check, because srcDiff reports errors there
but exits 0. To add a case, add a `check <expected-file> <command>` line and
run `tests/run.sh --update`.

## CI and publishing

[.github/workflows/build.yml](.github/workflows/build.yml) builds both
architectures on native GitHub runners and runs the smoke test on every push
to `mainline` or `develop` and on every pull request. These runs never
publish.

To publish, go to **Actions → Build → Run workflow**. You can:

- override any of the three refs (a branch is resolved to a commit once, so
  both architectures get the same code),
- choose the tag (default `latest`; a `sha-<commit>` tag is always added),
- untick **publish** for a test-only run.

The workflow pushes a multi-arch image to `<DOCKERHUB_USERNAME>/srckit`.

One-time setup, under **Settings → Secrets and variables → Actions**:

- **Variable** `DOCKERHUB_USERNAME`: your Docker Hub user or organization.
  This is a variable rather than a secret so the image name isn't masked in
  logs.
- **Secret** `DOCKERHUB_TOKEN`: a Docker Hub access token with Read & Write
  scope.

The CI job summary lists the versions file for each architecture.

## Build notes

These are the non-obvious things the Dockerfile works around:

- **srcML:**
  - libsrcml is linked with upstream's version script
    (`src/libsrcml/libsrcml.version`). Without it, libsrcml exports its
    internal srcSAX symbols. srcDiff then binds to those instead of its own
    copy, and `srcdiff -u` / `-y` segfault.
  - Configure downloads ANTLR 2.7.7 and a few other dependencies, so builds
    need network access.
- **srcDiff:**
  - Only the `SRCDIFF` install component is installed; a full install
    replaces srcML's man page with an empty file.
  - `CPACK_OUTPUT_FILE_PREFIX` must be set, because configure fails without
    it (upstream normally sets it in its presets).
- **srcSlice:** it doesn't link libsrcml, so it builds in parallel with
  srcML. Only the `srcslice` target is built; the default target also builds
  srcDispatch's Boost tests.
- **Ubuntu version:** the runtime package names (`libxml2-16`,
  `libarchive13t64`, …) are specific to Ubuntu 26.04. Check them if you
  change `UBUNTU_VERSION`.
