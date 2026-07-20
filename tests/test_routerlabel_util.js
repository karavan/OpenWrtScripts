// Unit tests for luci-app-router-label's pure-JS parsing/formatting logic.
// Run with: node test_routerlabel_util.js  (from inside tests/)
//
// The production file (../luci-app-router-label/htdocs/luci-static/resources/
// routerlabel.js) is a real LuCI class module: 'require baseclass'; return
// baseclass.extend({...}); -- LuCI's require() loader (compileClass() in
// luci.js) specifically rejects anything that isn't a genuine
// baseclass-derived class (Class.isSubclass() check), so it can't be a
// plain object or a hand-rolled constructor.
//
// That means a plain Node require() of that file won't work: `baseclass` is
// a parameter LuCI's real loader injects into the module's factory function,
// not a global, and doesn't exist under Node. So this harness does the same
// thing LuCI's loader does -- wrap the file's source in a factory function
// that takes `baseclass` as a parameter, and call it with a minimal shim --
// to test the *actual* production file rather than a duplicate copy of its
// logic.

var fs = require('fs');
var path = require('path');

var SOURCE_PATH = path.join(__dirname, '..', 'luci-app-router-label',
	'htdocs', 'luci-static', 'resources', 'routerlabel.js');
var source = fs.readFileSync(SOURCE_PATH, 'utf8');

// Minimal stand-in for LuCI's real baseclass.extend(): given a plain object
// of methods, return a constructor whose prototype has those methods. LuCI's
// real version also makes the result satisfy Class.isSubclass() for the
// browser loader's benefit -- irrelevant here, since Node never runs that
// check; we only need `new ReturnedClass()` to produce a usable instance.
var baseclassShim = {
	extend: function (members) {
		function Extended() {}
		for (var key in members) {
			if (Object.prototype.hasOwnProperty.call(members, key)) {
				Extended.prototype[key] = members[key];
			}
		}
		return Extended;
	}
};

var factory = new Function('baseclass', source);
var RouterLabelClass = factory(baseclassShim);
var util = new RouterLabelClass();

function eq(actual, expected, label) {
	if (actual !== expected) {
		throw new Error('FAIL ' + label + ': expected ' + JSON.stringify(expected) + ', got ' + JSON.stringify(actual));
	}
	console.log('PASS ' + label);
}

// roundUpToPow2Mb
eq(util.roundUpToPow2Mb(16 * 1024 * 1024), 16, 'round exact 16MB');
eq(util.roundUpToPow2Mb(15 * 1024 * 1024), 16, 'round up 15MB -> 16MB');
eq(util.roundUpToPow2Mb(16 * 1024 * 1024 - 100), 16, 'round up just-under-16MB');
eq(util.roundUpToPow2Mb(128 * 1024 * 1024), 128, 'round exact 128MB');

// parseMtdFlashBytes
var mtdText = [
	'dev:    size   erasesize  name',
	'mtd0: 00080000 00010000 "u-boot"',
	'mtd1: 00010000 00010000 "u-boot-env"',
	'mtd2: 00fc0000 00010000 "firmware"',
	'mtd3: 00300000 00010000 "kernel"',
	'mtd4: 00cb0000 00010000 "rootfs"',
	''
].join('\n');
eq(util.parseMtdFlashBytes(mtdText), 0x00fc0000, 'largest mtd partition');
eq(util.parseMtdFlashBytes('dev:    size   erasesize  name\n'), 0, 'no partitions -> 0 bytes');

// getFlashRamLabel
eq(util.getFlashRamLabel(0x00fc0000, 124616 * 1024), '16MB/128MB', 'flash/ram label');

// pickWifi
var ifaces = [
	{ disabled: '1', ssid: 'Disabled-SSID', key: 'secret1' },
	{ disabled: '0', ssid: 'Enabled-SSID', key: 'secret2' }
];
var picked = util.pickWifi(ifaces);
eq(picked.ssid, 'Enabled-SSID', 'pickWifi picks first enabled');

eq(util.pickWifi([ { disabled: '1', ssid: 'x', key: 'y' } ]), null, 'pickWifi returns null when none enabled');
eq(util.pickWifi([]), null, 'pickWifi returns null for empty list');

// formatWifiPw
eq(util.formatWifiPw('abcd9876'), 'abcd9876', 'formatWifiPw with password');
eq(util.formatWifiPw(''), '<no password>', 'formatWifiPw open wifi empty string');
eq(util.formatWifiPw(null), '<no password>', 'formatWifiPw open wifi null key');
eq(util.formatWifiPw(undefined), '<no password>', 'formatWifiPw open wifi undefined key');

console.log('All routerlabel.util tests passed.');
