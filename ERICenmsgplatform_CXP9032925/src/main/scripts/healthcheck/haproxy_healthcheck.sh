#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2015
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################

# GLOBAL VARIABLES
_INITSCRIPT=/etc/init.d/haproxy
ARG="monitor"

#//////////////////////////////////////////////////////////////
# Main Part of Script
#/////////////////////////////////////////////////////////////

$_INITSCRIPT $ARG > /dev/null 2>&1
ret=$?
if [[ "$ret" -eq 0 ]]; then
  exit 0
else
  exit 1
fi