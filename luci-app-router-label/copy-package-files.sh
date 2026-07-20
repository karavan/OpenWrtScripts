#! /bin/sh

# Copy all the files required for the package
# to the router and restart all the machinery

set -e   # stop on the first failed scp/ssh instead of restarting rpcd on a partial deploy

# Run from anywhere -- always operate relative to this script's own directory,
# since the scp source paths below are relative to luci-app-router-label/.
cd "$(dirname "$0")" || exit 1

ssh root@172.30.42.1 mkdir -p /usr/share/luci/menu.d /usr/share/rpcd/acl.d /www/luci-static/resources/view

scp -O htdocs/luci-static/resources/routerlabel.js \
	root@172.30.42.1:/www/luci-static/resources/routerlabel.js
scp -O htdocs/luci-static/resources/view/routerlabel.js \
	root@172.30.42.1:/www/luci-static/resources/view/routerlabel.js
scp -O root/usr/share/luci/menu.d/luci-app-router-label.json \
	root@172.30.42.1:/usr/share/luci/menu.d/luci-app-router-label.json
scp -O root/usr/share/rpcd/acl.d/luci-app-router-label.json \
	root@172.30.42.1:/usr/share/rpcd/acl.d/luci-app-router-label.json

ssh root@172.30.42.1 rm -f /tmp/luci-indexcache*
ssh root@172.30.42.1 /etc/init.d/rpcd restart