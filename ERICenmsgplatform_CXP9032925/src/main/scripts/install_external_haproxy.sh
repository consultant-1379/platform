#!/bin/bash

################################################################################
# Copyright (c) 2015 Ericsson, Inc. All Rights Reserved.
# This script installs the Haproxy
# Author: Marcin Pawlowski
# 
###############################################################################

RM=/bin/rm
CP=/bin/cp
LN=/bin/ln
MKDIR=/bin/mkdir

LOG_DIR="/ericsson/log/3pp/haproxy"
LOG_FILE="$LOG_DIR/haproxy-external-install-`/bin/date "+%F:%H:%M:%S%:z"`.log"

# deployment paths
HA_ROOT=/ericsson/3pp/haproxy

HAPROXY_SERVICE=/etc/init.d/haproxy-ext
HAPROXY_GENERIC_SERVICE=/etc/init.d/haproxy


########################################################
# Replace service
#
########################################################
ServiceModify()
{


  LogMessage "INFO: ServiceModify invoked, processing request .........."

  if [ ! -f ${HAPROXY_GENERIC_SERVICE} ] ; then
     LogMessage "ERROR: HAproxy generic service does not exist"
     return 1
  fi
  
  if [ -e ${HAPROXY_SERVICE} ] ; then
    ${RM} -f ${HAPROXY_SERVICE}
  fi

  ${MKDIR} -p ${HA_ROOT}/data/security/

  chown -R haproxy:haproxy ${HA_ROOT}

  if [ $? -ne 0 ]; then
    LogMessage "ERROR: failed to chown $HA_ROOT"
    return 1
  fi
  
  ${LN} -s ${HAPROXY_GENERIC_SERVICE} ${HAPROXY_SERVICE}

  if [ $? -ne 0 ]; then
    LogMessage "ERROR: failed to create symlink for external haproxy"
    return 1
  fi
  
  LogMessage "INFO: ServiceModify completed successfully"
  
  return 0
}


###############################################################################
# Main Program
# Parameters: None
###############################################################################
source $HA_ROOT/etc/common.sh
if [ $? -ne 0 ]; then
   echo "ERROR: Failed to source $HA_ROOT/etc/common.sh"
   exit 1
fi

SetLogFile $LOG_DIR $LOG_FILE
if [ $? != 0 ]; then
    echo "ERROR: SetLogFile failed"
    exit 1
fi

LogMessage "Haproxy external installation started..." 
if [ $# -ne 0 ]; then
   LogMessage "ERROR: Wrong number of arguments $#"
  # exit 1
fi

LogMessage "INFO: This is an install"

ServiceModify
if [ $? != 0 ] ; then
   LogMessage "ERROR: Service HAproxy external modification failed."
   exit 1
fi

info "Running Service Group RPM postinstall"
## TORF-77068  haproxy-ext should only be called/run by VCS
info  "Setting HAProxy External chkconfig off"
/sbin/chkconfig haproxy-ext off

LogMessage "INFO: install_external_haproxy.sh completed successfully."
exit 0
