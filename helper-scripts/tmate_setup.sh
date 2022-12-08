#!/bin/bash

sudo apt-get install -y tmate

echo "About to start tmate"
echo "Once tmate is started:"
echo "- Press q to get to the shell"
echo "- run the script /tmp/tmate.export.sh"
echo "- Note the provided pastebin URL"
echo "- Type <ctrl b>-<d> to suspend the tmate session without quitting"
echo ""

echo "On your laptop"
echo "- Browse to ubuntu.paste.com"
echo "- login then browse to the provided URL"
echo "- Copy the pastebin value (except the last 2 suffix chars)"
echo "- Use the value as a user name to ssh to the tmate session"
echo "  e.g."
echo "    ssh xy78fge923ss8809@lon1.tmate.io""


cat > /tmp/tmate.export.sh <<EOF

echo "Enter a random 2-char suffix"
read SU

tmate show-messages | awk ‘/ssh session:/ { print $10; }’ | sed ‘s/@lon1.*/97/’ | pastebinit

EOF


