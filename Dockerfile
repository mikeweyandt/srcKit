# syntax=docker/dockerfile:1

# Ubuntu release for both the build and runtime stages. The runtime package
# names in the `runtime` stage (libxml2-16, *t64) are specific to 26.04.
ARG UBUNTU_VERSION=26.04

# Upstream sources. *_REPO must be an https URL ending in .git.
# *_REF may be a full 40-character commit SHA (pinned default), a tag, or a
# branch name. It must never be empty. Bump the pins with scripts/bump-refs.sh.
ARG SRCML_REPO=https://github.com/srcML/srcML.git
ARG SRCML_REF=d382719161daa1d035b594fcd3639ff376b4bb83
ARG SRCSLICE_REPO=https://github.com/srcML/srcSlice.git
ARG SRCSLICE_REF=c69e9ead2691690ecc71c25dd0a8ba56bf8fad4a
ARG SRCDIFF_REPO=https://github.com/srcDiff/srcDiff.git
ARG SRCDIFF_REF=ce582975fc3c0e22348a2254df9bfd2503b39630

# --------------------------------------------------------------------------
# Toolchain shared by all build stages. Every build stage stages what the
# runtime image needs under /out/<tool>/, which `runtime` copies to /.
FROM ubuntu:${UBUNTU_VERSION} AS build-base
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        g++ cmake ninja-build git ca-certificates patch \
        libxml2-dev libxslt1-dev libarchive-dev libcurl4-openssl-dev libxcb1-dev \
        libboost-dev default-jre-headless \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/apply-patches.sh /usr/local/bin/apply-patches
COPY scripts/record-version.sh /usr/local/bin/record-version

# --------------------------------------------------------------------------
# srcML: installed into /usr/local here so srcDiff can find_package(srcML).
# The version script (as in upstream's GCC presets) limits libsrcml's exports
# to the public srcml_* API. Without it libsrcml also exports its internal
# srcSAX symbols, which override srcDiff's own srcSAX at link time and crash
# `srcdiff -u` / `-y`.
FROM build-base AS srcml
ARG SRCML_REPO
ARG SRCML_REF
ADD --keep-git-dir=true ${SRCML_REPO}#${SRCML_REF} /src/srcml
COPY patches/srcml/ /patches/srcml/
WORKDIR /src/srcml
RUN : "${SRCML_REF:?must not be empty}" \
 && apply-patches /patches/srcml . \
 && cmake -S . -B /tmp/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_CLIENT_TESTS=OFF \
        -DSRCML_CLIENT_STATIC_LIBXCB=ON \
        -DSRCML_LIBSRCML_LINK_FLAGS=-Wl,--version-script=/src/srcml/src/libsrcml/libsrcml.version \
 && cmake --build /tmp/build \
 && cmake --install /tmp/build \
 && mkdir -p /out/srcml/usr/local/bin /out/srcml/usr/local/lib \
 && cp -a /usr/local/bin/srcml /out/srcml/usr/local/bin/ \
 && cp -a /usr/local/lib/libsrcml.so.1* /out/srcml/usr/local/lib/ \
 && record-version srcml "$SRCML_REPO" /out/srcml /patches/srcml \
 && rm -rf /tmp/build

# --------------------------------------------------------------------------
# srcSlice: reads srcML through its vendored srcSAX; does not link libsrcml,
# so it builds in parallel with srcML.
FROM build-base AS srcslice
ARG SRCSLICE_REPO
ARG SRCSLICE_REF
ADD --keep-git-dir=true ${SRCSLICE_REPO}#${SRCSLICE_REF} /src/srcslice
COPY patches/srcslice/ /patches/srcslice/
COPY patches/srcsax/ /patches/srcsax/
WORKDIR /src/srcslice
RUN : "${SRCSLICE_REF:?must not be empty}" \
 && apply-patches /patches/srcslice . \
 && apply-patches /patches/srcsax srcDispatch/srcSAX \
 && cmake -S . -B /tmp/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTS=OFF \
 && cmake --build /tmp/build --target srcslice \
 && install -D -m 755 /tmp/build/bin/srcslice /out/srcslice/usr/local/bin/srcslice \
 && record-version srcslice "$SRCSLICE_REPO" /out/srcslice /patches/srcslice /patches/srcsax \
 && rm -rf /tmp/build

# --------------------------------------------------------------------------
# srcDiff: links libsrcml. Install only the SRCDIFF component; a full install
# would overwrite srcML's man page with an empty file. CPACK_OUTPUT_FILE_PREFIX
# is normally set by srcDiff's presets; configure fails without it.
FROM srcml AS srcdiff
ARG SRCDIFF_REPO
ARG SRCDIFF_REF
ADD --keep-git-dir=true ${SRCDIFF_REPO}#${SRCDIFF_REF} /src/srcdiff
COPY patches/srcdiff/ /patches/srcdiff/
COPY patches/srcsax/ /patches/srcsax/
WORKDIR /src/srcdiff
RUN : "${SRCDIFF_REF:?must not be empty}" \
 && apply-patches /patches/srcdiff . \
 && apply-patches /patches/srcsax src/srcSAX \
 && cmake -S . -B /tmp/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_CLIENT_TESTS=OFF \
        -DBUILD_DELTA_TESTS=OFF \
        -DCPACK_OUTPUT_FILE_PREFIX=dist \
 && cmake --build /tmp/build --target srcdiff \
 && cmake --install /tmp/build --component SRCDIFF --prefix /out/srcdiff/usr/local \
 && record-version srcdiff "$SRCDIFF_REPO" /out/srcdiff /patches/srcdiff /patches/srcsax \
 && rm -rf /tmp/build

# --------------------------------------------------------------------------
# The published image: the three tools plus their runtime libraries.
FROM ubuntu:${UBUNTU_VERSION} AS runtime
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        libxml2-16 libxslt1.1 libarchive13t64 libcurl4t64 ca-certificates jq \
 && rm -rf /var/lib/apt/lists/*
COPY --link --from=srcml /out/srcml/ /
COPY --link --from=srcslice /out/srcslice/ /
COPY --link --from=srcdiff /out/srcdiff/ /
RUN ldconfig \
 && cat /usr/local/share/srckit/versions.d/* > /usr/local/share/srckit/versions
ENV LANG=C.UTF-8
# Declared here, not at the top of the stage, so changing a ref doesn't
# invalidate the apt layer.
ARG SRCML_REF
ARG SRCSLICE_REF
ARG SRCDIFF_REF
LABEL org.opencontainers.image.title="srcKit" \
      org.opencontainers.image.description="srcML, srcSlice and srcDiff on Ubuntu" \
      org.opencontainers.image.source="https://github.com/mikeweyandt/srcKit" \
      io.github.mikeweyandt.srckit.srcml.ref="${SRCML_REF}" \
      io.github.mikeweyandt.srckit.srcslice.ref="${SRCSLICE_REF}" \
      io.github.mikeweyandt.srckit.srcdiff.ref="${SRCDIFF_REF}"
WORKDIR /work
CMD ["bash"]

# --------------------------------------------------------------------------
# Smoke test against known-good output. `--target test` fails if any check
# fails and exports the versions file (CI writes it to the job summary).
FROM runtime AS test-run
COPY tests/ /work/tests/
RUN tests/run.sh

FROM scratch AS test
COPY --from=test-run /usr/local/share/srckit/versions /versions

# --------------------------------------------------------------------------
# Default target: the runtime image.
FROM runtime
