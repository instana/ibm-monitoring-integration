#!/bin/sh
#-----------------------------------------------------------------------
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corporation 2015 - 2018. 
#
# US Government Users Restricted Rights - Use, duplication or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corporation.
#-----------------------------------------------------------------------

#set -x
if [ "$1" = "real-call" ];then
	shift
	#echo "param: $@"
else
	interpreter=$(command -v bash 2>/dev/null) ||
	interpreter=$(echo $SHELL | grep bash) || 
	interpreter=$(command -v ksh 2>/dev/null) ||
	interpreter=$(echo $SHELL | grep ksh) || 
	interpreter=$(command -v sh 2>/dev/null) ||
	interpreter=$(echo $SHELL | grep /sh)  

	if [ -z "$interpreter" ];then
		( ls -l /bin/sh | grep bash >/dev/null 2>&1 || 
		  ls -l /bin/sh | grep ksh >/dev/null 2>&1 || 
		  test -f /bin/sh -a ! -L /bin/sh 2>/dev/null ) && interpreter="/bin/sh"
	fi

	if [ -n "$interpreter" ];then
	# getopts can only handle single char paramter.
		enable_cp4mcm_hist=$(echo "$@" | grep "enable-cp4mcm-hist" 2>/dev/null )
		if [ -n "$enable_cp4mcm_hist" ];then
			for para in $@ ; do
				if [ "$para" = "-enable-cp4mcm-hist" -o "$para" = "enable-cp4mcm-hist" ];then
					para="-n"
				fi
				paras="$paras $para"
			done
		else
			paras="$@"
		fi
		echo "Going to run $interpreter $0 $paras"
	    exec "$interpreter" "$0" real-call $paras
	    ## exec return 
	else
		echo "Can't find a shell interpreter bash,ksh or sh to run."
		exit 1
	fi
fi

CMD=`basename $0`
CDIR=$(cd $(dirname "$0"); pwd -P)

print_usage() {
	PROGRAME=`basename "$0"`
	echo "Usage: $PROGRAME -i <ITMhome> [-c <instana|itm|dual> ] [-e <env.properties> ] [-p product or products] [-j <sda_support_dirs>] [-r] [-m]"
	echo "-c: connection modes. valid values are instana, itm and dual. The default is instana."
	echo "-e: the path to the file that contains all required server properties. By default, it is env.properties in the same directory of the agent2server_itm script."
	echo "-i: agent install directory (ITMhome)"
	echo "-j: SDA jar support directories for custom agents. Format: \"pc1=path1,pc2=path2\""
	echo "    where path is the custom agent installation support directory containing the SDA jar file"
	echo "    Example: -j \"11=/tmp/k11/support\""
	echo "-m: display current connection mode"
	echo "-p: agent type pc list delimited by space. for example: \"lz mq\""
	echo "-r: revert to ITM"
}

addlog() {
  echo "`date +%Y%m%d-%H%M%S` $1: $2" >> $LOG_FILE
}

log_info() {
  addlog "INFO" "$1"
}

log_err() {
  addlog "ERROR" "$1"
}

log_warn() {
  addlog "WARN" "$1"
}

log_cmd() {
  log_info "Executing command $1"
  eval "$1" >> $LOG_FILE 2>&1
  rc=$?
  log_info "Return code is $rc"
  return $rc
}

log_display_cmd() {
  log_info "Executing command $1"
  eval "$1" | tee -a $LOG_FILE
  rc=$?
  log_info "Return code is $rc"
  return $rc
}

validate_itmhome() {

	if [ ! $1 ]; then
		echo "Specify agent install directory with option i"
		log_err "Specify agent install directory with option i"
		print_usage
		exit 1
	fi
	
	if [ ! -e $1/bin/cinfo ]; then
		echo "check your agent installation directory and retry."
		log_err "check your agent installation directory and retry."
		exit 1
	fi
}

prereq_check() {
	
	log_info "Enter prereq_check"
	
	if [ "$PROTOCOL" = "https" ]; then
		prereqaxver="06300708"
	elif [ "$PROTOCOL" = "http" ]; then
		prereqaxver="06300703"	
	fi

	LANG=C
	axversions=`$1/bin/cinfo -d | grep ax  | awk -F, '{print $3","$4}' | tr -d '"' `
	for x in ${axversions}; do
		arch=`echo "$x" | cut -f 1 -d ','`
		axver=`echo "$x" | cut -f 2 -d ','`

		count=`grep $arch $CANDLEHOME/registry/archdsc.tbl | grep "32 bit" | wc -l`
		[ $count -eq 1 ] && INSTALLED_TEMA_VER_32=$axver

		count=`grep $arch $CANDLEHOME/registry/archdsc.tbl | grep "64 bit" | wc -l`
		[ $count -eq 1 ] && INSTALLED_TEMA_VER_64=$axver

		if [ "$axver" -lt "$prereqaxver" -a ${IS_REVERT_TO_CMS} -eq 0 ]; then
			printf "update your TEMA framework(ax) to version $prereqaxver or later.
06300703 or later is required to connect to the Cloud App Management server over HTTP.
06300708 or later is required to connect to the Cloud App Management serer over HTTPS.\n "
			
			log_err "update your TEMA framework(ax) to version $prereqaxver or later.
06300703 or later is required to connect to the Cloud App Management server over HTTP.
06300708 or later is required to connect to the Cloud App Management serer over HTTPS.\n"
			exit 1
		fi
	done

	if [ ! -z "$INSTALLED_TEMA_VER_32" ]; then
		log_info "32 bit tema is $INSTALLED_TEMA_VER_32"
	fi

	if [ ! -z "$INSTALLED_TEMA_VER_64" ]; then
		log_info "64 bit tema is $INSTALLED_TEMA_VER_64"
	fi

# 637 if9 is required for dual mode private situation
	verIF9="06300709"
	isUpIF9="no"
	if [ -n "$INSTALLED_TEMA_VER_32" -a -n "$INSTALLED_TEMA_VER_64" ];then
		if [ "$INSTALLED_TEMA_VER_32" -ge "$verIF9" -a "$INSTALLED_TEMA_VER_64" -ge "$verIF9" ];then
			isUpIF9="yes"
		elif [ "$INSTALLED_TEMA_VER_32" -lt "$verIF9" -a "$INSTALLED_TEMA_VER_64" -lt "$verIF9" ];then
			isUpIF9="no"
		else
			if [ ${IS_REVERT_TO_CMS} -eq 0 ];then
				echo "Warning:" 
				echo "Found mixed 32-bit/64-bit TEMA framework(ax) versions. If you need to enable Private situations, \
Private Historical data, and Centralized Configuration for Cloud App Management server and Tivoli Enterprise Monitoring \
Server(TEMS) simultaneously, upgrade both 32-bit and 64-bit TEMA to 06300709 or later."
	        	echo "  "
	        fi
			isUpIF9="no"
		fi
	elif [ -n "$INSTALLED_TEMA_VER_64" ]; then
		[ "$INSTALLED_TEMA_VER_64" -ge "$verIF9" ] && isUpIF9="yes"
	elif [ -n "$INSTALLED_TEMA_VER_32" ];then
		[ "$INSTALLED_TEMA_VER_32" -ge "$verIF9" ] && isUpIF9="yes"
	fi

	log_info "Exit prereq_check (OK)"
}

validate_connection_modes() {
	
	connection=$1
	case $connection in
		dual|icam|itm)
			echo "yes"
			;;
		*)
			echo "no"
			;;
	esac;

}

valid_args() {
	case $1 in
		 c)
		 	ret=`validate_connection_modes $2`
		 	if [ "$ret" = "no"  ]; then
				echo "unexpected connection mode '$2'. Exit."
				exit 1
			fi
		 	;;
         s)
			echo $2 | grep '^[0-9]\{1,3\}.[0-9]\{1,3\}.[0-9]\{1,3\}.[0-9]\{1,3\}$'
			if [ $? -eq 0 ]; then
			  echo "IP address is not supported. Server name must be full hostname in FQDN."
			  exit 1
			fi
			;;
		 p)
			for x in `echo $2`; do
				is_supported=`is_supported_agent ${x}`
				if [ "$is_supported" = "no" ]; then
					echo "agent product code ${x} is not supported."
					exit 1
				fi	 
			done
			;;	
		 *)
			exit 1
			;;
    esac;
}

# Get architecture code in ITM/APM format.
get_binary_arch() {
   log_info "Enter get_binary_arch($1)"
   pc=$1
   arch=`${CANDLEHOME}/bin/cinfo -d | grep Agent | grep $pc | awk -F, '{print $3}' | tr -d '"'`
   echo ${arch}
   log_info "Exit get_binary_arch($arch)"
}


format_hostname () {
	full_hostname=$1
	var_formatted=`echo "$full_hostname" | tr [a-z] [A-Z] | sed 's/[^a-zA-Z0-9]/_/g' | tr -s [_] '_'`
	echo $var_formatted
}

# not in use for now
create_default_envfiles() {
	log_info "Enter create_default_envfiles($1)"
	pc=$1
		
	FILE=${CANDLEHOME}/config/${x}.ibm_environment
	echo "CANDLEHOME=\${CANDLEHOME}" > ${FILE}
	_arch=`get_binary_arch ${pc}`
	echo "BINARCH="${_arch} >> ${FILE}
	echo "PRODUCTCODE="$1 >> ${FILE}
	echo "IRA_ASF_SERVER_TIMEOUT=30" >> ${FILE}
	echo "IRA_ASF_SERVER_HEARTBEAT=60" >> ${FILE}
	echo "IRA_ASF_SERVER_MAX_CACHE_PERIOD=60" >> ${FILE}
	echo "KDEB_LISTEN_QUEUE_DEPTH=128" >> ${FILE}
	echo "IRA_ASF_SERVER_URL=$PROTOCOL://#server_hostname#:$PORT/ccm/asf/request" >> ${FILE}
	echo "IRA_API_DATA_BROKER_URL=$PROTOCOL://#server_hostname#:$PORT/1.0/monitoring/data" >> ${FILE}
	echo "IRA_API_TENANT_ID=#tenant_id#" >> ${FILE}
	echo "IRA_API_DATA_ZLIB_COMPRESSION=Y" >> ${FILE}
	#echo "ITM_AUTHENTICATE_SERVER_CERTIFICATE=N" >> ${FILE}
	echo "TEMA_SDA=Y" >> ${FILE}
	echo "KBB_SHOW_NFS=false" >> ${FILE}
	echo "DNS_CACHE_REFRESH_INTERVAL=1" >> ${FILE}

	if [ "$PROTOCOL" = "https" ]; then
		echo "GSK_SSL_EXTN_SERVERNAME_REQUEST=#server_hostname#" >> ${FILE}
		echo "KEYFILE_DIR=\${CANDLEHOME}/keyfiles" >> ${FILE}
		echo "GSK_KEYRING_FILE=\${CANDLEHOME}/keyfiles/keyfile.kdb" >> ${FILE}
		echo "GSK_KEYRING_STASH=\${CANDLEHOME}/keyfiles/keyfile.sth" >> ${FILE}
		echo "GSK_KEYRING_LABEL=IBM_Tivoli_Monitoring_Certificate" >> ${FILE}
	fi
	log_info "Exit create_default_envfiles (OK)"
}

is_supported_agent() {

	# Always supported for Instana
	log_info "Enter is_supported_agent($1)"
	pc=$1
	supported="yes"

	echo $supported
	log_info "Exit is_supported_agent($supported)"
}

get_config_status() {

	log_info "Enter get_config_status"

	# check whether or not all supported agents have ever been configured with valid server and tenantId
	status="yes"
	installed_agent_list=`${CANDLEHOME}/bin/cinfo -i | grep Agent | cut -f1`
	for x in ${installed_agent_list}; do	
		is_supported=`is_supported_agent ${x}`
		is_inlist=`is_in_desired_list ${x}`
		if [ "$is_supported" = "yes" -a "$is_inlist" = "yes" ]; then
		
			if [ -f "${CANDLEHOME}/config/${x}.environment" ]; then 	
				old_server=`grep ^IRA_ASF_SERVER_URL "${CANDLEHOME}/config/${x}.environment" 2>/dev/null | cut -f 3 -d '/' | cut -f 1 -d ':'`
				old_tenantid=`grep ^IRA_API_TENANT_ID "${CANDLEHOME}/config/${x}.environment" 2>/dev/null | cut -f 2 -d '='`
				
				if [ "$old_server" = "" -o "$old_server" = "#server_hostname#" ]; then
					status="no"
				fi
				
				if [ "$old_tenantid" = "" -o "$old_tenantid" = "#tenant_id#" ]; then
					status="no"
				fi
			else
				status="no"
			fi
			
			if [ "$status" = "no" ]; then
				break
			fi
		fi		
	done
	echo $status
	log_info "Exit get_config_status ($status)"
}

is_in_desired_list() {

   log_info "Enter is_in_desired_list($1)"
   pc=$1
   status="no"
   log_info "AGENT_PRODUCTCODE_LIST=$AGENT_PRODUCTCODE_LIST, pc=$pc"
   if [ "${AGENT_PRODUCTCODE_LIST}" ]; then
   	   # printf does not output \n on solaris so we can't use wc -l
	   count=`printf "${AGENT_PRODUCTCODE_LIST}" | grep -i $pc`
	   if [ -n "$count" ]; then
			status="yes"
		else
			status="no"
		fi
	else
		status="yes" # no -p parameter specified
	fi
	echo $status
	log_info "Exit is_in_desired_list($status)"
}

# not in use for now
init_agent_default_env() {

	log_info "Enter init_agent_default_env"

	# clean old files if there is any
	rm -f ${CANDLEHOME}/config/*.ibm_environment

	# create enviroment files
	log_cmd "${CANDLEHOME}/bin/cinfo -i | grep Agent"
	installed_agent_list=`${CANDLEHOME}/bin/cinfo -i | grep Agent | cut -f1`
	for x in ${installed_agent_list}; do
		is_supported=`is_supported_agent ${x}`
		is_inlist=`is_in_desired_list ${x}`
		if [ "$is_supported" = "yes" -a "$is_inlist" = "yes" ]; then
			if [ -f "${CANDLEHOME}/config/${x}.ibm_environment" ]; then
				# file exists, do nothing
				echo "${x}.ibm_environment exists"
				log_warn "${x}.ibm_environment exists"
			else
				create_default_envfiles ${x}
			fi
		fi
	done
	log_info "Exit init_agent_default_env (OK)"
}

# just use this this to clean legacy xx.ibm_environment
clean_ibm_envfile() {
	pc=$1
	env_ibm_file=${CANDLEHOME}/config/${pc}.ibm_environment
	if [ -f "$env_ibm_file" ];then
		# clean this file only when it is configured by ICAM scripts
		isConfiguredByICAM "$env_ibm_file" || return 0
		#clean xx.ibm_environment
		tmp_file="${CANDLEHOME}/tmp/$CMD.$$"

		_FILTER="^CANDLEHOME= \
				^PRODUCTCOD= \
				^BINARCH= \
				^IRA_ASF_SERVER_TIMEOUT= \
				^IRA_ASF_SERVER_HEARTBEAT= \
				^IRA_ASF_SERVER_MAX_CACHE_PERIOD= \
				^KDEB_LISTEN_QUEUE_DEPTH= \
				^IRA_ASF_SERVER_URL= \
				^IRA_API_DATA_BROKER_URL= \
				^IRA_API_TENANT_ID= \
				^IRA_API_DATA_ZLIB_COMPRESSION= \
				^TEMA_SDA=Y \
				^KBB_SHOW_NFS= \
				^DNS_CACHE_REFRESH_INTERVAL= \
				^KEYFILE_DIR= \
				^GSK_KEYRING_FILE \
				^GSK_KEYRING_STASH \
				^GSK_KEYRING_LABEL \
				^ITM_AUTHENTICATE_SERVER_CERTIFICATE= \
				^GSK_SSL_EXTN_SERVERNAME_REQUEST="

		while read line; do
			line_filter "$line" "$tmp_file"
		done < ${env_ibm_file}

		mv -f $tmp_file ${env_ibm_file}
		others=$(cat $env_ibm_file)
		if [ -z "$others" ];then
			rm -f ${env_ibm_file}
		fi
	fi
}



# not in use for now.
create_envfile() {
	
	log_info "Enter create_envfile($1)"
	pc=$1
	FILE=${CANDLEHOME}/config/${pc}.environment
	echo "IRA_ASF_SERVER_URL=$PROTOCOL://#server_hostname#:$PORT/ccm/asf/request" > ${FILE}
	echo "IRA_API_DATA_BROKER_URL=$PROTOCOL://#server_hostname#:$PORT/1.0/monitoring/data" >> ${FILE}
	echo "IRA_API_TENANT_ID=#tenant_id#" >> ${FILE}
	#echo "ITM_AUTHENTICATE_SERVER_CERTIFICATE=N" >> ${FILE}

 	if [ "$pc" != "lz" -a  "$pc" != "ux" ]; then
 		echo "CT_CMSLIST=" >> ${FILE}
	fi

	if [ "$PROTOCOL" = "https" ]; then
			formatted_server_hostname=`format_hostname $SERVER`	
			echo "IRA_MANAGEMENT_SERVER_HOSTS=$formatted_server_hostname" >> ${FILE}
			echo "GSK_SSL_EXTN_SERVERNAME_REQUEST=#server_hostname#" >> ${FILE}
			echo "GSK_KEYRING_FILE_$formatted_server_hostname=$ICAM_SERVER_KEYFILE_DIR/keyfile.kdb" >> ${FILE}
			echo "GSK_KEYRING_STASH_$formatted_server_hostname=$ICAM_SERVER_KEYFILE_DIR/keyfile.sth" >> ${FILE}
			echo "GSK_KEYRING_LABEL_$formatted_server_hostname=IBM_Tivoli_Monitoring_Certificate" >> ${FILE}
	fi
	log_info "Exit create_envfile(OK)"
}

add_env_var() 
{
	log_info "Enter add_env_var"
    expression="$1"
	file="$2"
	name=`echo $expression | cut -f 1 -d '='`
	oldexpression=`grep $name "$file" 2>/dev/null`
	if [  "$oldexpression" ]; then
		# update existing
		update_file "s\"!$oldexpression!$expression!\"g" "$file"
	else
		eval "echo \"$expression\" >> \"$file\""
	fi
	log_info "Exit add_env_var($?)"
    return $?
}

# this is used to clean env files updated by release 2019.2.0 and earlier.
clean_envfile() {
	pc="$1"
	env_file=${CANDLEHOME}/config/${pc}.environment
	if [ -f "$env_file" ];then
		# clean this file only when it is configured by ICAM scripts
		isConfiguredByICAM "$env_file" || return 0
		tmp_file="${CANDLEHOME}/tmp/$CMD.$$"
		_FILTER="^IRA_ASF_SERVER_URL= \
				^IRA_API_DATA_BROKER_URL= \
				^IRA_API_TENANT_ID= \
				^GSK_KEYRING_FILE \
				^GSK_KEYRING_STASH \
				^GSK_KEYRING_LABEL \
				^GSK_SSL_EXTN_SERVERNAME_REQUEST= \
				^ITM_AUTHENTICATE_SERVER_CERTIFICATE= \
				^IRA_MANAGEMENT_SERVER_HOSTS= \
				^#Cloud_App_Management_settings \
				^CT_CMSLIST=$"

		while read line; do
			line_filter "$line" "$tmp_file"
		done < ${env_file} 
		mv -f $tmp_file $env_file
	fi
}

## use this function instead of grep -e. filter out lines that match _FILTER. mismatched lines will added to _tmp_file
line_filter(){
	__line="$1"
	__tmp_file="$2"
	for loop in $_FILTER
	do
		(echo $__line | grep $loop >/dev/null) && return 1
	done
	echo $__line >> $__tmp_file
	return 0
}


isConfiguredByICAM() {
	__testfile="$1"
	grep ^IRA_ASF_SERVER_URL "$__testfile" >/dev/null 2>&1 && \
	grep ^IRA_API_DATA_BROKER_URL "$__testfile" >/dev/null 2>&1 && \
	grep ^IRA_API_TENANT_ID "$__testfile" >/dev/null 2>&1 && return 0
	log_info "isConfiguredByICAM return false for $__testfile"
	return 1
}

# this is used to clean env file since release-2019.2.1
clean_envfile_v2() {
	log_info "Enter clean_envfile_v2"
	pc=$1
	# 0 before , 1 in , 2 after 
	state=0
	envfile=${CANDLEHOME}/config/${pc}.environment
	if [ ! -f $envfile ];then
		return 0
	fi
	tmp_file="${CANDLEHOME}/tmp/$CMD.$$"
	/bin/rm -f $tmp_file

	_FILTER="$icam_2nd_comment \
			^IRA_ASF_SERVER_URL= \
	        ^IRA_API_DATA_BROKER_URL= \
	        ^IRA_API_TENANT_ID= \
	        ^GSK_KEYRING_FILE \
	        ^GSK_KEYRING_STASH \
	        ^GSK_KEYRING_LABEL \
	        ^GSK_SSL_EXTN_SERVERNAME_REQUEST= \
	        ^ITM_AUTHENTICATE_SERVER_CERTIFICATE= \
	        ^IRA_MANAGEMENT_SERVER_HOSTS= \
	        ^#Cloud_App_Management_settings \
	        ^CT_CMSLIST=$ \
	        ^CANDLEHOME= \
			^PRODUCTCODE= \
			^BINARCH= \
			^IRA_ASF_SERVER_TIMEOUT= \
			^IRA_ASF_SERVER_HEARTBEAT= \
			^IRA_ASF_SERVER_MAX_CACHE_PERIOD= \
			^KDEB_LISTEN_QUEUE_DEPTH= \
			^IRA_API_DATA_ZLIB_COMPRESSION= \
			^IRA_V8_LOCALCONFIG_DIR= \
			^LOAD_PRIVATE_SITUATIONS_FROM_ICAM= \
			^DNS_CACHE_REFRESH_INTERVAL= \
			^START_PVTHIST_SITUATIONS="

	while read line; do
		#echo "clean line=$line, state=$state"
		if [ $state -eq 0 ];then
			if echo "$line" | grep "$icam_begin_comment" >/dev/null 2>&1 ;then
				state=1
			fi
			echo $line >> $tmp_file
		elif [ $state -eq 1 ];then
			if echo "$line" | grep "$icam_end_comment" >/dev/null 2>&1;then
				state=2
				echo "$icam_end_comment" >> $tmp_file
			else
				line_filter "$line" "$tmp_file"
			fi
		elif [ $state -eq 2 ];then
			echo $line >> $tmp_file
		fi
	done < $envfile
	mv -f $tmp_file $envfile
	log_info "Exit clean_envfilev_v2"
}

append_envfile() {
	tmp_file=$1
	pc=$2
	#log_cmd "grep -e ^IRA_ASF_SERVER_URL -e ^IRA_API_DATA_BROKER_URL ${CANDLEHOME}/config/${pc}.environment | sed 's/$old_protocol:\/\/$old_server:$old_port/$PROTOCOL:\/\/$SERVER:$PORT/g'  >> $tmp_file"
	#log_cmd "grep -e ^IRA_API_TENANT_ID ${CANDLEHOME}/config/${pc}.environment | sed s/$old_tenantid/$TENANTID/g >> $tmp_file"
	echo "$icam_2nd_comment" >> "$tmp_file"
	echo "IRA_ASF_SERVER_URL=${PROTOCOL}://${SERVER}:${PORT}/${SENSOR}/ccm/asf/request" >> "$tmp_file"
	echo "IRA_API_DATA_BROKER_URL=${PROTOCOL}://${SERVER}:${PORT}/${SENSOR}/1.0/monitoring/data" >> "$tmp_file"
	echo "IRA_API_TENANT_ID=$TENANTID" >> "$tmp_file"

	if [ "$PROTOCOL" = "https" ]; then
		formatted_server_hostname=`format_hostname $SERVER`
		echo "GSK_SSL_EXTN_SERVERNAME_REQUEST=$SERVER" >> "$tmp_file"
		echo "IRA_MANAGEMENT_SERVER_HOSTS=$formatted_server_hostname" >> "$tmp_file"
		#update_file "/GSK_KEYRING_FILE_*/d" "$tmp_file"
		echo "GSK_KEYRING_FILE_$formatted_server_hostname=$ICAM_SERVER_KEYFILE_DIR/keyfile.kdb" >> "$tmp_file"
		#update_file "/GSK_KEYRING_STASH_*/d" "$tmp_file"
		echo "GSK_KEYRING_STASH_$formatted_server_hostname=$ICAM_SERVER_KEYFILE_DIR/keyfile.sth" >> "$tmp_file"
		#update_file "/GSK_KEYRING_LABEL_*/d" "$tmp_file"
		echo "GSK_KEYRING_LABEL_$formatted_server_hostname=IBM_Tivoli_Monitoring_Certificate" >> "$tmp_file"
		if [ "$CONNECTION_MODE" = "icam" -a "$pc" != "lz" -a  "$pc" != "ux" ];then
			echo "ITM_AUTHENTICATE_SERVER_CERTIFICATE=Y" >> "$tmp_file"
		fi
	fi

	if [ "$CONNECTION_MODE" = "icam" -a "$pc" != "lz" -a  "$pc" != "ux" ]; then
		echo "CT_CMSLIST=" >> $tmp_file
	fi

	if [ "$isUpIF9" = "yes" ];then
		echo "IRA_V8_LOCALCONFIG_DIR=${LOCALCONFIG_DIR}/${pc}_icam" >> "$tmp_file"
		if [ "$CONNECTION_MODE" = "icam" ];then
			echo "LOAD_PRIVATE_SITUATIONS_FROM_ICAM=Y" >> "$tmp_file"
		fi
	fi

	# following are necessary for efficient ICAM server communication.
	echo "CANDLEHOME=\${CANDLEHOME}" >> ${tmp_file}
	_arch=`get_binary_arch ${pc}`
	echo "BINARCH="${_arch} >> ${tmp_file}
	echo "PRODUCTCODE="$pc >> ${tmp_file}
	echo "IRA_ASF_SERVER_TIMEOUT=30" >> ${tmp_file}
	echo "IRA_ASF_SERVER_HEARTBEAT=60" >> ${tmp_file}
	echo "IRA_ASF_SERVER_MAX_CACHE_PERIOD=60" >> ${tmp_file}
	echo "KDEB_LISTEN_QUEUE_DEPTH=128" >> ${tmp_file}
	echo "IRA_API_DATA_ZLIB_COMPRESSION=Y" >> ${tmp_file}
	#echo "TEMA_SDA=Y" >> ${tmp_file}
	#echo "KBB_SHOW_NFS=false" >> ${tmp_file}
	echo "DNS_CACHE_REFRESH_INTERVAL=1" >> ${tmp_file}
	if [ ${ENABLE_CP4MCM_HIST} -eq 1 ];then
		echo "START_PVTHIST_SITUATIONS=YES" >> ${tmp_file}
	else
		echo "START_PVTHIST_SITUATIONS=NO" >> ${tmp_file}
	fi
}

update_envfile() {
	
	log_info "Enter update_envfile($1)"
	pc=$1
	env_file="${CANDLEHOME}/config/${pc}.environment"

	icam_comment="no"
	if [ ! -f  "$env_file" ]; then
		touch $env_file
	else 
		if grep "$icam_begin_comment" $env_file >/dev/null 2>&1;then
			clean_envfile_v2 $pc
			icam_comment="yes"
		else
			clean_envfile $pc 
			clean_ibm_envfile $pc
		fi
	fi
	
	#old_protocol=`grep ^IRA_ASF_SERVER_URL "${CANDLEHOME}/config/${pc}.environment" 2>/dev/null | cut -f 2 -d '=' | cut -f 1 -d ':'`
	#old_server=`grep ^IRA_ASF_SERVER_URL "${CANDLEHOME}/config/${pc}.environment" 2>/dev/null | cut -f 3 -d '/' | cut -f 1 -d ':'`
	#old_port=`grep ^IRA_ASF_SERVER_URL "${CANDLEHOME}/config/${pc}.environment" 2>/dev/null | cut -f 3 -d '/' | cut -f 2 -d ':'`
	#old_tenantid=`grep ^IRA_API_TENANT_ID "${CANDLEHOME}/config/${pc}.environment" 2>/dev/null | cut -f 2 -d '='`
	if [ "$icam_comment" = "yes" ];then
		# 0 not append, 1 after end comment
		state=0
		tmp_file="${CANDLEHOME}/tmp/$CMD.$$"
		/bin/rm -f $tmp_file
		tmp_file2="${CANDLEHOME}/tmp/$CMD.$$_2"
		/bin/rm -f $tmp_file2
		grep -v "^${icam_end_comment}" $env_file > $tmp_file2
		while read line; do
			echo "$line" >> $tmp_file
			if [ $state -eq 0 ];then
				if echo "$line" | grep "$icam_begin_comment" >/dev/null 2>&1 ;then
					append_envfile "$tmp_file" $pc 
					echo "$icam_end_comment" >> $tmp_file
					state=1
				fi
			fi
		done < $tmp_file2
		/bin/rm -f $tmp_file2
		mv -f $tmp_file $env_file
	else
		# if no ICAM comment, add new directly
		echo "$icam_begin_comment" >> $env_file
		append_envfile $env_file $pc
		echo "$icam_end_comment" >> $env_file
	fi

	#set_connection_mode $pc $CONNECTION_MODE

	log_info "Exit update_envfile(OK)"
}

# not use anymore
remove_all_apm_config() {
	log_info "Enter remove_all_apm_config"
	config_dir=$1/config
	find "${config_dir}" -name "*environment" -print -exec /bin/rm {} \;
	log_info "Exit remove_all_apm_config(OK)"
}

# Remove <install_dir/localconfig files
#
flush_localconfig() {
	log_info "Enter flush_localconfig"
	for x in $CONFIGURED_PC_LIST; do
    	#removed_files=`find "${LOCALCONFIG_DIR}"/[a-z0-9][a-z0-9]/ -name "*.xml" -print -exec /bin/rm -f {} \;`
    	removed_files=`find "${LOCALCONFIG_DIR}"/${x}/ -name "*.xml" -print -exec /bin/rm -f {} \;`
		log_info "$removed_files"
    	#removed_files=`find "${LOCALCONFIG_DIR}"/[a-z0-9][a-z0-9]/ -name "*.csh" -print -exec /bin/rm -f {} \;`
    	removed_files=`find "${LOCALCONFIG_DIR}"/${x}/ -name "*.csh" -print -exec /bin/rm -f {} \;`
		log_info "$removed_files"
	done
	log_info "Exit flush_localconfig(OK)"
}

handle_localconfig() {
	if [ "$isUpIF9" = "yes" ];then
		# ifix9 do not use v6backup anymore
		restore_localconfig
		for x in $CONFIGURED_PC_LIST; do
			rm -rf ${LOCALCONFIG_DIR}/${x}_icam
			#mkdir -p ${LOCALCONFIG_DIR}/${x}_icam
			#chmod ugo+rwx ${LOCALCONFIG_DIR}/${x}_icam
			if [ "$(uname)" = "AIX" -o "$(uname)" = "SunOS" ]; then
				 log_cmd "cp -Rp ${LOCALCONFIG_DIR}/${x} ${LOCALCONFIG_DIR}/${x}_icam"
			else
				 log_cmd "cp -Ra ${LOCALCONFIG_DIR}/${x} ${LOCALCONFIG_DIR}/${x}_icam"
			fi
			log_cmd "rm -rf ${LOCALCONFIG_DIR}/${x}_icam/*"
		done
	else
		backup_localconfig
		flush_localconfig
	fi
}

handle_rollback_localconfig() {
	# always try to remove xx_icam
	for x in $CONFIGURED_PC_LIST; do
		rm -rf ${LOCALCONFIG_DIR}/${x}_icam 
	done
	restore_localconfig
}

make_keyfilesforicam() {

	log_info "Enter make_keyfilesforicam"

	# Restore backed up keyfiles_itm if exists to keyfiles 
	# keyfiles_itm directory can only exists with 2018.4.1 
	if [ -d "$ITM_SERVER_KEYFILE_BACKUP_DIR" ]; then
		log_cmd "rm -rf \"$CANDLEHOME/keyfiles\""
		log_cmd "mv \"$ITM_SERVER_KEYFILE_BACKUP_DIR\" \"$CANDLEHOME/keyfiles\""
	fi

	# making icam keyfiles but not touch the orignal keyfiles under Candlehome
	SRC_KEYFILEDIR=$1
	if [ ! -d "$ICAM_SERVER_KEYFILE_DIR" ]; then
		#mkdir $ICAM_SERVER_KEYFILE_DIR
		#chmod ugo+rwx $ICAM_SERVER_KEYFILE_DIR
		if [ "$(uname)" = "AIX" -o "$(uname)" = "SunOS" ]; then
			log_cmd "cp -Rp $CANDLEHOME/keyfiles $ICAM_SERVER_KEYFILE_DIR"
		else
			log_cmd "cp -Ra $CANDLEHOME/keyfiles $ICAM_SERVER_KEYFILE_DIR"
		fi
		log_cmd "rm -rf $ICAM_SERVER_KEYFILE_DIR/*"
	fi

	if [ -d "${SRC_KEYFILEDIR}" ]; then
			log_cmd "rm -f $ICAM_SERVER_KEYFILE_DIR/*"
			log_cmd "cp $CANDLEHOME/keyfiles/KAES256.ser $ICAM_SERVER_KEYFILE_DIR/"
			log_cmd "cp $SRC_KEYFILEDIR/* $ICAM_SERVER_KEYFILE_DIR/"
			log_cmd "chmod ugo+rwx $ICAM_SERVER_KEYFILE_DIR/*"
	fi
	log_info "Exit make_keyfilesforicam(OK)"
}

restore_keyfiles() {
	log_info "Enter restore_keyfiles"
	if [ -d "$ITM_SERVER_KEYFILE_BACKUP_DIR" ]; then
		log_cmd "rm -rf \"$CANDLEHOME/keyfiles\""
		log_cmd "mv \"$ITM_SERVER_KEYFILE_BACKUP_DIR\" \"$CANDLEHOME/keyfiles\""
	fi
	# can't remove keyfiles_icam since it may be used by other agents.
	#if [ -d "$ICAM_SERVER_KEYFILE_DIR" ]; then
	#	log_cmd "rm -rf \"$ICAM_SERVER_KEYFILE_DIR\""
	#fi

	log_info "Exit restore_keyfiles(OK)"
}

restore_localconfig() {
	log_info "Enter restore_localconfig"
	#for x in `ls $LOCALCONFIG_DIR | grep ^[a-z0-9][a-z0-9]$`; do
	for x in $CONFIGURED_PC_LIST; do
		if [ -d "$LOCALCONFIG_DIR/${x}_v6backup" ]; then
			log_cmd "rm -rf \"$LOCALCONFIG_DIR/${x}\""
			log_cmd "mv \"$LOCALCONFIG_DIR/${x}_v6backup\" \"$LOCALCONFIG_DIR/${x}\""
		fi
	done
	log_info "Exit restore_localconfig(OK)"
}

backup_localconfig() {

	log_info "Enter backup_localconfig"
	if [ ${IS_REVERT_TO_CMS} -eq 0 ];then
		warning_check=$(find "$LOCALCONFIG_DIR" -name *_cnfglist.xml -o -name *_situations.xml)
		if [ -n "$warning_check" -a "$CONNECTION_MODE" = "dual" -a "$isUpIF9" = "no" ];then
	        echo "Warning:" 
	        echo "Agents are configured to connect to the Instana host agent and the Tivoli Enterprise Monitoring \
Server (TEMS) simultaneously. Any existing configuration files for Private situations and Central Configuration server that \
are configured for IBM Tivoli Monitoring are backed up and replaced by those files that are downloaded from the Instana \
host agent."
	        echo "Therefore, Private situations, Private Historical data, and Central Configuration server files that are \
configured in IBM Tivoli Monitoring are NOT available in dual mode."
	        echo "  "
		fi
	fi
	# backup localconfig by product code once
	for x in $CONFIGURED_PC_LIST; do
		if [ ! -d "$LOCALCONFIG_DIR/${x}_v6backup" ]; then
			if [ "$(uname)" = "AIX" -o "$(uname)" = "SunOS" ]; then
				log_cmd "cp -Rp \"$LOCALCONFIG_DIR/${x}\" \"$LOCALCONFIG_DIR/${x}_v6backup\""
			else # "Linux"
				log_cmd "cp -Ra \"$LOCALCONFIG_DIR/${x}\" \"$LOCALCONFIG_DIR/${x}_v6backup\""
			fi	
			log_cmd "rm -rf \"$LOCALCONFIG_DIR/${x}/*\""
		fi
	done
	log_info "Exit backup_localconfig(OK)"
}

read_envproperties() {
	log_info "Enter read_envproperties"
	if [ -f "$ENVPROPFILE" ]; then
		SERVER=`grep ^hostname "$ENVPROPFILE" 2>/dev/null | cut -f 2 -d '='`
		log_info "SERVER=$SERVER"
		valid_args "s" $SERVER
		TENANTID=`grep ^tenantid "$ENVPROPFILE" 2>/dev/null | cut -f 2 -d '='`
		log_info "TENANTID=$TENANTID"
		PORT=`grep ^port "$ENVPROPFILE" 2>/dev/null | cut -f 2 -d '='`
		log_info "PORT=$PORT"
		PROTOCOL=`grep ^protocol "$ENVPROPFILE" 2>/dev/null | cut -f 2 -d '='`
		log_info "PROTOCOL=$PROTOCOL"

	else
		echo "$ENVPROPFILE not exist."
		log_warn "$ENVPROPFILE not exist."
		exit 1
    fi
	log_info "Exit read_envproperties(OK)"
}

undo_additional_config() { 
	log_info "Enter undo_additional_config"
	if [ -f "$CANDLEHOME/./config/.ConfigData/kmqenv" ]; then
		# remove lines with INSTANCE
		if [ "$(uname)" = "AIX" ]; then
			kmqenv_tmp=$CANDLEHOME/./config/.ConfigData/kmqenv_$$_tmp
			cp -p $CANDLEHOME/./config/.ConfigData/kmqenv $kmqenv_tmp
			sed '/|INSTANCE|/d' $CANDLEHOME/./config/.ConfigData/kmqenv > $kmqenv_tmp
			if [ $? -eq 0 ]; then
				cp -p $kmqenv_tmp $CANDLEHOME/./config/.ConfigData/kmqenv
			fi
			rm $kmqenv_tmp
		else #Linux
			sed -i '/|INSTANCE|/d' $CANDLEHOME/./config/.ConfigData/kmqenv
		fi
	fi
	
	if [ -f "$CANDLEHOME/config/mq.ini" ]; then
		if [ "$(uname)" = "AIX" ]; then
			mqini_tmp=$CANDLEHOME/config/mqini_$$_tmp
			cp -p $CANDLEHOME/config/mq.ini $mqini_tmp
			sed '/IBM Cloud App Management Specific settings/d' $CANDLEHOME/config/mq.ini > $mqini_tmp
			cp -p $mqini_tmp $CANDLEHOME/config/mq.ini 
			sed '/INSTANCE=\$INSTANCE\$/d' $CANDLEHOME/config/mq.ini > $mqini_tmp
			cp -p $mqini_tmp $CANDLEHOME/config/mq.ini 
			rm $mqini_tmp
		else # "Linux"
			sed -i '/IBM Cloud App Management Specific settings/d' $CANDLEHOME/config/mq.ini
			sed -i '/INSTANCE=\$INSTANCE\$/d' $CANDLEHOME/config/mq.ini
		fi
	fi
	log_info "Exit undo_additional_config"
}

do_additional_config() { 
	log_info "Enter do_additional_config"
	# short term solution for github issue 3958
	count=`printf "${CONFIGURED_PC_LIST}" | grep -i mq`
	if [ -n "$count" ]; then
		# mq agent is installed
		
		# update mq.ini
		kmqenv_tmp=$CANDLEHOME/./config/.ConfigData/kmqenv_$$_tmp
		count=`grep -c "INSTANCE=" $CANDLEHOME/config/mq.ini`
		if [ -n "$count" ];then
			if [ "$count" -eq 0 ]; then
				echo "# IBM Cloud App Management Specific settings" >> $CANDLEHOME/config/mq.ini
				echo "INSTANCE=\$INSTANCE\$" >> $CANDLEHOME/config/mq.ini
			fi
		fi
		
		cp $CANDLEHOME/./config/.ConfigData/kmqenv $kmqenv_tmp
		grep "RUNNINGHOSTNAME" $kmqenv_tmp | while read line
		# update kmqenv
		do
			instancename=`echo $line | awk -F\| '{print $1}'`
			if [ "$instancename" = "lx8263" -o "$instancename" = "ls3263" ]; then
				continue
			fi
			
			lineToAppend="$instancename|INSTANCE|$instancename|"		
			count=`grep -c "${lineToAppend}" $kmqenv_tmp`
			if [ -n "$count" ];then
				if [ "$count" -eq 0 ]; then
					echo "$lineToAppend" >> $kmqenv_tmp
					log_info "Appended $lineToAppend"
				fi
			fi
		done
		
		cp $kmqenv_tmp $CANDLEHOME/./config/.ConfigData/kmqenv
		rm $kmqenv_tmp
	fi
	log_info "Exit do_additional_config"
}

envfile_exist() {
	pc=$1
	if [ -f "$CANDLEHOME/config/$pc.environment" ]; then
		return 1
	else
		return 0
	fi
}

# Validate and parse SDA support directories
# Format: "pc1=path1,pc2=path2"
validate_sda_support_dirs() {
	log_info "Enter validate_sda_support_dirs"
	if [ -z "$SDA_SUPPORT_DIRS" ]; then
		log_info "No SDA support directories specified"
		return 0
	fi
	
	# Parse comma-separated mappings
	IFS=',' read -ra MAPPINGS <<< "$SDA_SUPPORT_DIRS"
	for mapping in "${MAPPINGS[@]}"; do
		# Check if mapping contains '='
		if [[ ! "$mapping" =~ = ]]; then
			echo "ERROR: Invalid SDA mapping format: $mapping"
			echo "Missing '=' separator. Expected format: productcode=path"
			echo "Example: -j \"11=/tmp/k11/support\""
			log_err "Invalid SDA mapping format (missing =): $mapping"
			exit 1
		fi
		
		pc=$(echo "$mapping" | cut -d'=' -f1 | tr -d ' ')
		support_dir=$(echo "$mapping" | cut -d'=' -f2- | tr -d ' ')
		
		if [ -z "$pc" ] || [ -z "$support_dir" ]; then
			echo "ERROR: Invalid SDA mapping format: $mapping"
			echo "Expected format: productcode=path"
			echo "Example: -j \"11=/tmp/k11/support\""
			log_err "Invalid SDA mapping format: $mapping"
			exit 1
		fi
		
		# Check if support directory exists
		if [ ! -d "$support_dir" ]; then
			echo "ERROR: SDA support directory does not exist for product code $pc"
			echo "Directory: $support_dir"
			log_err "SDA support directory does not exist: $support_dir"
			exit 1
		fi
		
		# Look for SDA jar file with pattern: ${pc}_sda_*.jar or k${pc}_sda_*.jar
		sda_jar=$(ls "$support_dir"/${pc}_sda_*.jar 2>/dev/null | head -1)
		if [ -z "$sda_jar" ]; then
			sda_jar=$(ls "$support_dir"/k${pc}_sda_*.jar 2>/dev/null | head -1)
		fi
		
		if [ -z "$sda_jar" ]; then
			echo "ERROR: SDA jar file not found for product code $pc"
			echo "Expected pattern: ${pc}_sda_*.jar or k${pc}_sda_*.jar"
			echo "In directory: $support_dir"
			log_err "SDA jar file not found in $support_dir for product code $pc"
			exit 1
		fi
		
		log_info "Found SDA jar: $sda_jar for product code $pc"
	done
	
	log_info "Exit validate_sda_support_dirs (OK)"
	return 0
}

# Copy SDA jar file for a specific product code
# $1: product code
copy_sda_jar() {
	log_info "Enter copy_sda_jar($1)"
	pc=$1
	
	if [ -z "$SDA_SUPPORT_DIRS" ]; then
		log_info "No SDA support directories specified, skipping SDA jar copy"
		return 0
	fi
	
	# Parse comma-separated mappings to find this product code
	IFS=',' read -ra MAPPINGS <<< "$SDA_SUPPORT_DIRS"
	for mapping in "${MAPPINGS[@]}"; do
		map_pc=$(echo "$mapping" | cut -d'=' -f1 | tr -d ' ')
		support_dir=$(echo "$mapping" | cut -d'=' -f2- | tr -d ' ')
		
		if [ "$map_pc" = "$pc" ]; then
			# Find the SDA jar file
			sda_jar=$(ls "$support_dir"/${pc}_sda_*.jar 2>/dev/null | head -1)
			if [ -z "$sda_jar" ]; then
				sda_jar=$(ls "$support_dir"/k${pc}_sda_*.jar 2>/dev/null | head -1)
			fi
			
			if [ -n "$sda_jar" ]; then
				# Get the architecture for this product code
				_arch=`get_binary_arch ${pc}`
				target_dir="${CANDLEHOME}/${_arch}/${pc}/support"
				
				if [ ! -d "$target_dir" ]; then
					echo "WARNING: Target support directory does not exist: $target_dir"
					log_warn "Target support directory does not exist: $target_dir"
					return 1
				fi
				
				sda_jar_name=$(basename "$sda_jar")
				echo "Copying SDA jar for product code $pc: $sda_jar_name"
				log_info "Copying $sda_jar to $target_dir/"
				
				cp "$sda_jar" "$target_dir/" 2>&1 | tee -a $LOG_FILE
				if [ $? -eq 0 ]; then
					echo "Successfully copied SDA jar to $target_dir/"
					log_info "Successfully copied SDA jar to $target_dir/"
				else
					echo "ERROR: Failed to copy SDA jar to $target_dir/"
					log_err "Failed to copy SDA jar to $target_dir/"
					exit 1
				fi
			fi
			break
		fi
	done
	
	log_info "Exit copy_sda_jar"
	return 0
}

update_file()
{
	log_info "Enter update_file()."
    log_info "update_file: 1: $1, 2: $2."
    expression="$1"
    file="$2"
    tmp="${file}.$$"
    eval "sed $expression \"$file\" > \"$tmp\""
    log_cmd "mv -f $tmp $file"
	log_info "Exit update_file()."
    return $?
}

enable_conn_itm_only() {

	log_info "Enter enable_conn_itm_only()."

	echo "Switch back to original TEMS for specified agents..."
	log_info "Switch back to original TEMS for specified agents..."

	echo "Removing Instana Host Agent configuration for specified agents..."
	log_info "Removing Instana Host Agent configuration for specified agents..."

	#remove_all_apm_config ${CANDLEHOME}
	INSTALLED_AGENT_LIST=`${CANDLEHOME}/bin/cinfo -i | grep Agent | cut -f1`
	for x in ${INSTALLED_AGENT_LIST}; do
		is_supported=`is_supported_agent ${x}`
		is_inlist=`is_in_desired_list ${x}`
		if [ "$is_supported" = "yes" -a "$is_inlist" = "yes" ]; then
			if grep "$icam_begin_comment" $CANDLEHOME/config/${x}.environment >/dev/null 2>&1;then
				clean_envfile_v2 ${x}
			else
				clean_envfile ${x}
			fi
			clean_ibm_envfile ${x}
			CONFIGURED_PC_LIST="$CONFIGURED_PC_LIST ${x}"
			others=$(grep -v "^${icam_begin_comment}" "^${icam_end_comment}" $CANDLEHOME/config/${x}.environment 2>/dev/null)
			if [ -z "$others" ];then
				rm -f "$CANDLEHOME/config/${x}.environment"
			fi
		fi	
	done
	# roll back twice will remove old v6 xml, don't flush here
	#flush_localconfig   

	echo "Removing Instana Host Agent configuration for specified agents...Done"
	log_info "Removing Instana Host Agent configuration for specified agents...Done"
	stop_all_agents
	handle_rollback_localconfig
	restore_keyfiles
	undo_additional_config
	start_all_agents

	echo "Switch back to original TEMS for specified agents...Done"
	log_info "Switch back to original TEMS for specified agents...Done"
	log_info "Exit enable_conn_itm_only()."
	exit 0
}

enable_conn_icam_only() {

	log_info "Enter enable_conn_icam_only()."
	pc=$1
	if [ "$pc" != "lz" -a  "$pc" != "ux" ]; then
		ENV_FILE=$CANDLEHOME/config/${pc}.environment
		if [ -f "$ENV_FILE" ]; then
			update_file "/CT_CMSLIST/d" "${ENV_FILE}"
			echo "CT_CMSLIST=" >> ${ENV_FILE}
		fi
	fi
	log_info "Exit enable_conn_icam_only()."
}

enable_conn_dual() {
	log_info "Enter enable_conn_dual()."
	pc=$1
	if [ "$pc" != "lz" -a  "$pc" != "ux" ]; then
		ENV_FILE=$CANDLEHOME/config/${pc}.environment
		if [ -f "$ENV_FILE"  ]; then
			update_file "/CT_CMSLIST/d" "${ENV_FILE}"
		fi
	fi
	log_info "Exit enable_conn_dual()."
}

display_current_conn_mode()
{
	log_info "Enter display_current_conn_mode()."
	pclist="$1"
	if [ -z "$pclist" ];then
		echo "option m is specified. Ignore other options."
		log_info "option m is specified. Ignore other options."
		INSTALLED_AGENT_LIST=`${CANDLEHOME}/bin/cinfo -i | grep Agent | cut -f1`
		pclist="$INSTALLED_AGENT_LIST"
	fi
	for pc in ${pclist}; do
		mode="unknown"
		ENV_FILE=$CANDLEHOME/config/${pc}.environment
		if grep "IRA_ASF_SERVER_URL" $ENV_FILE > /dev/null 2>&1 ;then
			count=$(grep '^CT_CMSLIST=$' "$ENV_FILE")
			if [ -n "$count" ]; then
				mode="instana"
			else
				mode="dual"	
			fi
		else
			mode="itm"
		fi
		echo "$pc is configured in $mode mode"
	done
	log_info "Exit display_current_conn_mode()."
}

# not used for now
set_connection_mode() {

	pc=$1
	conn_mode=$2
	case $conn_mode in
		dual)
			enable_conn_dual $pc
			;;
		itm)
			enable_conn_itm_only $pc
			;;
		icam)
			enable_conn_icam_only $pc
			;;
		*)
			echo "unexpected connection mode $conn_mode for $pc"
			log_info "unexpected connection mode $conn_mode for $pc"
			exit 1
			;;
	esac;
	echo "set connection mode $conn_mode for $pc"
	log_info "set connection mode $conn_mode for $pc"
}

start_all_agents() {

	log_info "Enter start_all_agents"
	if [ -f "$SHELL_START_ALL_AGENTS" ]; then
		log_display_cmd "$SHELL_START_ALL_AGENTS"
		log_cmd "rm -f \"$SHELL_START_ALL_AGENTS\""
	fi
	log_info "Exit start_all_agents(OK)"
}

stop_all_agents() {

	log_info "Enter stop_all_agents"
  	_rc=0
  	
	su_value=`which su` 2> /dev/null
	[ -f "$su_value" ] || su_value="su"

	# following agents are running
    echo "Restarting agents if any is running...."
	log_info "Restarting agents if any is running...."
    # restarting all running agents
    log_display_cmd "${CANDLEHOME}/bin/cinfo -R"
	
    # restarting running agents
	id_cmd="id"
	thisRealUser=$(${id_cmd} -unr);
	
	echo "#!/bin/sh" > $SHELL_START_ALL_AGENTS
	chmod 755 $SHELL_START_ALL_AGENTS
	
    LANG=C ${CANDLEHOME}/bin/cinfo -R | grep running | while read line
    do 	
		
        pc=`echo $line | cut -f2 -d" "`
        [ -z "$pc" ] && continue
        [ `is_supported_agent ${pc}` = "no" -o `is_in_desired_list ${pc}` = "no" ] && continue
		
        instance=`echo $line | cut -f6 -d" "`
        agentuser=`echo $line | cut -f4 -d" "`
		
        id -u ${agentuser} > /dev/null 2>&1
        [ $? -eq 1 ] && continue
		

        [ "$instance" = "None" ] && unset instance
        if [ -n "$instance" ]; then
            if [ "$pc" = "ud" ]; then
                hostnameRunInfo=`echo $line | cut -f1 -d" "`
                instancename=${instance#${hostnameRunInfo}_}
            else
                instancename=$instance
            fi
            instance="-o $instancename"
        fi
		
        if [ "$thisRealUser" = "root" ]; then
			log_display_cmd "$su_value - $agentuser -c \"${CANDLEHOME}/bin/itmcmd agent -f $instance stop $pc\""
        	_rc=$(($rc + $?))
        	echo "$su_value - $agentuser -c \"${CANDLEHOME}/bin/itmcmd agent $instance start $pc\"" >> "$SHELL_START_ALL_AGENTS"
		elif [ "$thisRealUser" = "$agentuser" ]; then
        	log_display_cmd "${CANDLEHOME}/bin/itmcmd agent -f $instance stop $pc"
       		 _rc=$(($rc + $?))
        	echo "${CANDLEHOME}/bin/itmcmd agent $instance start $pc" >> "$SHELL_START_ALL_AGENTS"
        else
        	echo  "Can not restart the running $pc agent with current user, please restart it manually."
			log_warn "Can not restart the running $pc agent with current user, please restart it manually."
        fi
	done

	log_info "Exit stop_all_agents(${_rc})"
    return ${_rc}
}

###
# Main code starts here.
###

if [ $# -eq 0 ]; then
	print_usage
	exit 1
fi

CANDLEHOME=
SERVER=
TENANTID=
PORT=80
SENSOR="com.instana.plugin.itm"
IS_REVERT_TO_CMS=0
DIS_CUR_MODE=0
ENABLE_CP4MCM_HIST=0
AGENT_PRODUCTCODE_LIST=
ENVPROPFILE=
CONFIGURED_PC_LIST=
INSTALLED_TEMA_VER_32=
INSTALLED_TEMA_VER_64=
PROTOCOL="http" # http as default
CONNECTION_MODE="icam"
SDA_SUPPORT_DIRS=
icam_begin_comment="#Begin_of_ICAM_settings_do_not_update_this_line"
icam_2nd_comment="#Below_section_is_for_ICAM_only_do_not_add_customized_data_here"
icam_end_comment="#End_of_ICAM_settings_do_not_update_this_line"
# in case ambiguous redirect, set a tmp path. it will be re-set after Candle Home is validated.
LOG_FILE=/tmp/agent2server_itm.log
rm -f $LOG_FILE  2>/dev/null

while getopts "c:e:i:j:o:p:s:t:mrn" opt

do
    case ${opt} in
 c)
  CONNECTION_MODE=${OPTARG}
  if [ "$CONNECTION_MODE" == "instana" ]
  then
   CONNECTION_MODE="icam"
  fi
  valid_args ${opt} "$CONNECTION_MODE"
  ;;
    e)
    	ENVPROPFILE=${OPTARG}
    	;;
    i)
        CANDLEHOME=${OPTARG}
  ;;
 j)
  SDA_SUPPORT_DIRS=${OPTARG}
  ;;
	m)
		DIS_CUR_MODE=1
		;;		
	o)  
		PORT=${OPTARG}
		;;
	p)
		AGENT_PRODUCTCODE_LIST=${OPTARG}
		valid_args ${opt} "$AGENT_PRODUCTCODE_LIST"
		;;
	s)
        SERVER=${OPTARG}
		valid_args ${opt} $SERVER
        ;;
    t)
        TENANTID=${OPTARG}
        ;;	
    r)
        IS_REVERT_TO_CMS=1
        ;;
	n)
		ENABLE_CP4MCM_HIST=1
		;;
    *)
        print_usage
        exit 1
    esac
	
done

CANDLEHOME=`echo $CANDLEHOME | sed -e 's/\/*$//'`
validate_itmhome $CANDLEHOME
workdir=`pwd`
cd ${CANDLEHOME}
CANDLEHOME=`pwd`
LOCALCONFIG_DIR=${CANDLEHOME}/localconfig
LOG_FILE="$CANDLEHOME/logs/agent2server_itm.log"
SHELL_START_ALL_AGENTS="${CANDLEHOME}/tmp/start_all_agents_$$.sh"
ITM_SERVER_KEYFILE_BACKUP_DIR=$CANDLEHOME/keyfiles_itm
ICAM_SERVER_KEYFILE_DIR=$CANDLEHOME/keyfiles_icam
cd ${workdir}

log_info "***********AGENT2SERVER_ITM*************"
# log all arguments
while (( "$#" )); do 
  log_info $1 
  shift
done

# ensure -c itm is identical to -r
[ "${CONNECTION_MODE}" = "itm" ] && IS_REVERT_TO_CMS=1
[ ${IS_REVERT_TO_CMS} -eq 1 ] && CONNECTION_MODE=itm

if [ ${IS_REVERT_TO_CMS} -eq 1 ]; then
	enable_conn_itm_only
elif [ ${DIS_CUR_MODE} -eq 1 ]; then
	display_current_conn_mode
else
	# read env.properties
	if [ -z "$ENVPROPFILE" ]; then
		ENVPROPFILE="${CDIR}/env.properties"
		echo "Path of env.properties is not specified, using default path: $ENVPROPFILE"
		log_info "Path of env.properties is not specified, using default path: $ENVPROPFILE"
	fi
	read_envproperties || exit 1

	prereq_check $CANDLEHOME
	
	# Validate SDA support directories if provided
	validate_sda_support_dirs
	
	if [ "$SERVER" = "" -o "$PORT" = "" -o "$TENANTID" = "" ]; then
		if [ `get_config_status` = "no" ]; then
			echo "Need to specify server hostname, port and tenantid in env.properties."
			log_warn "Specify server hostname, port and tenantid"
			print_usage
			exit 1
		fi
	fi
	
	echo "Configuring agents...."
	log_info "Configuring agents...."
		
	INSTALLED_AGENT_LIST=`${CANDLEHOME}/bin/cinfo -i | grep Agent | cut -f1`
	for x in ${INSTALLED_AGENT_LIST}; do
		is_supported=`is_supported_agent ${x}`
		is_inlist=`is_in_desired_list ${x}`
		if [ "$is_supported" = "yes" -a "$is_inlist" = "yes" ]; then
			update_envfile ${x}
			copy_sda_jar ${x}
			CONFIGURED_PC_LIST="$CONFIGURED_PC_LIST ${x}"
		fi
	done

	display_current_conn_mode "${CONFIGURED_PC_LIST}"
	stop_all_agents
	handle_localconfig
	if [ "$PROTOCOL" = "https" ]; then	
		make_keyfilesforicam "$CDIR/keyfiles"
	fi	
	do_additional_config
	start_all_agents
	
	echo "Agents have been configured to connect to server $SERVER!"
	log_info "Agents have been configured to connect to server $SERVER!"
fi

log_info "*********************************"
