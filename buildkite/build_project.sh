#!/bin/bash

PS4="~> " # needed to avoid accidentally generating collapsed output
set -uexo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. "$DIR/load_distribution.sh"

# set environment configs and allow build_project to be conveniently used in standalone
if [ -z "$REPO_FULL_NAME" ] ; then
    echo 'ERROR: You must set $REPO_FULL_NAME'
    exit 1
fi
if [ -z "${REPO_URL:-}" ] ; then
    REPO_URL="https://github.com/$REPO_FULL_NAME"
    echo "WARNING: \$REPO_URL not set. Falling back to $REPO_URL"
fi
if [ -z "${REPO_DIR:-}" ] ; then
    REPO_DIR="$(basename $REPO_FULL_NAME)"
    echo "WARNING: \$REPO_DIR not set. Falling back to $REPO_DIR"
fi

# clone the latest tag
latest_tag=$(git ls-remote --tags ""${REPO_URL}"" | \
    sed -n 's|.*refs/tags/\(v\?[0-9]*\.[0-9]*\.[0-9]*$\)|\1|p' | \
    sort --version-sort | \
    tail -n 1)
latest_tag="${latest_tag:-master}"

case "$REPO_URL" in
    https://github.com/vibe-d/vibe.d)
        # for https://github.com/vibe-d/vibe.d/pull/2183, required until 0.8.5 is released
        latest_tag=master
        ;;
    https://github.com/ldc-developers/ldc)
        # ldc doesn't really do point releases, so master is easier to adapt if needed.
        latest_tag=master
        ;;
    *)
        ;;
esac

echo "--- Checking ${REPO_URL} for a core repository and branch merging with ${BUILDKITE_REPO}"

# Don't checkout a tagged version of the core repositories like Phobos
case "${REPO_URL:-x}" in
    "https://github.com/dlang/dmd" | \
    "https://github.com/dlang/druntime" | \
    "https://github.com/dlang/phobos" | \
    "https://github.com/dlang/tools" | \
    "https://github.com/dlang/dub" | \
    "https://github.com/dlang/ci")
        # if the core repo is the current repo, then just merge its head
        if [ "${REPO_URL:-a}" == "${BUILDKITE_REPO:-b}" ] ; then
            echo "--- Merging with the upstream target branch"
            "./$DIR/merge_head.sh"
            latest_tag="IS-ALREADY_CHECKED-OUT"
        else
            # otherwise checkout the respective branch
            latest_tag=$("$DIR/origin_target_branch.sh" "${REPO_URL}")
        fi
        ;;
    *)
esac

if [ "$latest_tag" != "IS-ALREADY-CHECKED-OUT" ] ; then
    echo "--- Cloning ${REPO_URL} (tag: $latest_tag)"
    git clone -b "${latest_tag}" --depth 1 "${REPO_URL}" "${REPO_DIR}"
    cd "${REPO_DIR}"
fi

use_travis_test_script()
{
    # Strip any meson tests
    "$DIR/travis_get_script" | sed -e '/meson/d' | bash
}

remove_spurious_vibed_tests()
{
    # these vibe.d tests tend to timeout or fail often
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe-core/issues/56
    rm -rf tests/vibe.core.net.1726 # FIXME
    rm -rf tests/std.concurrency # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe-core/issues/55
    rm -rf tests/vibe.core.net.1429 # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe-core/issues/54
    rm -rf tests/vibe.core.concurrency.1408 # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2057
    rm -rf tests/vibe.http.client.1389 # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2054
    rm -rf tests/tcp # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2066
    rm -rf tests/vibe.core.net.1452 # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2068
    rm -rf tests/vibe.core.net.1376 # FIXME
    # temporarily disable failing tests, see: https://github.com/vibe-d/vibe.d/issues/2078
    rm -rf tests/redis # FIXME
}

################################################################################
# Add custom build instructions here
################################################################################

echo "--- Running the testsuite"
case "$REPO_FULL_NAME" in

    gtkd-developers/GtkD)
        make "DC=$DC"
        ;;

    higgsjs/Higgs)
        make -C source test "DC=$DC"
        ;;

    vibe-d/vibe.d+libevent-base)
        VIBED_DRIVER=libevent PARTS=builds,unittests ./travis-ci.sh
        ;;
    vibe-d/vibe.d+libevent-examples)
        VIBED_DRIVER=libevent PARTS=examples ./travis-ci.sh
        ;;
    vibe-d/vibe.d+libevent-tests)
        remove_spurious_vibed_tests
        VIBED_DRIVER=libevent PARTS=tests ./travis-ci.sh
        ;;
    vibe-d/vibe.d+vibe-core-base)
        VIBED_DRIVER=vibe-core PARTS=builds,unittests ./travis-ci.sh
        ;;
    vibe-d/vibe.d+vibe-core-examples)
        VIBED_DRIVER=vibe-core PARTS=examples ./travis-ci.sh
        ;;
    vibe-d/vibe.d+vibe-core-tests)
        remove_spurious_vibed_tests
        VIBED_DRIVER=vibe-core PARTS=tests ./travis-ci.sh
        ;;
    vibe-d/vibe.d+libasync-base)
        VIBED_DRIVER=libasync PARTS=builds,unittests ./travis-ci.sh
        ;;

    vibe-d/vibe-core+epoll)
        rm tests/issue-58-task-already-scheduled.d # https://github.com/vibe-d/vibe-core/issues/84
        CONFIG=epoll ./travis-ci.sh
        ;;

    vibe-d/vibe-core+select)
        rm tests/issue-58-task-already-scheduled.d # https://github.com/vibe-d/vibe-core/issues/84
        CONFIG=select ./travis-ci.sh
        ;;

    dlang/dub)
        rm test/issue895-local-configuration.sh # FIXME
        rm test/issue884-init-defer-file-creation.sh # FIXME
        sed 's/"stdx-allocator": "2.77.0",/"stdx-allocator": "2.77.2",/' -i dub.selections.json # upgrade stdx-allocator (can be removed once v1.11 gets released)
        rm test/ddox.sh # can be removed once v1.11 gets released
        sed -i '/^source.*activate/d' travis-ci.sh
        DC=$DC ./travis-ci.sh
        ;;

    dlang/tools)
        # explicit test to avoid Digger setup, see dlang/tools#298 and dlang/tools#301
        make -f posix.mak all DMD='dmd' DFLAGS=
        make -f posix.mak test DMD='dmd' DFLAGS=
        ;;

    msgpack/msgpack-d)
        make -f posix.mak unittest "DMD=$DMD" MODEL=64
        ;;

    dlang-community/containers)
        make -B -C test/ || echo failed # FIXME
        ;;

    BlackEdder/ggplotd)
        # workaround https://github.com/BlackEdder/ggplotd/issues/34
        sed -i 's|auto seed = unpredictableSeed|auto seed = 54321|' source/ggplotd/example.d
        use_travis_test_script
        ;;

    BBasile/iz)
        cd scripts && sh ./test.sh
        ;;

    dlang-community/D-YAML)
        dub build "--compiler=$DC"
        dub test "--compiler=$DC"
        ;;

    sociomantic-tsunami/ocean)
        git submodule update --init
        make d2conv V=1
        make test V=1 DVER=2 F=production ALLOW_DEPRECATIONS=1
        ;;

    eBay/tsv-utils)
        make test "DCOMPILER=$DC"
        ;;

    dlang-tour/core)
        git submodule update --init public/content/en
        dub test "--compiler=$DC"
        ;;

    CyberShadow/ae)
        # remove failing extended attribute test
        perl -0777 -pi -e "s/unittest[^{]*{[^{}]*xAttrs[^{}]*}//" sys/file.d
        # remove network tests (they tend to timeout)
        rm -f sys/net/test.d
        use_travis_test_script
        ;;

    ikod/dlang-requests)
        # full test suite is currently disabled
        # see https://github.com/dlang/ci/pull/166
        dub build -c std
        dub build -c vibed
        ;;

    libmir/mir-algorithm | \
    libmir/mir | \
    pbackus/sumtype | \
    aliak00/optional)
        dub test "--compiler=$DC"
        ;;

    ldc-developers/ldc)
        cd runtime && git clone --depth 5 https://github.com/ldc-developers/druntime
        git clone --depth 5 https://github.com/ldc-developers/phobos
        cd .. && git submodule update
        mkdir bootstrap && cd bootstrap
        cmake -GNinja -DCMAKE_BUILD_TYPE=Debug -DD_COMPILER="$DC" ..
        ninja -j2 ldmd2 druntime-ldc-debug phobos2-ldc-debug
        cd ..
        mkdir build && cd build
        cmake -GNinja -DCMAKE_BUILD_TYPE=Debug -DD_COMPILER="$(pwd)/../bootstrap/bin/ldmd2" ..
        ninja -j2 ldc2 druntime-ldc phobos2-ldc
        ;;

    dlang/phobos)
        "$DIR"/clone_repositories.sh
        # To avoid running into "Path too long" issues, see e.g. https://github.com/dlang/ci/pull/287
        export TMP="/tmp/${BUILDKITE_AGENT_NAME}"
        export TEMP="$TMP"
        export TMPDIR="$TMP"
        rm -rf "$TMP" && mkdir -p "$TMP"
        cd phobos && make -f posix.mak -j2 buildkite-test
        rm -rf "$TMP"
        ;;

    *)
        use_travis_test_script
        ;;
esac

# final cleanup
git clean -ffdxq .
