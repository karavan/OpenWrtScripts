# Building the .apk

This builds a real, installable `luci-app-router-label-<version>.apk` using
the official OpenWrt SDK, via Docker — no toolchain compilation, no full
OpenWrt source checkout. Verified end-to-end: built, installed with `apk
add` on a real router, and confirmed `apk` correctly owns all 5 package
files (the loose-file deploy process in the main README is unrelated and
still works independently, for quick iteration without rebuilding a
package each time).

## One-time setup

Requires Docker Desktop running.

```bash
docker pull openwrt/sdk:ath79-generic-25.12.5
```

This tag matches the test router exactly (`ath79/generic` target, OpenWrt
25.12.5) — see the note at the bottom on picking a different tag. The
image is large (~2GB uncompressed).

The image declares `/builder` (the SDK's whole working directory --
feeds, toolchain, `staging_dir`, `build_dir`) as a Docker **volume**. This
matters: `docker commit` and similar tricks silently exclude volume data,
so the only reliable way to keep this state across container
recreations is a real Docker volume, not a bind mount to some host
directory you pick yourself:

```bash
docker volume create openwrt-router-label-builder
```

`bin/` (the actual build *output* -- the `.apk` files you want) is
different: bind-mount that to a real directory on your Mac so it's
directly accessible without `docker cp`:

```bash
mkdir -p ~/openwrt-sdk-build/bin
```

Start a long-lived container with the named volume as `/builder`, this
repo's package directory bind-mounted in (read-only -- the build never
needs to write into the source tree), and `bin/` bind-mounted to the
directory above:

```bash
docker run -d --name openwrt-router-label-build \
  -v openwrt-router-label-builder:/builder \
  -v /Users/richb/github/OpenWrtScripts/luci-app-router-label:/builder/package/luci-app-router-label:ro \
  -v ~/openwrt-sdk-build/bin:/builder/bin \
  openwrt/sdk:ath79-generic-25.12.5 sleep infinity
```

Set up feeds (downloads several git repos — takes a few minutes):

```bash
docker exec openwrt-router-label-build sh -c './scripts/feeds update -a'
docker exec openwrt-router-label-build sh -c './scripts/feeds install -a -p luci'
docker exec openwrt-router-label-build sh -c 'make defconfig'
```

Enable the package in `.config` (module/separate package, not built into
a firmware image — `=m`, not `=y`):

```bash
docker exec openwrt-router-label-build sh -c '
  grep -q CONFIG_PACKAGE_luci-app-router-label .config \
    || echo "CONFIG_PACKAGE_luci-app-router-label=m" >> .config
'
```

## Every time you make changes

The container stays running between sessions (`docker start
openwrt-router-label-build` if it's stopped). Since the package directory
is bind-mounted live, edits to any file under `luci-app-router-label/`
(view.js, Makefile, menu.d/acl.d json, etc.) are visible inside the
container immediately — no need to re-copy anything.

If you bump `PKG_VERSION`/`PKG_RELEASE` in the `Makefile`, remember to
also update `APP_VERSION` in
`htdocs/luci-static/resources/view/routerlabel.js` (kept in sync by hand,
not derived automatically — see the comment there for why).

```bash
docker start openwrt-router-label-build   # if not already running
docker exec openwrt-router-label-build sh -c 'make package/luci-app-router-label/clean'
docker exec openwrt-router-label-build sh -c 'make package/luci-app-router-label/compile V=s'
```

The `.apk` lands in `~/openwrt-sdk-build/bin/packages/mips_24kc/base/`
(that directory is bind-mounted, so it's directly accessible on your Mac,
not just inside the container). Old-version `.apk` files aren't
auto-removed — delete stale ones so you don't accidentally install the
wrong version:

```bash
ls ~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-router-label*.apk
```

## Installing on a router

```bash
APK=~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-router-label-<version>.apk
scp -O "$APK" root@<router>:/tmp/
ssh root@<router> apk add --allow-untrusted /tmp/$(basename "$APK")
ssh root@<router> rm -f /tmp/luci-indexcache*
ssh root@<router> /etc/init.d/rpcd restart
```

`--allow-untrusted` is needed because this `.apk` isn't signed with a key
the router trusts (it would need to come from a real package repository
for that) — fine for a locally-built test package.

If the router already has the loose-file version deployed (from the main
README's quick-iteration path), remove those first so there's no
ambiguity between package-managed and stray files:

```bash
ssh root@<router> '
  rm -f /www/luci-static/resources/routerlabel.js
  rm -f /www/luci-static/resources/view/routerlabel.js
  rm -f /usr/share/luci/menu.d/luci-app-router-label.json
  rm -f /usr/share/rpcd/acl.d/luci-app-router-label.json
'
```

To upgrade to a newer build later: `apk add --allow-untrusted
/tmp/luci-app-router-label-<new-version>.apk` again — `apk` handles the
upgrade in place. To remove entirely: `apk del luci-app-router-label`.

## Cleaning up

```bash
docker stop openwrt-router-label-build     # pause; the named volume (feeds,
                                            # staging_dir, build_dir) and
                                            # ~/openwrt-sdk-build/bin both
                                            # survive regardless

docker rm openwrt-router-label-build       # also fine -- the named volume
                                            # (openwrt-router-label-builder)
                                            # is a separate Docker object,
                                            # untouched by removing the
                                            # container. Recreate the
                                            # container later with the same
                                            # `docker run` command above and
                                            # everything (feeds, .config,
                                            # toolchain) is right where you
                                            # left it -- no need to redo
                                            # feeds update/install/defconfig.
```

To actually discard the SDK state and start over: `docker volume rm
openwrt-router-label-builder` (only after removing the container that's
using it).

## Picking a different SDK target/version

The `.apk` itself is `noarch` (LuCI apps are just JSON/JS files, no
compiled code) so the SDK target doesn't affect what the package can run
on — `ath79-generic-25.12.5` was chosen only because it matches this
project's actual test router, guaranteeing the SDK's packaging tooling
(apk format, menu.d/acl.d conventions) behaves identically to the real
target. Available tags: <https://hub.docker.com/r/openwrt/sdk/tags>.
