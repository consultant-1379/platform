#!/bin/bash
#----------------------------------------------------------------------------
#############################################################################
# COPYRIGHT Ericsson 2013
# The copyright to the computer program therein is the property of
# conditions stipulated in the agreement/contract under which the
# program have been supplied.
#############################################################################
#----------------------------------------------------------------------------

_GREP=/bin/grep
_ECHO=/bin/echo
_TR=/usr/bin/tr
_SED=/bin/sed
_CP="/bin/cp -f"
_CHMOD=/bin/chmod
_MV="/bin/mv -f"
_MKDIR="/bin/mkdir"
_RM="/bin/rm"

DATE=`date +"%d-%m-%Y-%H%M"`

SSO_CERT_DIR=/ericsson/tor/data/certificates/sso
SSO_CERT_PREFIX=ssoserverapache
PKI_CERT_DIR=/etc/pki/tls/certs
PKI_KEY_DIR=/etc/pki/tls/private
SSO_CERT=${PKI_CERT_DIR}/${SSO_CERT_PREFIX}.crt
SSO_KEY=${PKI_KEY_DIR}/${SSO_CERT_PREFIX}.key
NEW_SSO_CERT=${SSO_CERT_DIR}/${SSO_CERT_PREFIX}.crt
NEW_SSO_KEY=${SSO_CERT_DIR}/${SSO_CERT_PREFIX}.key


HAPROXY_CERT_DIR=/ericsson/tor/data/certificates/haproxy
HAPROXYAPACHE_CERT=${HAPROXY_CERT_DIR}/apacheserver.pem
HAPROXY_XML=haproxy-ext_CertRequest.xml
NEW_HAPROXY_KC=${HAPROXY_CERT_DIR}/ssoserver.pem

CREDM_DATA_XML=/ericsson/credm/data/xmlfiles
CREDM_DATA_TMP_XML=/ericsson/3pp/haproxy/data/cert_request
CREDM_LOCATION=/opt/ericsson/ERICcredentialmanagercli/bin/credentialmanager.sh

CONFIGURATION_CHECK="service haproxy-ext check"
IS_OLD_CONF_VALID="false"

PROPERTIES_FILE="/ericsson/tor/data/global.properties"
CONFIGURE_HAPROXY=/ericsson/3pp/haproxy/etc/kvm_ha_config.sh
HAPROXY_CFG="/ericsson/3pp/haproxy/data/config/haproxy-ext.cfg"
HAPROXY_CFG_TEMPLATE="/ericsson/3pp/haproxy/data/config/haproxy-ext.cfg.template"
HAPROXY_OLD_CONFIG=/tmp/haproxy-configuration-${DATE}.cfg
prg=$( basename "${BASH_SOURCE[0]}" )
prg_dir=$( cd `dirname "${BASH_SOURCE[0]}"` && pwd )

info()
{
    logger -s -t TOR_HAPROXY_CONFIG -p user.notice "INFORMATION ($prg): $@"
}

error()
{
    logger -s -t TOR_HAPROXY_CONFIG -p user.err "ERROR ($prg): $@"
}

#wait

wait_for_properties()
{
while [ ! -f "$PROPERTIES_FILE" ]
do
    info "$PROPERTIES_FILE does not exist - waiting"
    sleep 2
done
info "$PROPERTIES_FILE exists!"
info "Proceeding with HAProxy External Configuration"
}


check_sso_aliases ()
{
count=0
while IFS='' read -r line || [[ -n "$line" ]]; do
 if [[ $line =~ (sso-instance$'\t'|sso-instance |sso-instance-[[:digit:]]) ]]; then
   arr_sso_tmp[$count]=$(echo "${BASH_REMATCH[1]}" | tr -d '\040\011\012\015')
   arr_sso_ip[$count]=`echo $line | awk '{print $1}'`
   array_sso_joined[$count]="${arr_sso_ip[$count]}=${arr_sso_tmp[$count]}"
   count=$(($count+1))

 fi
done < "/etc/hosts"

i=0
k=0
sorted_arr_sso=( $(echo "${array_sso_joined[@]}" | tr ' ' '\n' | sort -r | tr '\n' ' ') )

    for x in ${sorted_arr_sso[@]}
      do
      if [ $i -gt 0 ]; then
        j=$((i-1))
        ip_1=$(echo $x | cut -d'=' -f 1)
        ip_2=$(echo  ${sorted_arr_sso[$j]} | cut -d'=' -f 1)
        alias_1=$(echo $x | cut -d'=' -f 2)
        alias_2=$(echo  ${sorted_arr_sso[$j]} | cut -d'=' -f 2)
        if [[ "$ip_1" == "$ip_2" ]]; then
           if [[ "$alias_2" == "sso-instance" ]]; then
             arr_sso[$((k-1))]=$alias_1
           fi
        else
           arr_sso[$k]=$alias_1
           k=$((k+1)) 
        fi
      else
        arr_sso[$k]=$(echo $x | cut -d'=' -f 2)
        k=$((k+1)) 
      fi
      i=$((i+1))
    done

}

wait_for_properties

if [ -f "${HAPROXY_CFG_TEMPLATE}" ]; then
    $_CP ${HAPROXY_CFG} ${HAPROXY_OLD_CONFIG}
fi

info "Sourcing from central config store for HAProxy External configuration"
. $PROPERTIES_FILE

ret_val=`$CONFIGURATION_CHECK` > /dev/null 2>&1

if [ ${?} -eq 0 ]; then
   IS_OLD_CONF_VALID="true"
fi


# Check if the haproxy.cfg is present
 if [ -f "${HAPROXY_CFG_TEMPLATE}" ]; then
     info "Updating ${HAPROXY_CFG}"
     # Update frontend name and healthcheck hostname for SSO backends
     cat  ${HAPROXY_CFG_TEMPLATE} | sed -e "s/MYHOSTNAME/${UI_PRES_SERVER}/g" > ${HAPROXY_CFG} 2>/dev/null

# If haproxy.cfg is present, check if there is defined $httpd_instances key in global.properties
     if [ ! -z "$httpd_instances" ]; then
        arr=$(echo $httpd_instances | tr "," "\n")
     else
        error " ${httpd_instances} not found"
        exit 1
     fi

# If haproxy.cfg is present, check if there is defined $sso_instances key in global.properties
#     if [ ! -z "$sso_instances" ]; then
#        arr_sso=$(echo $sso_instances | tr "," "\n")
#     else
#        error "sso_instances key not found in global.properties"
#        exit 1
#     fi


     i=0;
# Define HTTP backends in haproxy.cfg
# Example:
# backend apache_http
#    balance     roundrobin
#    cookie iPlanetDirectoryPro prefix nocache
#    server httpdserver_80_1 httpd-instance-1:80 cookie S1 check
#    server httpdserver_80_2 httpd-instance-2:80 cookie S2 check
#    ...
#    log global

    for x in ${arr[@]}
      do
      i=$((i+1))
      serv="${serv}    server httpdserver_80_${i} ${x}:${web_ports_unsecurePort} cookie S${i} check\n"
    done

    sed -i "s/APACHE_BACKEND_NAMES_80/${serv}/g" ${HAPROXY_CFG}

    serv=""
    i=0;

# Define HTTPS backends in haproxy.cfg
# Example:
# backend apache_https
#    balance     roundrobin
#    cookie iPlanetDirectoryPro prefix nocache
#    server httpdserver_443_1 httpd-instance-1:443 ssl cookie S1 check
#    server httpdserver_443_2 httpd-instance-2:443 ssl cookie S2 check
#    ...
#    log global

    for x in ${arr[@]}
    do
        i=$((i+1))
        serv="${serv}    server httpdserver_443_${i} ${x}:${web_ports_securePort} ssl cookie S${i} check\n"
    done
    sed -i "s/APACHE_BACKEND_NAMES_443/${serv}/g" ${HAPROXY_CFG}

    serv=""
    i=0;

# Define iorfile backends in haproxy.cfg
# Example:
# backend iorfile_http
#    balance     roundrobin
#    cookie iPlanetDirectoryPro prefix nocache
#    server iorfile_1 iorfile1.atrcxb2461-1.athtem.eei.ericsson.se:80 cookie S1 check
#    server iorfile_2 iorfile2.atrcxb2461-1.athtem.eei.ericsson.se:80 cookie S2 check
#
#    log global

    IORFILE1=`grep iorfile1 /etc/hosts`
    IORFILE2=`grep iorfile2 /etc/hosts`

    if [ -n "$IORFILE1" ] && [ -n "$IORFILE2" ] ; then
        arr=('iorfile1' 'iorfile2')
    else
        arr=('iorfile')
    fi

    for x in ${arr[@]}
      do
      i=$((i+1))
      serv="${serv}    server iorfile_${i} ${x}.${UI_PRES_SERVER}:${web_ports_unsecurePort} check\n"
    done

    sed -i "s/BACKEND_NAMES_IORFILE/${serv}/g" ${HAPROXY_CFG}

   check_sso_aliases

   if [ ${#arr_sso[@]} -eq 0 ]; then
      sed -i "s/SSO_BACKEND_NAMES_8080//g" ${HAPROXY_CFG}
      sed -i "s/SSO_BACKEND_NAMES_8443//g" ${HAPROXY_CFG}
   else

# Define SSO HTTP backends in haproxy.cfg
# Example:
# backend s_https
#    balance     roundrobin
#    cookie ssocookie insert nocache
#    option httpchk GET /heimdallr/haproxy_healthcheck.jsp HTTP/1.1\r\nHost:\ HOSTNAME
#    server ssoserver_8080_1 sso-instance-1.FQDN:8080 cookie ssocookie-1 check
#    server ssoserver_8080_2 sso-instance-2.FQDN:8080 cookie ssocookie-2 check
#    ...
#    log global

    serv=""
    i=0;

    for x in ${arr_sso[@]}
      do
      i=$((i+1))
      serv="${serv}    server ssoserver_8080_${i} ${x}.${UI_PRES_SERVER}:8080 cookie ssocookie-${i} check\n"
    done

    sed -i "s/SSO_BACKEND_NAMES_8080/${serv}/g" ${HAPROXY_CFG}

# Define SSO HTTPS backends in haproxy.cfg
# Example:
# backend sso_https
#    balance     roundrobin
#    cookie ssocookie insert nocache
#    option httpchk GET /heimdallr/haproxy_healthcheck.jsp HTTP/1.1\r\nHost:\ HOSTNAME
#    server ssoserver_8443_1 sso-instance-1.FQDN:8443 ssl cookie ssocookie-1 check
#    server ssoserver_8443_2 sso-instance-2.FQDN:8443 ssl cookie ssocookie-2 check
#    ...
#    log global

    serv=""
    i=0;

    for x in ${arr_sso[@]}
      do
      i=$((i+1))
      serv="${serv}    server ssoserver_8443_${i} ${x}.${UI_PRES_SERVER}:8443 ssl cookie ssocookie-${i} check\n"
    done

    sed -i "s/SSO_BACKEND_NAMES_8443/${serv}/g" ${HAPROXY_CFG}
  fi
else
     error " ${HAPROXY_CFG_TEMPLATE} not found"
    exit 1
fi

#############################################################
# Action :
#   configure_amos_websockets_backend
#  Configures the amos_websocket backend.
# Globals :
#   _SED
#   _ECHO
#   _TR
#   HAPROXY_CFG
#   amos_instances (sourced from global.properties)
#   web_ports_appServer (sourced from global.properties)
# Arguments:
#   None
# Returns:
#   None
#############################################################
configure_amos_websockets_backend()
{
    if [ -z "${amos_instances}" ]; then
        info "amos_instances not found, Returning without configuring haproxy for amos"
        #Remove AMOS placeholder from configuration file.
        ${_SED} -i "s/AMOS_WEBSOCKET_BACKEND//g" "${HAPROXY_CFG}"
        return
    fi

    amos_server_instances=( $(${_ECHO} "${amos_instances}" | ${_TR} ',' '\n') )
    for instance in "${!amos_server_instances[@]}"
    do
        amos_backend_instances="${amos_backend_instances}    server jboss-64-$((instance+1)) ${amos_server_instances[$instance]}:${web_ports_appServer} cookie S$((instance+1)) check\n"
    done

    ${_SED} -i "s/AMOS_WEBSOCKET_BACKEND/${amos_backend_instances}/g" "${HAPROXY_CFG}"
}

configure_amos_websockets_backend

#############################################################
# Action :
#   configure_elementmanager_websockets_backend
#  Configures the EM_DESKTOP_BACKEND backend.
# Globals :
#   _SED
#   _ECHO
#   _TR
#   HAPROXY_CFG
#   elementmanager_instances (sourced from global.properties)
#   web_ports_securePort  (sourced from global.properties)
# Arguments:
#   None
# Returns:
#   None
#############################################################
configure_elementmanager_websockets_backend()
{
    if [ -z "${elementmanager_instances}" ]; then
        info "elementmanager_instances not found, Returning without configuring haproxy for element manager"
        #Remove EM placeholder from configuration file.
        ${_SED} -i "s/EM_DESKTOP_BACKEND//g" "${HAPROXY_CFG}"
        return
    fi

    elementmanager_server_instances=( $(${_ECHO} "${elementmanager_instances}" | ${_TR} ',' '\n') )
    for instance in "${!elementmanager_server_instances[@]}"
    do
        elementmanager_backend_instances="${elementmanager_backend_instances}    server elementmanager-$((instance+1)) ${elementmanager_server_instances[$instance]}:${web_ports_securePort} ssl verify none check-ssl cookie S$((instance+1)) check\n"
    done

    ${_SED} -i "s/EM_DESKTOP_BACKEND/${elementmanager_backend_instances}/g" "${HAPROXY_CFG}"
}

configure_elementmanager_websockets_backend

#############################################################
# Action :
#   configure_nodecli_websocket_backend
#  Configures the nodecli_websocket backend.
# Globals :
#   _SED
#   _ECHO
#   _TR
#   HAPROXY_CFG
#   nodecli (sourced from global.properties)
#   web_ports_appServer (sourced from global.properties)
# Arguments:
#   None
# Returns:
#   None
#############################################################
configure_nodecli_websocket_backend()
{
    if [ -z "${nodecli}" ]; then
        info "nodecli global property not found, returning without configuring haproxy for Node CLI"
        # Remove Node CLI placeholder from configuration file.
        ${_SED} -i "s/NODECLI_WEBSOCKET_BACKEND//g" "${HAPROXY_CFG}"
        return
    fi

    local nodecli_server_instances=( $(${_ECHO} "${nodecli}" | ${_TR} ',' '\n') )
    local nodecli_backend_instances
    for instance in "${!nodecli_server_instances[@]}"
    do
        nodecli_backend_instances="${nodecli_backend_instances}    server nodecli-$((instance+1)) ${nodecli_server_instances[$instance]}:${web_ports_appServer} cookie S$((instance+1)) check\n"
    done

    ${_SED} -i "s/NODECLI_WEBSOCKET_BACKEND/${nodecli_backend_instances}/g" "${HAPROXY_CFG}"
}
configure_nodecli_websocket_backend


######################################################
#
# Configure haproxy
#
#######################################################

if [ ! -d ${HAPROXY_CERT_DIR} ]; then
    ${_MKDIR} ${HAPROXY_CERT_DIR}
fi

#
# prepare sso certificate
#
if [ ! -f ${SSO_CERT} -o ! -f ${SSO_KEY} ]; then
    info "SSO certificate or key file not present, copying from shared area"
    ${_CP} ${NEW_SSO_CERT} ${PKI_CERT_DIR} && \
    ${_CP} ${NEW_SSO_KEY} ${PKI_KEY_DIR} && \
    ${_CHMOD} 600 ${SSO_CERT} ${SSO_KEY} && \
    info "Certificate and key installed"
fi

cat ${NEW_SSO_CERT} ${NEW_SSO_KEY} > ${NEW_HAPROXY_KC}

#
# retrieve certificates from Credential Manager
#

## prepare xml cert request file
HAPROXY_EXT_IP=$(${_GREP} -E "\s${UI_PRES_SERVER}" /etc/hosts | ${_GREP} --only-matching -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
${_CP} ${CREDM_DATA_TMP_XML}/${HAPROXY_XML}.template ${CREDM_DATA_TMP_XML}/${HAPROXY_XML}
${_SED} -i "s/FQDN/${UI_PRES_SERVER}/g" ${CREDM_DATA_TMP_XML}/${HAPROXY_XML}
${_SED} -i "s/HAPROXY-EXT_IP/${HAPROXY_EXT_IP}/g" ${CREDM_DATA_TMP_XML}/${HAPROXY_XML}

## compare new xml cert request file with the previous one
CMPXMLRESULT=1
if [ -f ${CREDM_DATA_XML}/${HAPROXY_XML} ]; then
    cmp ${CREDM_DATA_TMP_XML}/${HAPROXY_XML} ${CREDM_DATA_XML}/${HAPROXY_XML} > /dev/null 2>&1
    CMPXMLRESULT=$?
    if [ ${CMPXMLRESULT} -eq 0 ]; then
        info "XML cert request file is actual"
    else
        info "XML cert request file is not actual - certificate should be regenerated with new XML cert request"
    fi
fi

## retrieve certificate if it is not in place or it is not actual
if [ ! -f ${HAPROXYAPACHE_CERT} ] || [ $CMPXMLRESULT -eq 1 ]; then
    ${_CP} ${CREDM_DATA_TMP_XML}/${HAPROXY_XML} ${CREDM_DATA_XML}/${HAPROXY_XML}
    info "Running Credential Manager CLI to retrieve HAProxy certificates"
    $CREDM_LOCATION -b -i -x ${CREDM_DATA_XML}/${HAPROXY_XML}
    if [ ! -f ${HAPROXYAPACHE_CERT} ]; then
        error "Cannot obtain HAProxy certificate ${HAPROXYAPACHE_CERT} from Credential Manager"
    fi
fi

ret_val=`$CONFIGURATION_CHECK` > /dev/null 2>&1

if [ ${?} -eq 0 ]; then
   info "Valid configuration generated"
else
  if [[ "${IS_OLD_CONF_VALID}" == "true" ]]; then
    info "Invalid configuration generated"
    info "Old configuration is valid. Restoring the old configuration, bypassing the changes"
    info "If you want to update configuration, please verify input data correctness at generated configuration ${HAPROXY_OLD_CONFIG}"
    $_MV ${HAPROXY_CFG} ${HAPROXY_CFG}.tmp
    $_MV ${HAPROXY_OLD_CONFIG} ${HAPROXY_CFG}
    $_MV ${HAPROXY_CFG}.tmp ${HAPROXY_OLD_CONFIG}
  else
    error "Invalid configuration generated, exiting"
    exit 1
  fi
fi

info "Successfully updated configuration of haproxy-ext"
exit 0
