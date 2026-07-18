# luci-app-router-label — Design

## Purpose

`print-router-label.sh` (and the copy embedded in `config-spare-router.sh`)
generates a printable text label from an OpenWrt router's live state:
device model, flash/RAM size, OpenWrt version, hostname/LAN address,
root password (passed in as an argument — not derivable from `uci`), and
Wifi SSID/password. It's meant to be printed and taped to the router.

This project ports that same data and layout into a LuCI web GUI page, so
the label can be viewed/filled-in through the browser instead of SSH.

## Scope decision: loose files first, real package later

Deliverable is a small set of plain files that get copied directly onto a
router's filesystem for testing — no OpenWrt SDK/buildroot required. This
matches how the rest of this repo's scripts are used ("copy onto the
router and run it").

This is intentionally structured as a stepping stone: the file layout
below (`luasrc/`, `htdocs/`) mirrors what a real `.ipk`/`.apk` package
would contain. Turning this into an installable package later is adding a
`Makefile` + `ipkg-*.control` file that point the SDK at these same
files — the Lua controller and JS view content do not change.

## File layout

```
luci-app-router-label/
├── luasrc/controller/routerlabel.lua
├── htdocs/luci-static/resources/view/routerlabel.js
└── README.md   # how to copy these onto a router for testing
```

## Architecture

- **Controller** (`routerlabel.lua`): registers a LuCI menu entry under
  **System → Router Label**, plus a JSON leaf endpoint
  (`admin/system/routerlabel/data`). Both are behind LuCI's normal admin
  session login — no separate ACL/rpcd grant is needed, since this uses a
  standard controller `call()` action rather than a raw ubus RPC.
- **View** (`routerlabel.js`): a LuCI JS view that fetches the JSON
  endpoint on load and renders the fields as a LuCI-styled table (native
  LuCI form/table CSS, not a `<pre>` block).

## Data flow

1. User opens **System → Router Label**.
2. The JS view calls the controller's JSON endpoint.
3. The Lua controller action re-implements the shell script's logic
   natively in Lua (not by shelling out to the `.sh` file):
   - `luci.model.uci` for `system.@system[0].hostname`,
     `network.lan.ipaddr`, `dhcp.@dnsmasq[0].domain`, and iterating
     `wireless` `wifi-iface` sections.
   - File reads / `luci.sys.exec` for `/tmp/sysinfo/model`, `/proc/mtd`,
     `/proc/meminfo`, `/etc/openwrt_release`.
   - A Lua port of `round_up_to_pow2_mb()` for the Flash/RAM calculation
     (same logic: round each up to the next power-of-two MB).
   - Wifi lookup replicates the script's rule: first **enabled**
     `wifi-iface` section wins; its `ssid`/`key` are used.
   - Returns one JSON object with all fields.
4. The JS view renders a table with the same rows as the script's label
   output: Device, Flash/RAM, OpenWrt, Connect to (`http://host.tld`),
   or (`ssh root@host.tld`), LAN, User (static `root`), Login PW, Wifi
   SSID, Wifi PW, Configured (today's date, computed client-side in JS).
5. **Login PW row**: a password `<input>` above the table. Typing into it
   updates the Login PW table row live via a JS event handler.
   - Nothing is submitted to the server, written to `uci`, or persisted
     to disk anywhere — purely a client-side display binding, mirroring
     the script's behavior where the password is just a runtime argument.
   - Empty field displays `?` in the Login PW row, matching the script's
     default when no password argument is given.

## Field-by-field parity with the script

| Script field  | Source                                              |
|---------------|------------------------------------------------------|
| Device        | `/tmp/sysinfo/model`                                  |
| Flash/RAM     | largest `/proc/mtd` partition + `/proc/meminfo`, both rounded up to next power-of-two MB |
| OpenWrt       | `DISTRIB_DESCRIPTION` from `/etc/openwrt_release`     |
| Connect to / ssh | `system.@system[0].hostname` + `dhcp.@dnsmasq[0].domain` |
| LAN           | `network.lan.ipaddr`                                  |
| User          | static `root`                                         |
| Login PW      | client-side text input, not derivable from `uci`      |
| Wifi SSID/PW  | first enabled `wireless` `wifi-iface` section          |
| Configured    | today's date (script: shell `date`; here: JS `Date`)  |

## Error handling

- Unset/missing `uci` values (e.g. no `dhcp` domain configured) render as
  an empty cell rather than erroring, matching the script's tolerance for
  unset `uci -q get` results.
- No enabled `wifi-iface` found → Wifi SSID/PW both show `unknown`,
  matching the script's fallback branch.
- JSON fetch failure (e.g. expired session) shows LuCI's standard error
  notification rather than a blank/broken page.

## Dev/test workflow (no SDK)

Since this ships as loose files rather than a built package:

1. `scp luasrc/controller/routerlabel.lua root@router:/usr/lib/lua/luci/controller/routerlabel.lua`
2. `scp htdocs/luci-static/resources/view/routerlabel.js root@router:/www/luci-static/resources/view/routerlabel.js`
3. `ssh root@router rm -f /tmp/luci-indexcache*`
4. Reload LuCI in the browser.

This is documented in the app directory's own README.

## Out of scope

- Building an actual `.ipk`/`.apk` package (explicitly deferred — this
  design only needs to make that migration easy, not do it).
- Persisting the root password anywhere.
- A print-specific stylesheet (native LuCI table styling was chosen over
  reproducing the script's monospace-aligned text block).
