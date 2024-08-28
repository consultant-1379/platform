#!/bin/bash
if [[ `/etc/init.d/haproxy-ext status` == *"stopped"* ]]; then
    /opt/VRTS/bin/hagrp -switch Grp_CS_svc_cluster_haproxy_ext -any
else
    /etc/init.d/haproxy-ext restart
fi
