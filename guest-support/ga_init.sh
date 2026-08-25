#!/bin/bash
mkdir /opt/vemu-init
cp ga_init.rb /opt/vemu-init/
cp localruby.tzst /opt/vemu-init/
cd /opt/vemu-init
chmod -x localruby.tzst
tar -xf localruby.tzst
chown root:root -R localruby

systemctl daemon-reload
systemctl enable vemu-guest-agent.service
systemctl start vemu-guest-agent.service
