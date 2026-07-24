# Building the .apk

`build-apk.sh` builds a real, installable `luci-app-router-label-<version>.apk`
in about a second, with no OpenWrt SDK, no feeds, and no toolchain. Verified
against a real SDK-built `.apk`: identical file tree, install/upgrade/remove
scripts, and metadata (see "How it works" below) -- and installed with `apk
add` on a real router.

## Requirements

Docker Desktop running. The script uses a tiny `alpine:3.24` image (~7MB,
pulled automatically on first use) to invoke the real `apk mkpkg`
command -- there's no persistent container or volume to set up.

## Building

```bash
./build-apk.sh
```

**Note:** The packages version is saved in `PKG_VERSION` in the `Makefile`. Bump that version when you make changes.
The `build-apk.sh` script copies that version number into
`htdocs/luci-static/resources/view/routerlabel.js` 

The `.apk` lands in
`~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-router-label-<version>.apk`
(same path the old SDK-based workflow used, kept only for continuity with
the install steps below -- the `mips_24kc` subdirectory name isn't
meaningful anymore since the package is `noarch`). Old-version `.apk` files
aren't auto-removed -- delete stale ones so you don't accidentally install
the wrong version.

## Installing on a router

**Quick path:** `./deploy-apk.sh [user@]router-address` — scp's the
already-built `.apk` and installs it with `apk`, clearing the menu cache
and restarting `rpcd`. The manual
steps below are what it automates.

```bash
APK=~/openwrt-sdk-build/bin/packages/mips_24kc/base/luci-app-router-label-<version>.apk
scp -O "$APK" root@<router>:/tmp/
ssh root@<router> apk add --allow-untrusted /tmp/$(basename "$APK")
ssh root@<router> rm -f /tmp/luci-indexcache*
ssh root@<router> /etc/init.d/rpcd restart
```

`--allow-untrusted` is needed because this `.apk` isn't signed with a key
the router trusts (it would need to come from a real package repository
for that) -- fine for a locally-built test package.

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
/tmp/luci-app-router-label-<new-version>.apk` again -- `apk` handles the
upgrade in place. To remove entirely: `apk del luci-app-router-label`.

## How it works

OpenWrt's current package manager is `apk-tools` v3, and its `.apk` files
are a custom binary format ("ADB", Alpine Dependency Binary) -- not a
zip/tar concatenation like the old `.ipk`/`apk` v2 formats. Hand-writing
that binary format isn't practical, but the OpenWrt SDK doesn't do that
either: for a pure LuCI app (`LUCI_PKGARCH:=all`, no compiled code), the
SDK's build process ultimately just calls `apk mkpkg` on the package's
files, generated control scripts, and metadata. `build-apk.sh` does the
same thing directly:

- Assembles the 4 files this package actually installs (2 `.js`, 2 `.json`)
  into the exact target file tree.
- Generates `lib/apk/packages/luci-app-router-label.list`, a manifest apk
  expects at that fixed path (this is what `luci.mk` generates for every
  `luci-app-*` package).
- Generates the standard `post-install`/`pre-deinstall`/`post-upgrade`
  scripts that `luci.mk` attaches to every `luci-app-*` package (they call
  `add_group_and_user`/`default_postinst`/`default_prerm` from
  `/lib/functions.sh` on the router).
- Reads name/version/license/maintainer/description/depends straight from
  the `Makefile`, so there's one source of truth.
- Runs `apk mkpkg --info ... --script ... --files ... --output ...` inside
  `alpine:3.24` (the first stable Alpine release with `apk-tools` 3.x) and
  writes the resulting `.apk` to the bind-mounted output directory.

Since there's no compiled code and no cross-compilation, none of the SDK's
toolchain, feeds, or `.config` machinery is actually needed -- it exists to
support packages that do compile something.
