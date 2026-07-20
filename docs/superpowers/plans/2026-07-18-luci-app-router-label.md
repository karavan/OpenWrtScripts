# luci-app-router-label Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `print-router-label.sh`'s router-identification label into a LuCI web GUI page (**System → Router Label**), with a client-side-only root-password field, as loose files that can later be wrapped into a real `.ipk`/`.apk` package without changing their content.

**Architecture:** A new `luci-app-router-label/` directory holds a Lua controller (menu entry + JSON data endpoint) and a LuCI JS view (renders the data as a native LuCI table, with a password input that updates one table cell live via JS — nothing is submitted or persisted). The controller's data-parsing logic (flash/RAM sizing, OpenWrt version, wifi selection) lives in a separate pure-Lua module with no OpenWrt/LuCI runtime dependencies, so it can be unit-tested locally with a plain `lua` interpreter — everything else (the controller glue and the JS view) requires a real router and is verified manually.

**Tech Stack:** OpenWrt LuCI (JS-view + Lua controller, current dispatcher style), plain `lua` (5.1-compatible patterns) for local unit tests.

**Reference spec:** `docs/superpowers/specs/2026-07-18-luci-app-router-label-design.md`

---

## Chunk 1: Full Plan

### Task 1: App skeleton + directory README

**Files:**
- Create: `luci-app-router-label/README.md`
- Create (empty dirs via placeholder files created in later tasks — no action needed here beyond the README)

- [ ] **Step 1: Create the app directory and its README**

```bash
mkdir -p luci-app-router-label/luasrc/controller
mkdir -p luci-app-router-label/luasrc/routerlabel
mkdir -p luci-app-router-label/htdocs/luci-static/resources/view
```

Write `luci-app-router-label/README.md`:

````markdown
# luci-app-router-label

Displays the same router-identification "label" that `print-router-label.sh`
(in the repo root) prints to the console, but in the LuCI web GUI under
**System → Router Label**. The root login password isn't derivable from
`uci`, so it's a plain text field on the page — nothing typed there is
saved to disk or sent to the router; it only updates the page you're looking at.

This ships as loose files for now, not a built `.ipk`/`.apk` — see
`docs/superpowers/specs/2026-07-18-luci-app-router-label-design.md` for why,
and how this maps onto a real package later.

## Testing on a router (no SDK/opkg build required)

Copy the files directly onto a router running current OpenWrt. The `scp`
source paths below are relative to this directory (`luci-app-router-label/`),
so `cd` here first.

**Note the `-O` flag on each `scp`:** OpenWrt's default SSH server (Dropbear)
doesn't ship an `sftp-server` binary, and modern `scp` clients (OpenSSH 9.0+,
which is what current macOS ships) default to the SFTP protocol. Without
`-O` you'll hit `ash: /usr/libexec/sftp-server: not found` / `scp: Connection
closed`. `-O` forces the older SCP protocol, which Dropbear does support.

```bash
cd luci-app-router-label   # skip if you're already in this directory
ssh root@<router> mkdir -p /usr/lib/lua/luci/routerlabel
scp -O luasrc/routerlabel/util.lua root@<router>:/usr/lib/lua/luci/routerlabel/util.lua
scp -O luasrc/controller/routerlabel.lua root@<router>:/usr/lib/lua/luci/controller/routerlabel.lua
scp -O htdocs/luci-static/resources/view/routerlabel.js root@<router>:/www/luci-static/resources/view/routerlabel.js
ssh root@<router> rm -f /tmp/luci-indexcache*
```

Then reload LuCI in your browser and look under **System → Router Label**.

## Running the unit tests locally

`luasrc/routerlabel/util.lua` has no OpenWrt/LuCI dependencies and can be
tested with a plain `lua` interpreter — no router needed:

```bash
cd ../tests
lua test_routerlabel_util.lua
```
````

- [ ] **Step 2: Commit**

```bash
git add luci-app-router-label/README.md
git commit -m "Add luci-app-router-label skeleton and README"
```

---

### Task 2: Flash/RAM sizing logic (pure Lua, TDD)

This ports `round_up_to_pow2_mb()` and `get_flash_ram_label()` from the
shell script.

**Files:**
- Create: `luci-app-router-label/luasrc/routerlabel/util.lua`
- Create: `tests/test_routerlabel_util.lua`

- [ ] **Step 1: Write the failing test**

Create `tests/test_routerlabel_util.lua`:

```lua
-- Unit tests for luci-app-router-label's pure-Lua parsing/formatting logic.
-- Run with: lua test_routerlabel_util.lua  (from inside tests/)
-- No OpenWrt/LuCI runtime needed -- these functions take plain strings/tables.

package.path = "../luci-app-router-label/luasrc/?.lua;" .. package.path
local util = require("routerlabel.util")

local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("FAIL %s: expected %s, got %s",
			label, tostring(expected), tostring(actual)))
	end
	print("PASS " .. label)
end

-- round_up_to_pow2_mb
eq(util.round_up_to_pow2_mb(16 * 1024 * 1024), 16, "round exact 16MB")
eq(util.round_up_to_pow2_mb(15 * 1024 * 1024), 16, "round up 15MB -> 16MB")
eq(util.round_up_to_pow2_mb(16 * 1024 * 1024 - 100), 16, "round up just-under-16MB")
eq(util.round_up_to_pow2_mb(128 * 1024 * 1024), 128, "round exact 128MB")

print("All routerlabel.util tests passed.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: FAIL — `module 'routerlabel.util' not found` (the module doesn't exist yet)

- [ ] **Step 3: Write minimal implementation**

Create `luci-app-router-label/luasrc/routerlabel/util.lua`:

```lua
local M = {}

-- Round a byte count up to the next power of two, in whole MB.
-- Rounding up (rather than to nearest) accounts for /proc/mtd and
-- /proc/meminfo reporting slightly less than the nominal hardware size.
function M.round_up_to_pow2_mb(bytes)
	local pow2 = 1
	while pow2 < bytes do
		pow2 = pow2 * 2
	end
	return math.floor(pow2 / 1024 / 1024)
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: PASS (all 4 `round_up_to_pow2_mb` assertions print `PASS`, then `All routerlabel.util tests passed.`)

- [ ] **Step 5: Commit**

```bash
git add luci-app-router-label/luasrc/routerlabel/util.lua tests/test_routerlabel_util.lua
git commit -m "Add round_up_to_pow2_mb with unit tests"
```

- [ ] **Step 6: Write the failing test for /proc/mtd parsing**

Append to `tests/test_routerlabel_util.lua` (before the final `print` line):

```lua
-- parse_mtd_flash_bytes: takes /proc/mtd content, returns bytes of the
-- largest partition (mirrors the script's "largest single mtd partition"
-- rule, so nested partitions like rootfs_data aren't double-counted).
local mtd_text = [[
dev:    size   erasesize  name
mtd0: 00080000 00010000 "u-boot"
mtd1: 00010000 00010000 "u-boot-env"
mtd2: 00fc0000 00010000 "firmware"
mtd3: 00300000 00010000 "kernel"
mtd4: 00cb0000 00010000 "rootfs"
]]
eq(util.parse_mtd_flash_bytes(mtd_text), 0x00fc0000, "largest mtd partition")
eq(util.parse_mtd_flash_bytes("dev:    size   erasesize  name\n"), 0, "no partitions -> 0 bytes")
```

- [ ] **Step 7: Run test to verify it fails**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: FAIL — `attempt to call a nil value (field 'parse_mtd_flash_bytes')`

- [ ] **Step 8: Write minimal implementation**

Add to `luci-app-router-label/luasrc/routerlabel/util.lua` (before `return M`):

```lua
-- Parse /proc/mtd content and return the size (bytes) of the largest
-- partition. The "dev:  size  erasesize  name" header line never matches
-- (its "size" column isn't hex digits, so %x+ fails on it), so it's
-- skipped naturally by the pattern rather than by an explicit check.
function M.parse_mtd_flash_bytes(text)
	local flashbytes = 0
	for line in text:gmatch("[^\n]+") do
		local dev, size = line:match("^([^:]+):%s+(%x+)")
		if dev then
			local bytes = tonumber(size, 16)
			if bytes and bytes > flashbytes then
				flashbytes = bytes
			end
		end
	end
	return flashbytes
end
```

- [ ] **Step 9: Run test to verify it passes**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: PASS for both new assertions

- [ ] **Step 10: Commit**

```bash
git add luci-app-router-label/luasrc/routerlabel/util.lua tests/test_routerlabel_util.lua
git commit -m "Add parse_mtd_flash_bytes with unit tests"
```

- [ ] **Step 11: Write the failing test for /proc/meminfo parsing and the combined label**

Append to `tests/test_routerlabel_util.lua`:

```lua
-- parse_meminfo_bytes: takes /proc/meminfo content, returns MemTotal in bytes.
local meminfo_text = [[
MemTotal:         124616 kB
MemFree:           45000 kB
]]
eq(util.parse_meminfo_bytes(meminfo_text), 124616 * 1024, "meminfo MemTotal bytes")

-- get_flash_ram_label: combines both byte counts into the "16MB/128MB" label.
eq(util.get_flash_ram_label(0x00fc0000, 124616 * 1024), "16MB/128MB", "flash/ram label")
```

- [ ] **Step 12: Run test to verify it fails**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: FAIL — `attempt to call a nil value (field 'parse_meminfo_bytes')`

- [ ] **Step 13: Write minimal implementation**

Add to `luci-app-router-label/luasrc/routerlabel/util.lua` (before `return M`):

```lua
-- Parse /proc/meminfo content and return MemTotal in bytes.
function M.parse_meminfo_bytes(text)
	local kb = text:match("MemTotal:%s+(%d+)")
	return kb and (tonumber(kb) * 1024) or 0
end

-- Combine flash + RAM byte counts into the "16MB/128MB" label string.
function M.get_flash_ram_label(flashbytes, membytes)
	local flashmb = M.round_up_to_pow2_mb(flashbytes)
	local rammb = M.round_up_to_pow2_mb(membytes)
	return string.format("%dMB/%dMB", flashmb, rammb)
end
```

- [ ] **Step 14: Run test to verify it passes**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: PASS for both new assertions, plus `All routerlabel.util tests passed.` at the end

- [ ] **Step 15: Commit**

```bash
git add luci-app-router-label/luasrc/routerlabel/util.lua tests/test_routerlabel_util.lua
git commit -m "Add parse_meminfo_bytes and get_flash_ram_label with unit tests"
```

---

### Task 3: OpenWrt version parsing (pure Lua, TDD)

Ports the `DISTRIB_DESCRIPTION` extraction from `/etc/openwrt_release`.

**Files:**
- Modify: `luci-app-router-label/luasrc/routerlabel/util.lua`
- Modify: `tests/test_routerlabel_util.lua`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_routerlabel_util.lua`:

```lua
-- parse_openwrt_version: extract DISTRIB_DESCRIPTION from /etc/openwrt_release.
local release_text = [[
DISTRIB_ID='OpenWrt'
DISTRIB_RELEASE='23.05.5'
DISTRIB_REVISION='r24106-10cc5fcd00'
DISTRIB_TARGET='mediatek/filogic'
DISTRIB_DESCRIPTION='OpenWrt 23.05.5 r24106-10cc5fcd00'
DISTRIB_TAINTS=''
]]
eq(util.parse_openwrt_version(release_text), "OpenWrt 23.05.5 r24106-10cc5fcd00", "openwrt version")
eq(util.parse_openwrt_version(""), "", "openwrt version missing -> empty string")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: FAIL — `attempt to call a nil value (field 'parse_openwrt_version')`

- [ ] **Step 3: Write minimal implementation**

Add to `luci-app-router-label/luasrc/routerlabel/util.lua` (before `return M`):

```lua
-- Parse /etc/openwrt_release content and return DISTRIB_DESCRIPTION
-- (the quote character used, ' or ", is matched via a back-reference
-- so the value itself may safely contain the other quote character).
function M.parse_openwrt_version(text)
	local _, desc = text:match("DISTRIB_DESCRIPTION=(['\"])(.-)%1")
	return desc or ""
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: PASS for both new assertions

- [ ] **Step 5: Commit**

```bash
git add luci-app-router-label/luasrc/routerlabel/util.lua tests/test_routerlabel_util.lua
git commit -m "Add parse_openwrt_version with unit tests"
```

---

### Task 4: Wifi selection logic (pure Lua, TDD)

Ports the "first enabled `wifi-iface` wins" rule and the `<no password>`
substitution for open wifi.

**Files:**
- Modify: `luci-app-router-label/luasrc/routerlabel/util.lua`
- Modify: `tests/test_routerlabel_util.lua`

- [ ] **Step 1: Write the failing test**

Append to `tests/test_routerlabel_util.lua`:

```lua
-- pick_wifi: given an ordered list of {disabled=, ssid=, key=} entries
-- (as read from `uci show wireless` wifi-iface sections), return the
-- first enabled one, or nil if none are enabled.
local ifaces = {
	{ disabled = "1", ssid = "Disabled-SSID", key = "secret1" },
	{ disabled = "0", ssid = "Enabled-SSID", key = "secret2" },
}
local picked = util.pick_wifi(ifaces)
eq(picked.ssid, "Enabled-SSID", "pick_wifi picks first enabled")

eq(util.pick_wifi({ { disabled = "1", ssid = "x", key = "y" } }), nil,
	"pick_wifi returns nil when none enabled")
eq(util.pick_wifi({}), nil, "pick_wifi returns nil for empty list")

-- format_wifi_pw: literal key, or "<no password>" for open wifi
-- (empty-string or nil key) -- distinct from "no enabled iface at all",
-- which the caller (the controller) handles separately as "unknown".
eq(util.format_wifi_pw("abcd9876"), "abcd9876", "format_wifi_pw with password")
eq(util.format_wifi_pw(""), "<no password>", "format_wifi_pw open wifi empty string")
eq(util.format_wifi_pw(nil), "<no password>", "format_wifi_pw open wifi nil key")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: FAIL — `attempt to call a nil value (field 'pick_wifi')`

- [ ] **Step 3: Write minimal implementation**

Add to `luci-app-router-label/luasrc/routerlabel/util.lua` (before `return M`):

```lua
-- Given an ordered list of {disabled=, ssid=, key=} wifi-iface entries,
-- return the first enabled one, or nil if none are enabled.
function M.pick_wifi(ifaces)
	for _, iface in ipairs(ifaces) do
		if iface.disabled ~= "1" then
			return iface
		end
	end
	return nil
end

-- Format a wifi key for display: the literal key, or "<no password>"
-- if the iface has no key set (open wifi).
function M.format_wifi_pw(key)
	if key == nil or key == "" then
		return "<no password>"
	end
	return key
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: PASS for all new assertions, plus `All routerlabel.util tests passed.` at the end. This is now the full util.lua test suite — confirm the whole file runs clean end to end.

- [ ] **Step 5: Commit**

```bash
git add luci-app-router-label/luasrc/routerlabel/util.lua tests/test_routerlabel_util.lua
git commit -m "Add pick_wifi and format_wifi_pw with unit tests"
```

---

### Task 5: LuCI controller — menu entry + JSON data endpoint

This is the glue layer: reads `/tmp/sysinfo/model`, `/proc/mtd`,
`/proc/meminfo`, `/etc/openwrt_release`, and `uci` values, feeds them
through `routerlabel.util`, and returns JSON. It requires a real
OpenWrt/LuCI runtime (`luci.model.uci`, `luci.http`), so it can't be unit
tested locally — verification is manual, on a router.

**Files:**
- Create: `luci-app-router-label/luasrc/controller/routerlabel.lua`

- [ ] **Step 1: Write the controller**

Create `luci-app-router-label/luasrc/controller/routerlabel.lua`:

```lua
module("luci.controller.routerlabel", package.seeall)

function index()
	entry({"admin", "system", "routerlabel"}, view("routerlabel"), _("Router Label"), 60).leaf = true
	entry({"admin", "system", "routerlabel", "data"}, call("action_data")).leaf = true
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local content = f:read("*a")
	f:close()
	return content
end

function action_data()
	local util = require("luci.routerlabel.util")
	local uci = require("luci.model.uci").cursor()

	local device = read_file("/tmp/sysinfo/model"):gsub("%s+$", "")
	local mtd_text = read_file("/proc/mtd")
	local meminfo_text = read_file("/proc/meminfo")
	local release_text = read_file("/etc/openwrt_release")

	local flashram = util.get_flash_ram_label(
		util.parse_mtd_flash_bytes(mtd_text),
		util.parse_meminfo_bytes(meminfo_text)
	)
	local openwrt_version = util.parse_openwrt_version(release_text)

	local hostname = uci:get("system", "@system[0]", "hostname") or ""
	local lanip = uci:get("network", "lan", "ipaddr") or ""
	local dnstld = uci:get("dhcp", "@dnsmasq[0]", "domain") or ""

	local ifaces = {}
	uci:foreach("wireless", "wifi-iface", function(s)
		table.insert(ifaces, { disabled = s.disabled, ssid = s.ssid, key = s.key })
	end)
	local wifi = util.pick_wifi(ifaces)

	local wifi_ssid, wifi_pw
	if wifi then
		wifi_ssid = wifi.ssid or ""
		wifi_pw = util.format_wifi_pw(wifi.key)
	else
		wifi_ssid = "unknown"
		wifi_pw = "unknown"
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json({
		device = device,
		flashram = flashram,
		openwrt_version = openwrt_version,
		hostname = hostname,
		lanip = lanip,
		dnstld = dnstld,
		wifi_ssid = wifi_ssid,
		wifi_pw = wifi_pw,
	})
end
```

Note the module require is `luci.routerlabel.util` (not the bare
`routerlabel.util` used by the local test) — on the router, this file
installs to `/usr/lib/lua/luci/routerlabel/util.lua`, and OpenWrt's
default Lua path (`/usr/lib/lua/?.lua`) resolves that dotted name to
exactly that path. The local test's `package.path` override in Task 2
Step 1 is a test-only convenience for running the module without a
router; it does not need to match this string.

- [ ] **Step 2: Commit**

```bash
git add luci-app-router-label/luasrc/controller/routerlabel.lua
git commit -m "Add luci-app-router-label controller (menu entry + JSON data endpoint)"
```

- [ ] **Step 3: Manually verify on a real (or VM) OpenWrt router**

```bash
ssh root@<router> mkdir -p /usr/lib/lua/luci/routerlabel
scp -O luci-app-router-label/luasrc/routerlabel/util.lua root@<router>:/usr/lib/lua/luci/routerlabel/util.lua
scp -O luci-app-router-label/luasrc/controller/routerlabel.lua root@<router>:/usr/lib/lua/luci/controller/routerlabel.lua
ssh root@<router> rm -f /tmp/luci-indexcache*
```

(`-O` forces the legacy SCP protocol -- Dropbear, OpenWrt's default SSH
server, has no `sftp-server` binary, and modern `scp` clients default to
SFTP. Without it: `ash: /usr/libexec/sftp-server: not found`.)

Then, still on the router (or via `ssh root@<router> curl ...` with a
valid session cookie), confirm the JSON endpoint responds. The simplest
check is from a browser already logged into LuCI: visit
`http://<router>/cgi-bin/luci/admin/system/routerlabel/data` and confirm
it returns a JSON object with `device`, `flashram`, `openwrt_version`,
`hostname`, `lanip`, `dnstld`, `wifi_ssid`, `wifi_pw` populated with
real values (compare a couple against `print-router-label.sh`'s output
on the same router).

Expected: JSON response, not a Lua error page. If it 500s, check
`logread | grep luci` on the router for the Lua traceback — most likely
cause is a typo in the `require` path or a `uci` section that doesn't
exist on that device (e.g. no `dhcp.@dnsmasq[0]` on a device with dnsmasq
disabled) — confirm the `or ""` fallbacks are catching it.

---

### Task 6: LuCI JS view — render the label table + password field

Requires a real LuCI runtime to execute (browser JS against the live
LuCI JS API), so this is also verified manually rather than by an
automated test.

**Files:**
- Create: `luci-app-router-label/htdocs/luci-static/resources/view/routerlabel.js`

- [ ] **Step 1: Write the view**

Create `luci-app-router-label/htdocs/luci-static/resources/view/routerlabel.js`:

```javascript
'use strict';
'require view';
'require ui';

return view.extend({
	load: function () {
		return L.resolveDefault(
			fetch(L.url('admin', 'system', 'routerlabel', 'data')).then(function (res) {
				return res.json();
			}),
			null
		);
	},

	render: function (data) {
		if (!data) {
			ui.addNotification(null, E('p', {}, _('Could not load router label data.')), 'danger');
			return E('p', {}, _('Could not load router label data.'));
		}

		var device = data.device || '';
		var flashram = data.flashram || '';
		var openwrtVersion = data.openwrt_version || '';
		var hostname = data.hostname || '';
		var dnstld = data.dnstld || '';
		var lanip = data.lanip || '';
		var wifiSsid = data.wifi_ssid || '';
		var wifiPw = data.wifi_pw || '';

		// Matches the script exactly, including the trailing "." when
		// dnstld is unset (script: "http://$HOSTNAME.$LOCALDNSTLD" with
		// no fallback) -- don't special-case an empty dnstld here, or the
		// LAN address will silently diverge from print-router-label.sh's
		// output on routers with no dhcp domain configured.
		var fqdn = hostname + '.' + dnstld;
		var today = new Date().toISOString().slice(0, 10);

		var loginPwCell = E('td', { 'class': 'td' }, '?');

		var pwInput = E('input', {
			type: 'text',
			placeholder: '?',
			style: 'max-width: 20em',
			input: function (ev) {
				loginPwCell.textContent = ev.target.value || '?';
			}
		});

		var rows = [
			['Device', device],
			['Flash/RAM', flashram],
			['OpenWrt', openwrtVersion],
			['Connect to', 'http://' + fqdn],
			['or', 'ssh root@' + fqdn],
			['LAN', lanip],
			['User', 'root'],
			['Login PW', loginPwCell],
			['Wifi SSID', wifiSsid],
			['Wifi PW', wifiPw],
			['Configured', today],
			['Label for Power Brick', device]
		];

		var table = E('table', { 'class': 'table' }, rows.map(function (row) {
			var label = row[0], value = row[1];
			// Wrap in an array so LuCI's dom.append() text-nodes this rather
			// than assigning to innerHTML -- these values come from uci config
			// (device name, hostname, wifi SSID/key) and can contain characters
			// like "<no password>" that would otherwise be parsed as markup.
			var valueCell = (value && value.nodeType) ? value : E('td', { 'class': 'td' }, [ String(value) ]);
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'width': '33%' }, [ E('strong', {}, label) ]),
				valueCell
			]);
		}));

		return E('div', {}, [
			E('h2', {}, _('Router Label')),
			E('p', {}, _('Same information as print-router-label.sh, for taping to the router. ' +
				'The login password below is not saved anywhere — it only updates this page.')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Login PW')),
				pwInput
			]),
			E('br'),
			table
		]);
	}
});
```

- [ ] **Step 2: Commit**

```bash
git add luci-app-router-label/htdocs/luci-static/resources/view/routerlabel.js
git commit -m "Add luci-app-router-label JS view"
```

- [ ] **Step 3: Manually verify on a real (or VM) OpenWrt router**

```bash
scp -O luci-app-router-label/htdocs/luci-static/resources/view/routerlabel.js \
	root@<router>:/www/luci-static/resources/view/routerlabel.js
ssh root@<router> rm -f /tmp/luci-indexcache*
```

(`-O` forces the legacy SCP protocol -- see the note in Task 5 Step 3.)

In a browser, log into LuCI on that router and go to **System → Router
Label**. Verify against `print-router-label.sh`'s console output on the
same router:

- All 12 rows are present (Device, Flash/RAM, OpenWrt, Connect to, or,
  LAN, User, Login PW, Wifi SSID, Wifi PW, Configured, Label for Power
  Brick) and match the script's values.
- Typing in the Login PW field updates the **Login PW** table row
  immediately, with no page reload or network request (check the
  browser Network tab — confirm nothing fires on keystroke).
- Clearing the Login PW field shows `?` in the table row.
- Reloading the page clears whatever was typed (confirms nothing was
  persisted).
- If the router has an open (no-password) wifi network enabled, confirm
  the Wifi PW row shows `<no password>` (not blank).
- If no wifi-iface is enabled at all, confirm both Wifi SSID and Wifi PW
  show `unknown`.

If the page doesn't appear in the menu at all, re-check
`/tmp/luci-indexcache*` was actually cleared and that both the
controller (Task 5) and this view are in place — a missing view file
with a valid controller entry typically shows as a blank/error page
rather than a missing menu item.

---

### Task 7: List the new app in the repo README

Every script in this repo is listed in the top-level `README.md` (see the
bullet list near the top, and each script's own `##` section further
down). Add a matching entry for the new LuCI app so it's discoverable the
same way.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a bullet to the top list**

In `README.md`, immediately after the existing `print-router-label.sh`
bullet (around line 20-22), add:

```markdown
* [luci-app-router-label](#luci-app-router-label) -
  A LuCI web GUI page (System > Router Label) showing the same
  information as print-router-label.sh, with a fill-in-only field
  for the root password.
```

- [ ] **Step 2: Add a matching section**

In `README.md`, immediately after the existing `## print-router-label.sh`
section (after its sample-label code block, around line 140), add:

```markdown
## [luci-app-router-label](https://github.com/richb-hanover/OpenWrtScripts/tree/master/luci-app-router-label)

Shows the same information as `print-router-label.sh` (device, Flash/RAM,
OpenWrt version, LAN address, Wifi credentials) in the LuCI web GUI,
under **System > Router Label**, instead of on the console. The root
login password isn't derivable from `uci`, so it's a plain text field on
the page that only updates the page's display — nothing is saved or
sent anywhere.

Currently ships as loose files rather than an installable package; see
[luci-app-router-label/README.md](./luci-app-router-label/README.md) for
how to try it on a router.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "List luci-app-router-label in the repo README"
```

---

### Task 8: Final end-to-end check

- [ ] **Step 1: Run the full local unit test suite one more time**

Run: `cd tests && lua test_routerlabel_util.lua`
Expected: `All routerlabel.util tests passed.` with no errors

- [ ] **Step 2: Confirm git log tells a clean story**

Run: `git log --oneline main..openwrt-apk`
Expected: one commit per task above (skeleton, 4 util.lua commits, controller,
view, README), all with clear messages, nothing stray or half-finished

- [ ] **Step 3: Re-run the Task 5/6 manual on-router checklist once more, end to end**

With all files in place on a test router simultaneously (controller +
util.lua + view.js), walk through **System → Router Label** one more
time as a final sanity check before considering this done, using the
checklist in Task 6 Step 3.
