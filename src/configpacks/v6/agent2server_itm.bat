@echo off
REM ===========================================================================
REM Licensed Materials - Property of IBM
REM "Restricted Materials of IBM"
REM 
REM (C) Copyright IBM Corp. 2018. All Rights Reserved
REM ===========================================================================
REM -- Prepare the Command Processor --
setlocal EnableDelayedExpansion
SET SCRIPT_HOME=%~dp0
SET SCRIPT_NAME=%~nx0
:: SCRIPT_HOME without " "
for %%i in ("%SCRIPT_HOME%") do set SCRIPT_HOME_S=%%~si
for %%i in ("%CD%") do set CURRENT_DIR_S=%%~si


SET logfile=%SCRIPT_HOME_S%\agent2server_itm.log
SET logfile=%logfile:\\=\%
:: remove existing log if larger than 2M.
if exist %logfile% (
	for /f %%i in ("%logfile%") do ( if %%~zi GEQ 2097152 del /Q %logfile% )
)
echo *********************************%date% %time%********************************* >> %logfile%

set TenantID=
set server_host=
set server_port=
set protocol=
set CandleHome=
set envFile=
set pclist=
set rollback=
set SENSOR=com.instana.plugin.itm
set server_port_e=
set server_host_e=
set protocol_e=
set TenantID_e=
set enable_cp4mcm_hist=
set sda_support_dirs=
set "_NEW_SERVERNAME=Instana Host Agent"
:: for 3 connection mode, only one following three can be defined.
:: itm_m is identical to rollback
set dual_m=
set icam_m=
set itm_m=
set showConnMode=

call :VERIFY_ADMIN_RIGHTS
IF ERRORLEVEL 1 EXIT /B 1
IF "%~1"=="" goto DISPLAY_USAGE

:PARAM_LOOP
	IF "%~1"=="" GOTO VALIDATE_ARGS
	IF "%~1"=="/?" GOTO DISPLAY_USAGE
	IF "%~1"=="-help" GOTO DISPLAY_USAGE
	IF %1==-i (
		call :Validate_CandleHome %2
		if errorlevel 1 exit /b 1
		SET CandleHome=%~f2
	) ELSE IF %1==-s (
	    call :Check_Required_Param "Server hostname" "-s" %2
	    if errorlevel 1 exit /b 1
		SET server_host=%~2
	) ELSE IF %1==-o (
		call :Check_Required_Param "Server port" "-o" %2
		if errorlevel 1 exit /b 1
		SET server_port=%~2
	) ELSE IF %1==-t (
	    call :Check_Required_Param "Tenant id" "-t" %2
		if errorlevel 1 exit /b 1
		SET TenantID=%~2
	) ELSE IF %1==-e (
	    call :Validate_ENVFile %2
		if errorlevel 1 exit /b 1
		SET envFile=%~f2
	) ELSE IF %1==-p (
	    call :Check_Required_Param "Product code list" "-p" %2
		if errorlevel 1 exit /b 1
		SET pclist=%~2
	) ELSE IF %1==-j (
	    call :Check_Required_Param "SDA support directories" "-j" %2
		if errorlevel 1 exit /b 1
		SET sda_support_dirs=%~2
	) ELSE IF %1==-r (
		SET rollback=true
	) ELSE IF %1==-c (
		call :Check_Required_Param "connection mode" "-p" %2 || exit /b 1
		set conn_mode=%~2
		if /i "!conn_mode!"=="icam" (
			set icam_m=true
		) else if /i "!conn_mode!"=="instana" (
			set icam_m=true
		) else if /i "!conn_mode!"=="itm" (
			set itm_m=true
			set rollback=true
		) else if /i "!conn_mode!"=="dual" (
			set dual_m=true
		) else (
			echo Invalid connection mode !conn_mode!. Valid values are instana, itm and dual.
			exit /b 1
		)
	) ELSE IF %1==-m (
		set showConnMode=true
	) ELSE IF %1==-enable-cp4mcm-hist (
		set enable_cp4mcm_hist=true
	) ELSE IF %1==enable-cp4mcm-hist (
		set enable_cp4mcm_hist=true
	) ELSE IF %1==-n (
		set enable_cp4mcm_hist=true
	) ELSE (
		echo %1 is an invalid parameter. 
		exit /b 1
	)
	if /i %1==-r (
		shift
	) else if %1==-enable-cp4mcm-hist (
		shift
	) else if %1==enable-cp4mcm-hist (
		shift
	) else if %1==-n (
		shift	
	) else (
		shift
		shift
	)
	GOTO PARAM_LOOP



:VALIDATE_ARGS
if not defined CandleHome (
	echo "The ITM Home directory is required."
	exit /b 1
)

if not defined envFile set "envFile=%SCRIPT_HOME%env.properties"
call :Log_echo "Configure with %envFile% ..."
::Parse env.properties
if exist "%envFile%" (
	for /F "usebackq eol=# tokens=1,2 delims==" %%i in ("%envFile%") do (
    	if /i "%%i"=="hostname" set server_host_e=%%j
    	if /i "%%i"=="port"     set server_port_e=%%j
    	if /i "%%i"=="tenantid" set TenantID_e=%%j
    	if /i "%%i"=="protocol" set protocol_e=%%j
	)
	echo "protocol_e is !protocol_e!" >> %logfile%
	echo "hostname_e is !server_host_e!" >> %logfile%
	echo "port_e is !server_port_e!"  >> %logfile%
	echo "tenantid_e is !TenantID_e!" >> %logfile%
) else (
	call :Log_echo "Can't find env file: %envFile% !"
	exit /b 1
)


if not defined protocol set protocol=%protocol_e%
if not defined server_host set server_host=%server_host_e%
if not defined server_port set server_port=%server_port_e%
if defined server_host (
	echo %server_host%|findstr "^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$" >nul && (
		call :Log_echo "Do not specify IP address for the hostname."
		exit /b 1
	)
	if not defined server_port (
		set server_port=80
		call :Log_echo "The server port is not specified, using 80 by default."
	)
)
if not defined TenantID set TenantID=%TenantID_e%

:: for now we need all three parameters at one time.
if not defined rollback (
	if not defined server_host ( call :Log_echo "Server host is required." & exit /b 1 )
	if not defined server_port ( call :Log_echo "Server port is required." & exit /b 1 )
	if not defined TenantID ( call :Log_echo "TenantID is required." & exit /b 1 )
)

:: -r has higher priority
if defined rollback (
	set icam_m=
	set dual_m=
	set itm_m=true
) else (
	rem if nothing specified, default value is instana (icam_m)
	if not defined icam_m if not defined itm_m if not defined dual_m set icam_m=true
)

::if not defined rollback (
::rem at least one parameter is set
::if not defined server_host ( 
::if not defined server_port (
::if not defined TenantID (	
::	call :Log_echo "No server hostname, port or tenant ID is set. Nothing to configure."
::	exit /b 1
::) ) ) 
::rem if it is the 1st time configure, 3 parameters are required
::set _NEED_Check_3=true
::if defined server_host if defined server_port if defined TenantID set _NEED_Check_3=
::)

:: datapower-agent       		   BN
:: db2-agent                       UD
:: IIB agent                       QI
:: MQ agent                        MQ
:: Os agent                        NT/LZ/UX
:: was-agent                       YN

:: http_server-agent               HU
:: oracle_database-agent           RZ
:: jboss-agent                     JE
:: linux_kvm-agent                 V1
:: netapp_storage-agent            NU
:: tomcat-agent                    OT
:: sap-agent                       SA
:: vmware_vi-agent                 VM

:: dotnet-agent                    QF
:: microsoft_hyper-v_server-agent  HV
:: microsoft_iis-agent             Q7
:: mssql-agent                     OQ
:: Cisco UCS agent                 V6
:: Citrix VDI agent                VD
:: Skype for Business              QL 
:: Active Directory                3Z
:: MS Cluster                      Q5
:: MS Exchange                     EX 
:: All product codes are now supported, including custom agents built with Agent Builder/Agent Factory
:: The supported_pclist below is kept for reference only and is no longer used for validation
set "supported_pclist=BN MQ NT QI YN UD SA HU RZ JE NU OT SA VM OQ Q7 QF HV S7 H8 OY V6 VD QL 3Z Q5 EX"
if "%pclist%"=="" (
	:: When -p is not specified, configure ALL installed agents (including custom agents)
	:: This matches the behavior of the Linux script
	:: Set to special marker to indicate "all agents"
	set "pclist=__ALL__"
) else (
    :: All product codes are now supported - no validation is performed
    :: This allows custom agents with any product code to be configured
    for %%i in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do set "pclist=!pclist:%%i=%%i!"
)

echo --final parameters--  >> %logfile%
echo "CandleHome=%CandleHome%" >> %logfile%
echo "protocol=%protocol%" >> %logfile%
echo "server_host=%server_host%" >> %logfile%
echo "server_port=%server_port%" >> %logfile%
echo "TenantID=%TenantID%" >> %logfile%
echo "envFile=%envFile%" >> %logfile%
echo "pclist=%pclist%"  >> %logfile%
echo "sda_support_dirs=%sda_support_dirs%" >> %logfile%
echo "rollback=%rollback%" >> %logfile%
echo "conn_mode=%conn_mode%" >> %logfile%
echo "itm_m=%itm_m%" >> %logfile%
echo "icam_m=%icam_m%" >> %logfile%
echo "dual_m=%dual_m%" >> %logfile%
echo "showConnMode=%showConnMode%" >> %logfile%

for %%i in ("%CandleHome%") do set CandleHome_s=%%~si
set kinconfgexe=%CandleHome_s%\InstallITM\kinconfg.exe
set kincinfoexe=%CandleHome_s%\InstallITM\kincinfo.exe
:: supportIF9 is not avilable when rollback
set supportIF9=
call :PreCheck supportIF9
if errorlevel 1 exit /b 1

:: Validate SDA support directories if provided
if defined sda_support_dirs (
	call :Validate_SDA_Support_Dirs
	if errorlevel 1 exit /b 1
)
set "v2018keyStr=;--- %_NEW_SERVERNAME% Settings."
::set _TMPFILE_DIR=%TMP%
set _TMPFILE_DIR=%SCRIPT_HOME_S%
::set _TMPFILE_NEWPARAM=%_TMPFILE_DIR%\tmpfile_newparam
::set _TMPFILE_NEWPARAM_MQ=%_TMPFILE_DIR%\tmpfile_newparam_mq
::set _TMPFILE_OOTOPARAM=%_TMPFILE_DIR%\tmpfile_ootoparam
::set _TMPFILE_OOTOPARAM_MQ=%_TMPFILE_DIR%\tmpfile_ootoparam_mq
set _TMPFILE_REG=%_TMPFILE_DIR%\ICAM2018.reg
set _TMPFILE_INSTANCELIST=%_TMPFILE_DIR%\tmpfile_instancelist
set _TMPFILE_TEMPLATE=%_TMPFILE_DIR%\tmpfile_template
set _TMPFILE_NEWLIST=%_TMPFILE_DIR%\tmpfile_newlist
:: remove list is refreshed for each instance
set _TMPFILE_RMLIST=%_TMPFILE_DIR%\tmpfile_removelist
:: Go to script dir to create temp files
cd /d %SCRIPT_HOME_S%
echo Finding instances to be configured...
set _RUNNING_LIST=
set _RESTART_LIST=
set _SUCCESS_PCLIST=
call :GetInstanceList _RUNNING_LIST
echo all instances:  >> %logfile%
if exist %_TMPFILE_INSTANCELIST% (
	type %_TMPFILE_INSTANCELIST% >> %logfile%
) else (
	call :Log_echo "Can not find appropriate agents to configure. supported agents are: %supported_pclist%"
	cd /d %CURRENT_DIR_S%
	exit /b 1
)
echo _RUNNING_LIST="%_RUNNING_LIST%" >> %logfile%

:: -m has higher priority
if defined showConnMode (
	call :showAllPC_ConnMode
	goto Whole_end
)


:: _TMPFILE_TEMPLATE to save all parameters that might be removed in this script.
echo IRA_ASF_SERVER_TIMEOUT> %_TMPFILE_TEMPLATE%
echo IRA_ASF_SERVER_HEARTBEAT>> %_TMPFILE_TEMPLATE%
echo IRA_ASF_SERVER_MAX_CACHE_PERIOD>> %_TMPFILE_TEMPLATE%
echo IRA_API_DATA_ZLIB_COMPRESSION>> %_TMPFILE_TEMPLATE%
echo KBB_SHOW_NFS>> %_TMPFILE_TEMPLATE%
echo DNS_CACHE_REFRESH_INTERVAL>> %_TMPFILE_TEMPLATE%

echo ITM_AUTHENTICATE_SERVER_CERTIFICATE>> %_TMPFILE_TEMPLATE%

echo IRA_ASF_SERVER_URL>> %_TMPFILE_TEMPLATE%
echo IRA_API_DATA_BROKER_URL>> %_TMPFILE_TEMPLATE%
echo IRA_API_TENANT_ID>> %_TMPFILE_TEMPLATE%

echo KEYFILE_DIR>> %_TMPFILE_TEMPLATE%
echo GSK_KEYRING_FILE>> %_TMPFILE_TEMPLATE%
echo GSK_KEYRING_STASH>> %_TMPFILE_TEMPLATE%
echo GSK_KEYRING_LABEL>> %_TMPFILE_TEMPLATE%
echo GSK_SSL_EXTN_SERVERNAME_REQUEST>> %_TMPFILE_TEMPLATE%
echo IRA_MANAGEMENT_SERVER_HOSTS>> %_TMPFILE_TEMPLATE%
echo IRA_V8_LOCALCONFIG_DIR>> %_TMPFILE_TEMPLATE%
echo LOAD_PRIVATE_SITUATIONS_FROM_ICAM>> %_TMPFILE_TEMPLATE%
echo START_PVTHIST_SITUATIONS>> %_TMPFILE_TEMPLATE%

:: do not add OOTO in new parameters list anymore
echo\> %_TMPFILE_NEWLIST%
echo %v2018keyStr% Do not change this line! >> %_TMPFILE_NEWLIST%
echo IRA_ASF_SERVER_URL=%protocol%://%server_host%:%server_port%/%SENSOR%/ccm/asf/request>> %_TMPFILE_NEWLIST%
echo IRA_API_DATA_BROKER_URL=%protocol%://%server_host%:%server_port%/%SENSOR%/1.0/monitoring/data>> %_TMPFILE_NEWLIST%
echo IRA_API_TENANT_ID=%TenantID%>> %_TMPFILE_NEWLIST%
if /i "%protocol%"=="https" (
	echo GSK_SSL_EXTN_SERVERNAME_REQUEST=%server_host%>> %_TMPFILE_NEWLIST%	
	call :formathost %server_host% mangled_host
	echo IRA_MANAGEMENT_SERVER_HOSTS=!mangled_host!>> %_TMPFILE_NEWLIST%
	echo GSK_KEYRING_FILE_!mangled_host!=%CandleHome_s%\keyfiles_ICAM\keyfile.kdb>> %_TMPFILE_NEWLIST%
	echo GSK_KEYRING_STASH_!mangled_host!=%CandleHome_s%\keyfiles_ICAM\keyfile.sth>> %_TMPFILE_NEWLIST%
	echo GSK_KEYRING_LABEL_!mangled_host!=IBM_Tivoli_Monitoring_Certificate>> %_TMPFILE_NEWLIST%
	if defined icam_m echo ITM_AUTHENTICATE_SERVER_CERTIFICATE=Y>> %_TMPFILE_NEWLIST%		
)
if defined icam_m (
	echo CT_CMSLIST=>> %_TMPFILE_NEWLIST%
	if defined supportIF9 echo LOAD_PRIVATE_SITUATIONS_FROM_ICAM=Y>> %_TMPFILE_NEWLIST%
)
if defined enable_cp4mcm_hist (
	echo START_PVTHIST_SITUATIONS=YES>> %_TMPFILE_NEWLIST%
) else (
	echo START_PVTHIST_SITUATIONS=NO>> %_TMPFILE_NEWLIST%
)

:: NT and MQ always use self owned new list file
findstr "NT" %_TMPFILE_INSTANCELIST% >nul 2>&1 && (
    del /Q %_TMPFILE_NEWLIST%_NT >nul 2>&1 || ( call :Log_echo "Failed to remove %_TMPFILE_NEWLIST%_NT." & exit /b 1 )
	findstr /V /C:"CT_CMSLIST=" %_TMPFILE_NEWLIST% | findstr /V /C:"ITM_AUTHENTICATE_SERVER_CERTIFICATE" > %_TMPFILE_NEWLIST%_NT
)
findstr "MQ" %_TMPFILE_INSTANCELIST% >nul 2>&1 && (
	del /Q %_TMPFILE_NEWLIST%_MQ >nul 2>&1 || ( call :Log_echo "Failed to remove %_TMPFILE_NEWLIST%_MQ." & exit /b 1 )
	copy /Y /V %_TMPFILE_NEWLIST% %_TMPFILE_NEWLIST%_MQ >nul 2>&1
	echo INSTANCE=@CanTask@>> %_TMPFILE_NEWLIST%_MQ
)



if defined rollback (
	set invokefunc=CovertToITM
) else (
	set invokefunc=CovertToICAM
)
call :Log_echo "Stopping Agents ..."
start /wait %kinconfgexe% -pA
call :Log_echo "Agents stopped."

call :HandleKey_v2 || ( call :Restart_Agent %_RUNNING_LIST% & goto Whole_end )

if exist %CandleHome_s%\InstallITM\GetJavaHome.bat (
	for /f %%i in ('%CandleHome_s%\InstallITM\GetJavaHome.bat') do set _JAVA_HOME32=%%i
	echo JAVA_HOME32=!_JAVA_HOME32!>> %logfile%
)
if exist %CandleHome_s%\InstallITM\GetJavaHome64.bat (
	for /f %%i in ('%CandleHome_s%\InstallITM\GetJavaHome64.bat') do set _JAVA_HOME64=%%i
	echo JAVA_HOME64=!_JAVA_HOME64!>> %logfile%
)
:: global vars by instance to update ini files. 
for /f "tokens=1,2" %%i in (%_TMPFILE_INSTANCELIST%) do ( 
    set _PC=%%i
	set _INST=%%j
	set _INIFULLPATH=
	set _INIFILE=
	set _TMPFILE_CLEANINI=
	set _NOTCONFIGURED=
	rem set _NEWPARAM_FILE_PC=
	rem set _OOTOPARAM_FILE_PC=
	:: set _INIFILE, _TMPFILE_CLEANINI , etc
	call :INIT_Instance_Global_Var
	if errorlevel 1 (
		echo Failed to init global var for !_PC! !_INST!. Skip this instance.>>%logfile% 
	) else (
		call :%invokefunc%
		if !errorlevel!==0 (
			rem echo %_RUNNING_LIST% | findstr "!_PC!!_INST!" >nul 2>&1 && set "_RESTART_LIST=!_RESTART_LIST! K!_PC!!_INST!"
			echo !_SUCCESS_PCLIST! | findstr "!_PC!" >nul 2>&1 || set "_SUCCESS_PCLIST=!_SUCCESS_PCLIST! !_PC!"
		)
		del /Q !_TMPFILE_CLEANINI! >nul 2>&1
		del /Q %_TMPFILE_RMLIST% >nul 2>&1
	)
)

if defined rollback (
	del /Q %CandleHome_s%\License\tenantid.txt >nul 2>&1
)else (
	if defined TenantID echo %TenantID%>%CandleHome_s%\License\tenantid.txt  
)
echo Sucess PC list:%_SUCCESS_PCLIST%>> %logfile%
:: echo Restart list:%_RESTART_LIST%>> %logfile%
call :Remove_xml %_SUCCESS_PCLIST%
call :Restart_Agent %_RUNNING_LIST%
if defined _SUCCESS_PCLIST (
	if defined rollback (
		call :Log_echo "Successfully configured %_SUCCESS_PCLIST% agents to ITM server."
	) else (
		call :Log_echo "Successfully configured %_SUCCESS_PCLIST% agents to %_NEW_SERVERNAME% %server_host%"
	)
)

:Whole_end
del /Q %_TMPFILE_INSTANCELIST% > nul 2>&1
del /Q %_TMPFILE_TEMPLATE% >nul 2>&1
del /Q %_TMPFILE_NEWLIST% >nul 2>&1
del /Q %_TMPFILE_NEWLIST%_MQ >nul 2>&1
del /Q %_TMPFILE_NEWLIST%_NT >nul 2>&1

cd /d %CURRENT_DIR_S%
exit /b 0



:: --------------------------------------------- functions --------------------------------------------

:DISPLAY_USAGE
echo Usage:
echo %SCRIPT_NAME% -i ^<ITMhome^> [-e ^<env.properties^>] [-p ^<product code list^>] [-j ^<sda_support_dirs^>] [-r] [-c ^<instana^|itm^|dual^>] [-m]
echo -i ^<ITMhome^>             The installation directory of ITM or ITCAM agents.
echo -e ^<env.properties^>      The path to the file that contains all required server properties. By default, it is env.properties in the same directory of the agent2server_itm script.
echo -p ^<product code list^>   A list of product codes that will be configured to connect to %_NEW_SERVERNAME%. For example, "nt mq qi"
echo -j ^<sda_support_dirs^>    SDA jar support directories for custom agents. Format: "pc1=path1,pc2=path2"
echo                           where path is the custom agent installation support directory containing the SDA jar file
echo                           Example: -j "11=C:\tmp\k11\support"
echo -r                       If this parameter is specified, all agents will be configured to reconnect to TEMS.
echo -c                       Connection modes. valid values are instana, itm and dual. The default is instana.
echo -m                       Display current connection mode.
::echo -s ^<ip or hostname^>      The hostname of %_NEW_SERVERNAME%. Do not specify the IP address.
::echo -o ^<port^>                The port number of %_NEW_SERVERNAME%, it must be specified along with the server hostname.
::echo -t ^<tenantID^>            The tenant ID to access %_NEW_SERVERNAME%.
exit /b 0


:showAllPC_ConnMode
setlocal
for /f "tokens=1,2" %%i in (%_TMPFILE_INSTANCELIST%) do ( 
    set _PC=%%i
	set _INST=%%j
	set _INIFULLPATH=
	set _INIFILE=
	set _TMPFILE_CLEANINI=
	set _NOTCONFIGURED=
	call :INIT_Instance_Global_Var
	if errorlevel 1 (
		echo Failed to init global var for !_PC! !_INST!. Skip this instance.>>%logfile% 
	) else (
		call :GetConnMode
	)
)
endlocal & exit /b 0


:Validate_CandleHome
setlocal
    call :Check_Required_Param "ITM Home" "-i" %1
    if errorlevel 1 exit /b 1
    SET CandleHome_tmp=%~f1
    if not exist "%CandleHome_tmp%\InstallITM\kinconfg.exe" (
    	echo The ITM home directory "%CandleHome_tmp%" is invalid. 
    	exit /B 1 )
endlocal & exit /B 0

:Validate_ENVFile
setlocal
    call :Check_Required_Param "Environment file" "-e" %1
    if errorlevel 1 exit /b 1
    SET envFile_tmp=%~f1
    if not exist "%envFile_tmp%" (
    	echo The environment file %envFile_tmp% is invalid. 
    	exit /B 1 )
endlocal & exit /B 0

:: Use this to prompt which parameter is missing.
:Check_Required_Param
setlocal
    set param1=%~3
    if not defined param1 goto MISSING_PARAM
    set param2=%param1:~0,1%
    if "%param2%"=="-" goto MISSING_PARAM
    	endlocal & exit /b 0
:MISSING_PARAM
		echo %1 is required after %2.
    	endlocal & exit /b 1
    

:VERIFY_ADMIN_RIGHTS
NET SESSION >NUL 2>&1
IF NOT ERRORLEVEL 1 EXIT /B 0
echo This script must be run as Administrator.
EXIT /B 1


:Validate_PC
setlocal
:Validate_PC_loop
   set pc=%1
   if not defined pc goto Validate_PCend
   echo %pc% | findstr /I "%supported_pclist%" >nul 2>&1 || (
		echo %pc% is not supportted agent.
   		endlocal & exit /b 1
   )
   shift
goto Validate_PC_loop
:Validate_PCend
endlocal & exit /b 0

:: return restart list to %1
:GetInstanceList
setlocal
echo Enter GetInstanceList>> %logfile%
if exist %_TMPFILE_INSTANCELIST% del /Q %_TMPFILE_INSTANCELIST%
:: including Running and Not Running, exclude IN since it is Manage_Tivoli_Enterprise_Monitoring_Services
for /F "tokens=2,5,*" %%i in ('%kincinfoexe% -r ^| findstr Running') do (
	set pc=%%i
	if not "!pc!"=="IN" (
    	set tmpline=%%k
    	set ret_inst=
		call :FindInstName ret_inst !tmpline!
		if not defined ret_inst set ret_inst=Primary
		echo !tmpline! | findstr /C:"Not Running" >nul 2>&1 || set "_running_list_=!_running_list_! K!pc!!ret_inst!"
		:: If pclist is __ALL__ (no -p specified), configure all agents; otherwise check if pc is in the list
		if "!pclist!"=="__ALL__" (
			echo !pc! !ret_inst!>>%_TMPFILE_INSTANCELIST%
		) else (
			echo !pc! | findstr "!pclist!" >nul 2>&1 && echo !pc! !ret_inst!>>%_TMPFILE_INSTANCELIST%
		)
    )
)
echo Exit GetInstanceList>> %logfile%
endlocal & set "%1=%_running_list_%" & exit /b 0

:: %2 %3 %4 %5 ... online from kincinfo -r
:: %1 return the last column to %1 as instance name
:FindInstName
setlocal
     set retvar=%1
     shift
:FindInst_loop     
     set tmp=%1
     if not defined tmp goto FindInst_end
     set prev=%tmp%
     shift
     goto FindInst_loop
:FindInst_end
 endlocal & set "%retvar%=%prev%" & exit /b 0


:: Validate SDA support directories
:: Format: "pc1=path1,pc2=path2"
:Validate_SDA_Support_Dirs
setlocal
echo Enter Validate_SDA_Support_Dirs >> %logfile%
if not defined sda_support_dirs (
	echo No SDA support directories specified >> %logfile%
	endlocal & exit /b 0
)

:: Parse comma-separated mappings
for %%m in ("%sda_support_dirs:,=" "%") do (
	set "mapping=%%~m"
	
	:: Check if mapping contains '='
	echo !mapping! | findstr "=" >nul
	if errorlevel 1 (
		call :Log_echo "ERROR: Invalid SDA mapping format: !mapping!"
		call :Log_echo "Missing '=' separator. Expected format: productcode=path"
		call :Log_echo "Example: -j \"11=C:\tmp\k11\support\""
		endlocal & exit /b 1
	)
	
	for /f "tokens=1,2 delims==" %%a in ("!mapping!") do (
		set "pc=%%a"
		set "support_dir=%%b"
		
		:: Trim spaces
		for /f "tokens=* delims= " %%x in ("!pc!") do set "pc=%%x"
		for /f "tokens=* delims= " %%y in ("!support_dir!") do set "support_dir=%%y"
		
		if "!pc!"=="" (
			call :Log_echo "ERROR: Invalid SDA mapping format: !mapping!"
			call :Log_echo "Expected format: productcode=path"
			call :Log_echo "Example: -j \"11=C:\tmp\k11\support\""
			endlocal & exit /b 1
		)
		if "!support_dir!"=="" (
			call :Log_echo "ERROR: Invalid SDA mapping format: !mapping!"
			call :Log_echo "Expected format: productcode=path"
			call :Log_echo "Example: -j \"11=C:\tmp\k11\support\""
			endlocal & exit /b 1
		)
		
		:: Check if support directory exists
		if not exist "!support_dir!" (
			call :Log_echo "ERROR: SDA support directory does not exist for product code !pc!"
			call :Log_echo "Directory: !support_dir!"
			endlocal & exit /b 1
		)
		
		:: Look for SDA jar file with pattern: ${pc}_sda_*.jar or k${pc}_sda_*.jar
		set "sda_jar="
		for %%f in ("!support_dir!\!pc!_sda_*.jar") do set "sda_jar=%%f"
		if not defined sda_jar (
			for %%f in ("!support_dir!\k!pc!_sda_*.jar") do set "sda_jar=%%f"
		)
		
		if not defined sda_jar (
			call :Log_echo "ERROR: SDA jar file not found for product code !pc!"
			call :Log_echo "Expected pattern: !pc!_sda_*.jar or k!pc!_sda_*.jar"
			call :Log_echo "In directory: !support_dir!"
			endlocal & exit /b 1
		)
		
		echo Found SDA jar: !sda_jar! for product code !pc! >> %logfile%
	)
)

echo Exit Validate_SDA_Support_Dirs (OK) >> %logfile%
endlocal & exit /b 0

:: Copy SDA jar file for a specific product code
:: %1: product code
:Copy_SDA_Jar
setlocal
set "pc=%~1"
echo Enter Copy_SDA_Jar(%pc%) >> %logfile%

if not defined sda_support_dirs (
	echo No SDA support directories specified, skipping SDA jar copy >> %logfile%
	endlocal & exit /b 0
)

:: Parse comma-separated mappings to find this product code
for %%m in ("%sda_support_dirs:,=" "%") do (
	set "mapping=%%~m"
	for /f "tokens=1,2 delims==" %%a in ("!mapping!") do (
		set "map_pc=%%a"
		set "support_dir=%%b"
		
		:: Trim spaces
		for /f "tokens=* delims= " %%x in ("!map_pc!") do set "map_pc=%%x"
		for /f "tokens=* delims= " %%y in ("!support_dir!") do set "support_dir=%%y"
		
		if /i "!map_pc!"=="%pc%" (
			:: Find the SDA jar file
			set "sda_jar="
			for %%f in ("!support_dir!\%pc%_sda_*.jar") do set "sda_jar=%%f"
			if not defined sda_jar (
				for %%f in ("!support_dir!\k%pc%_sda_*.jar") do set "sda_jar=%%f"
			)
			
			if defined sda_jar (
				:: Determine the correct ITM directory (tmaitm6_x64 for 64-bit, tmaitm6 for 32-bit)
				:: Check for 64-bit first, then 32-bit
				set "target_dir="
				if exist "%CandleHome_s%\tmaitm6_x64\support\%pc%" (
					set "target_dir=%CandleHome_s%\tmaitm6_x64\support\%pc%"
				) else if exist "%CandleHome_s%\tmaitm6\support\%pc%" (
					set "target_dir=%CandleHome_s%\tmaitm6\support\%pc%"
				)
				
				if defined target_dir (
					for %%n in ("!sda_jar!") do set "sda_jar_name=%%~nxn"
					call :Log_echo "Copying SDA jar for product code %pc%: !sda_jar_name!"
					echo Copying !sda_jar! to !target_dir!\ >> %logfile%
					
					copy /Y /V "!sda_jar!" "!target_dir!\" >> %logfile% 2>&1
					if !errorlevel! equ 0 (
						call :Log_echo "Successfully copied SDA jar to !target_dir!\"
					) else (
						call :Log_echo "ERROR: Failed to copy SDA jar to !target_dir!\"
						endlocal & exit /b 1
					)
				) else (
					call :Log_echo "WARNING: Target support directory does not exist for product code %pc%"
					call :Log_echo "         Checked: %CandleHome_s%\tmaitm6_x64\support\%pc%"
					call :Log_echo "         Checked: %CandleHome_s%\tmaitm6\support\%pc%"
					endlocal & exit /b 1
				)
			)
			goto :copy_sda_done
		)
	)
)

:copy_sda_done
echo Exit Copy_SDA_Jar >> %logfile%
endlocal & exit /b 0

:: _PC, _INST, _INIFILE and _INIFULLPATH, _NOTCONFIGURED are defined global vars
:CovertToICAM
setlocal
echo Enter CovertToICAM>>%logfile%
    :: copy /y /V %_INIFULLPATH% %SCRIPT_HOME_S%\ini1.txt
	if defined _NOTCONFIGURED (
		rem  findstr does not support Regex very well.  thers is a \w and \t in [ ]
		rem type %_INIFULLPATH% | findstr /R /C:"^[ 	]*\[Override Local Settings\][ 	]*$" >nul 2>&1 || echo [Override Local Settings]>> %_INIFULLPATH%
		call :Check_Override_Line %_INIFULLPATH% || echo [Override Local Settings]>> %_INIFULLPATH%
		copy /Y /V %_INIFULLPATH%  %_TMPFILE_CLEANINI% >> %logfile% 2>&1 
	) else (
		call :Remove_old 
		if errorlevel 1  (
			echo Exit CovertToICAM with rc 1 >>%logfile%
			endlocal & exit /b 1
		)
	)
	:: copy /y /V %_INIFULLPATH% %SCRIPT_HOME_S%\ini2.txt
	if "%_PC%"=="MQ" (
		set "_TMPFILE_NEWLIST_PC=%_TMPFILE_NEWLIST%_MQ"
	) else if "%_PC%"=="NT" (
		set "_TMPFILE_NEWLIST_PC=%_TMPFILE_NEWLIST%_NT"
	) else (
		set "_TMPFILE_NEWLIST_PC=%_TMPFILE_NEWLIST%"
	)
    if not "%_PC%"=="NT" (
    	if defined icam_m (
    		call :Backup_REG
    	) else (
    		call :Restore_REG
     		echo CT_CMSLIST.ICAM2018=>>  %_TMPFILE_RMLIST%
			echo KDC_FAMILIES.ICAM2018=>> %_TMPFILE_RMLIST%
    	)
    )
    if exist %_TMPFILE_RMLIST% type  %_TMPFILE_RMLIST% >> %_INIFULLPATH%
    :: copy /y /V %_INIFULLPATH% %SCRIPT_HOME_S%\ini3.txt
	type %_TMPFILE_NEWLIST_PC% >> %_INIFULLPATH%
	:: IRA_V8_LOCALCONFIG_DIR is the only parameter associated with PC
	if defined supportIF9 echo IRA_V8_LOCALCONFIG_DIR=%CandleHome_s%\localconfig\%_PC%_icam >> %_INIFULLPATH%
	:: copy /y /V %_INIFULLPATH% %SCRIPT_HOME_S%\ini4.txt
    call :Log_echo "Reconfigure %_PC% agent %_INST% ..."
	start /wait %kinconfgexe% -n -riK%_PC%%_INST%
	copy /Y /V %_TMPFILE_CLEANINI% %_INIFULLPATH% >> %logfile% 2>&1
	:: copy /y /V %_INIFULLPATH% %SCRIPT_HOME_S%\ini5.txt 
	type %_TMPFILE_NEWLIST_PC% >> %_INIFULLPATH%
	if defined supportIF9 echo IRA_V8_LOCALCONFIG_DIR=%CandleHome_s%\localconfig\%_PC%_icam >> %_INIFULLPATH%
	:: copy /y /V %_INIFULLPATH% %SCRIPT_HOME_S%\ini6.txt
	call :Copy_SDA_Jar %_PC%
	call :Log_echo  "Complete reconfiguration of %_PC% instance %_INST%"
echo Exit CovertToICAM with rc 0 >> %logfile%
endlocal & exit /b 0

:CovertToITM
setlocal
echo Enter CovertToITM>>%logfile%
    if defined _NOTCONFIGURED (
    	call :Log_echo "%_PC% agent instance %_INST% is not configured to Instana, there is nothing to change." 
    	echo Exit CovertToITM with rc 0 >>%logfile%
    	endlocal & exit /b 0
    )
    call :Remove_old
    if errorlevel 1 (
    	echo Exit CovertToITM with rc 1 >>%logfile%
    	endlocal & exit /b 1
    )
    if not "%_PC%"=="NT" (
     	call :Restore_REG
     	echo CT_CMSLIST.ICAM2018=>>  %_TMPFILE_RMLIST%
		echo KDC_FAMILIES.ICAM2018=>> %_TMPFILE_RMLIST%
    )
    if exist %_TMPFILE_RMLIST% type  %_TMPFILE_RMLIST% >> %_INIFULLPATH%
    call :Log_echo "Reconfigure %_PC% agent %_INST% ..."
	start /wait %kinconfgexe% -n -riK%_PC%%_INST%
	:: re-copy to clean the ini file
	copy /Y /V %_TMPFILE_CLEANINI% %_INIFULLPATH% >> %logfile% 2>&1 
	:: type %_TMPFILE_CLEANINI% | findstr /V /C:"%v2018keyStr%" > %_INIFULLPATH%
	echo 2nd copy clean %_TMPFILE_CLEANINI% to %_INIFULLPATH% >> %logfile%
	call :Log_echo  "Complete reconfiguration of %_PC% instance %_INST%"
echo Exit CovertToITM with rc 0 >>%logfile%
endlocal & exit /b 0


:: _PC, _INST, _INIFILE and _INIFULLPATH are defined global vars
:: need to set 32bit or 64bit JAVA_HOME by instance in order to resolve @JAVA_HOME@ in ini file. 
:INIT_Instance_Global_Var
echo Enter INIT_Instance_Global_Var>> %logfile%
    if not defined _INST (
    	set _INIFILE=K%_PC%CMA.ini
    ) else if "%_INST%"=="Primary" (
		set _INIFILE=K%_PC%CMA.ini
	) else (
		set _INIFILE=K%_PC%CMA_%_INST%.ini
	)
	if exist %CandleHome_s%\tmaitm6_x64\%_INIFILE% (
		set _INIFULLPATH=%CandleHome_s%\tmaitm6_x64\%_INIFILE%
		set "JAVA_HOME=%_JAVA_HOME64%"
	) else if exist %CandleHome_s%\tmaitm6\%_INIFILE% (
		set _INIFULLPATH=%CandleHome_s%\tmaitm6\%_INIFILE%
		set "JAVA_HOME=%_JAVA_HOME32%"
	) else (
		call :Log_echo "Can not find %_INIFILE% !"
		echo Exit INIT_Instance_Global_Var with rc 1 >>%logfile% 
		exit /b 1
	)
	set _TMPFILE_CLEANINI=%_TMPFILE_DIR%\%_INIFILE%.clean
	if exist %_TMPFILE_CLEANINI% del /Q %_TMPFILE_CLEANINI%
	if exist  %_TMPFILE_RMLIST% del /Q  %_TMPFILE_RMLIST%
	findstr /C:"%v2018keyStr%" %_INIFULLPATH% >nul 2>&1 || set _NOTCONFIGURED=true
echo Exit INIT_Instance_Global_Var with rc 0 >>%logfile%	
exit /b 0
::endlocal & set "%~1=%_inifile_%" & set "%~2=%_inifullpath_%" & exit /b %_rc_%

::Update_ini
:Remove_old
setlocal
echo Enter Remove_old >>%logfile%
set tmp_linefile=%tmp%\tmpline_ICAM
set after_override=
set after_v2018=
call :Log_echo "Updating %_INIFULLPATH%"
for /f "tokens=1* delims=:" %%i in ('findstr /n .* %_INIFULLPATH%') do (
	set line=%%j
 	if not defined line (
        :: blank line
        if not defined after_override echo\>> %_TMPFILE_CLEANINI%
	) else if "!line:~0,1!"==";" (
        rem v2018keyStr should not be appended into clean file
        echo !line! | findstr  /C:"%v2018keyStr%" >nul 2>&1  && set after_v2018=true || echo !line!>> %_TMPFILE_CLEANINI%    
	) else if not defined after_override (
		echo !line!>%tmp_linefile%
		call :Check_Override_Line %tmp_linefile% && set after_override=true
		rem type %tmp_linefile% | findstr /R /C:"^[ 	]*\[Override Local Settings\][ 	]*$" >nul 2>&1 &&  set after_override=true
		echo !line!>> %_TMPFILE_CLEANINI%
	) else if not defined after_v2018 (
		echo !line!>> %_TMPFILE_CLEANINI%
	) else (
		call :ProcessLine "!line!"
	)
)
del /Q %tmp_linefile% >nul 2>&1
copy /Y /V %_TMPFILE_CLEANINI% %_INIFULLPATH% >> %logfile% 2>&1 
if errorlevel 1 (
	call :Log_echo "Failed to update %_INIFULLPATH%"
	del /Q %_TMPFILE_CLEANINI% >nul 2>&1
	echo Exit Remove_old with rc %errorlevel% >> %logfile%
	endlocal & exit /b 1
)
echo copy clean %_TMPFILE_CLEANINI%  to %_INIFULLPATH% >> %logfile%
echo Exit Remove_old with rc 0 >> %logfile% 
endlocal & exit /b 0

:: this is not used anymore
:Append_new
::echo Enter Append_new>>%logfile%
:: when roll back, should not append CT_CMSLIST= to ini 
type %_NEWPARAM_FILE_PC% | findstr /V /C:"CT_CMSLIST=" >> %_INIFULLPATH%
if exist %_OOTOPARAM_FILE_PC% (
	for /f "tokens=1,2 delims==" %%i in (%_OOTOPARAM_FILE_PC%) do (
		rem if there is new params in ooto, add it into ini file
		type %_INIFULLPATH% | findstr %%i >nul 2>&1 || echo %%i=%%j>> %_INIFULLPATH%
	)
)
::echo Exit Append_new>>%logfile%
exit /b 0

:Restart_Agent
setlocal
:Restart_Agent_loop
    set pcinst=%1
    if not defined pcinst goto Retart_end
	echo Restarting %pcinst% ...
	start /wait %kinconfgexe% -n -si%pcinst%
	shift
	goto Restart_Agent_loop  
:Retart_end
endlocal & exit /b 0

:Remove_xml
setlocal
if defined dual_m if not defined supportIF9 (
	dir /s "%CandleHome_s%\localconfig\*_cnfglist.xml" >nul 2>&1 || (
	dir /s "%CandleHome_s%\localconfig\*_situations.xml" >nul 2>&1
	) || goto Remove_xml_loop
	echo Warning:
	echo Agents are configured to connect to the Instana Host Agent and the Tivoli Enterprise Monitoring ^
Server ^(TEMS^) simultaneously. Any existing configuration files for Private situations and Central Configuration server ^
that are configured for IBM Tivoli Monitoring are backed up and replaced by those files that are downloaded from the ^
Instana Host Agent.
	   echo Therefore, Private situations, Private Historical data, and Central Configuration server files that are configured ^
in IBM Tivoli Monitoring are not available in dual mode.
 	echo.
)
:Remove_xml_loop
    set pc=%1
    if not defined pc goto Remove_end
    if defined rollback (
    	rem can't determine supportIF9 when rollback. so always try to restore v6backup
    	call :Restore_v6backup %pc%
    	if exist "%CandleHome_s%\localconfig\%pc%_icam" (
    		rmdir /s /q "%CandleHome_s%\localconfig\%pc%_icam" 2>nul
    		if exist "%CandleHome_s%\localconfig\%pc%_icam" (
    			call :Log_echo "Failed to remove %CandleHome%\localconfig\%pc%_icam."
    		)
    	) 
    ) else (
    	if defined supportIF9 (
    		call :Restore_v6backup %pc%
    		rmdir /s /q "%CandleHome_s%\localconfig\%pc%_icam" 2>nul
    		mkdir "%CandleHome_s%\localconfig\%pc%_icam"
    	) else (
	    	if exist "%CandleHome_s%\localconfig\%pc%_v6backup" (
	    		rem v6backup already exists, just remove all xml as APM v8 did.
	    		for /R "%CandleHome_s%\localconfig\%pc%" %%i in ( *.xml ) do (
	    			del /Q %%i >nul 2>&1
	    		)
	    	) else (
	    		if exist "%CandleHome_s%\localconfig\%pc%" (
	    			rename "%CandleHome_s%\localconfig\%pc%" "%pc%_v6backup"
	    			if errorlevel 1 (
	    				call :Log_echo "Failed to backup %CandleHome%\localconfig\%pc%"
	    			) else (
	    				echo Successfully backup %CandleHome%\localconfig\%pc% >>%logfile%
	    			)
	    		) else (
	    			rem crete empty v6backup dir to indidate it is switched to Instana agent.  
	    			mkdir "%CandleHome_s%\localconfig\%pc%_v6backup"
	    		)
	    		rem empty pc dir is required to download xml.
	    		mkdir "%CandleHome_s%\localconfig\%pc%" 2>nul
	    	)
    	)
    )
    shift
    goto Remove_xml_loop
:Remove_end
endlocal & exit /b 0

:Restore_v6backup
setlocal
	set pc=%1
	if exist "%CandleHome_s%\localconfig\%pc%_v6backup" (
		rmdir /s /q "%CandleHome_s%\localconfig\%pc%" 2>nul
		if exist "%CandleHome_s%\localconfig\%pc%" (
			call :Log_echo "Failed to remove %CandleHome%\localconfig\%pc%."
		) else (
			rename "%CandleHome_s%\localconfig\%pc%_v6backup" "%pc%"
			if errorlevel 1 (
				call :Log_echo "Failed to restore %CandleHome%\localconfig\%pc%_v6backup"
			) else (
				echo Successfully restored %CandleHome%\localconfig\%pc%_v6backup >> %logfile%
			)
		)
	) 
endlocal & exit /b 0


:: Only backup existing value to a new key.  Do not remove here
:Backup_REG
setlocal
    set reg_path=
    call :GetRegPath reg_path
    if errorlevel 1 endlocal & exit /b 1
    set _ct_cmslist_data=
    call :GetRegData %reg_path% CT_CMSLIST _ct_cmslist_data
    if errorlevel 1 endlocal & exit /b 1
  	REG ADD %reg_path% /v CT_CMSLIST.ICAM2018 /d "%_ct_cmslist_data%" /f >>%logfile% 2>&1
  	if %errorlevel%==0 echo Successfully backup CT_CMSLIST: "%_ct_cmslist_data%">> %logfile%
    set _kdc_families_data=
    call :GetRegData %reg_path% KDC_FAMILIES _kdc_families_data
    if errorlevel 1 endlocal & exit /b 1
    REG ADD %reg_path% /V KDC_FAMILIES.ICAM2018 /d "%_kdc_families_data%" /f >>%logfile% 2>&1
    if %errorlevel%==0 echo Successfully backup KDC_FAMILIES: "%_kdc_families_data%">> %logfile%
endlocal & exit /b 0    

:: Do not remove CT_CMSLIST.ICAM2018, it will be removed during Re-config
:Restore_REG
setlocal
	set reg_path=
    call :GetRegPath reg_path
    if errorlevel 1 endlocal & exit /b 1
    set _ct_cmslist_data=
	call :GetRegData %reg_path% CT_CMSLIST _ct_cmslist_data
	if not defined _ct_cmslist_data ( 
		set _ct_cmslist_icam2018_data=
		call :GetRegData %reg_path% CT_CMSLIST.ICAM2018 _ct_cmslist_icam2018_data
		if errorlevel 1 (
			echo Can not restore CT_CMSLIST for agent %_PC% %_INST%>> %logfile%
		) else (
			REG ADD %reg_path% /v CT_CMSLIST /d "!_ct_cmslist_icam2018_data!" /f >>%logfile% 2>&1
			if !errorlevel!==0 echo Successfully restored CT_CMSLIST: "!_ct_cmslist_icam2018_data!">> %logfile%  
		)
		set _kdc_families_icam2018_data=
		call :GetRegData %reg_path% KDC_FAMILIES.ICAM2018 _kdc_families_icam2018_data
		if errorlevel 1 (
			echo Can not restore KDC_FAMILIES for agent %_PC% %_INST%>> %logfile%
		) else (
			REG ADD %reg_path% /v KDC_FAMILIES /d "!_kdc_families_icam2018_data!" /f >>%logfile% 2>&1
			if !errorlevel!==0 echo Successfully restored KDC_FAMILIES: "!_kdc_families_icam2018_data!">> %logfile% 
		)
	) else (
		echo There is existing CT_CMSLIST:"%_ct_cmslist_data%". Skip restore. >> %logfile%
	)
endlocal & exit /b 0


:: %1 reg path, %2 reg name, %3 returned reg data
:GetRegData
setlocal
    set reg_path=%~1
    set reg_name=%~2
    REG QUERY %reg_path% /v  %reg_name%  > %_TMPFILE_REG% 2>nul 
    if errorlevel 1  (
    	echo Can not find1 %reg_name% from %reg_path% for agent %_PC% %_INST%>> %logfile% 
    	goto GetRegData_Fail
    )	
    for /f "tokens=1,2,*" %%i in ('type %_TMPFILE_REG% ^| findstr /C:"%reg_name%"') do set "reg_data=%%k"
    if not defined reg_data (
    	echo Can not find2 Registry data for %reg_name% from %reg_path% for agent %_PC% %_INST%>> %logfile% 
    	goto GetRegData_Fail
	)
	goto GetRegData_Success
:GetRegData_Fail
del /Q %_TMPFILE_REG% 1>nul 2>&1
endlocal & exit /b 1
:GetRegData_Success
del /Q %_TMPFILE_REG% 1>nul 2>&1
endlocal & set "%~3=%reg_data%" & exit /b 0


:: %1 return a path like HKLM\SOFTWARE\Candle\KMQ\Ver730\QM7502\Environment
:GetRegPath
setlocal
    for /f "tokens=2 delims==" %%i in ('findstr /C:"CanTask=" %_INIFULLPATH%') do set _inst_=%%i
    if not defined _inst_ goto GetRegPath_Fail
    for /f "tokens=2 delims==" %%i in ('findstr /C:"CanVers=" %_INIFULLPATH%') do set _ver_=%%i
    if not defined _ver_ goto GetRegPath_Fail
    for /f "tokens=2 delims==" %%i in ('findstr /C:"CanProd=" %_INIFULLPATH%') do set _kpc_=%%i
    if not defined _kpc_ goto GetRegPath_Fail
    goto GetRegPath_Success
:GetRegPath_Fail
    echo Failed to get Registry path from %_INIFULLPATH% >> %logfile%
    endlocal&exit /b 1
:GetRegPath_Success
	echo %_INIFULLPATH% | findstr "tmaitm6_x64" >nul && (
    	set "ret_path=HKLM\SOFTWARE\Candle\%_kpc_%\%_ver_%\%_inst_%\Environment"
    ) || (
    	set "ret_path=HKLM\SOFTWARE\Wow6432Node\Candle\%_kpc_%\%_ver_%\%_inst_%\Environment"
    )
    echo Success to get Registry path %ret_path% >> %logfile%
endlocal & set "%~1=%ret_path%" & exit /b 0

:PreCheck
if defined rollback exit /b 0
if defined showConnMode exit /b 0
setlocal
set filter=
set require32=
set require64=

:: If pclist is __ALL__ (no -p specified), skip the precheck as we'll configure all installed agents
if "%pclist%"=="__ALL__" (
	endlocal & exit /b 0
)

call :make_filter filter %pclist%

%kincinfoexe% -d | findstr "%filter%" > %tmp%\tmpfile_precheck 2>&1
if errorlevel 1 (
	call :Log_echo "The specified agent ^( %pclist% ^) is not installed."
	del /Q %tmp%\tmpfile_precheck
	endlocal & exit /b 1
)

type %tmp%\tmpfile_precheck | findstr "\"WINNT\"" >nul 2>&1 && set require32=true
type %tmp%\tmpfile_precheck | findstr "\"WIX64\"" >nul 2>&1 && set require64=true
del /Q %tmp%\tmpfile_precheck

set version_GL32=
set version_GL64=
for /F "tokens=*" %%i in ('%kincinfoexe% -t GL ^| findstr KGL ^| findstr WINNT') do call :getversion version_GL32 %%i
for /F "tokens=*" %%i in ('%kincinfoexe% -t GL ^| findstr KGL ^| findstr WIX64') do call :getversion version_GL64 %%i
echo found 32 GL version=%version_GL32% >> %logfile% 
echo found 64 GL version=%version_GL64% >> %logfile%

if /i "%protocol%"=="https" (
	set "prereqKGLver=06.30.07.08"
) else (
	set "prereqKGLver=06.30.07.03"
)
if defined require64 (
	if "%version_GL64%" GEQ "%prereqKGLver%" (
		set rc=0
	) else (
		call :Log_echo "KGL^(64-bit^) CMA/IBM Monitoring Agent Framework must be version %prereqKGLver% or later."
		set rc=1
	)
) else ( 
	set rc=0 
)
if defined require32 (
	if "%version_GL32%" GEQ "%prereqKGLver%" (
		set /a "rc=%rc%|0" >nul
	) else (
		call :Log_echo "KGL^(32-bit^) CMA/IBM Monitoring Agent Framework must be version %prereqKGLver% or later."
		set /a "rc=%rc%|1" >nul
	)
)
:: determine if this version can support localconfig/xx_icam
set "verIF9=06.30.07.09"
set isUpIF9=
if defined version_GL32 if defined version_GL64 (
	if "%version_GL32%" GEQ "%verIF9%" if "%version_GL64%" GEQ "%verIF9%" ( set "isUpIF9=true" & goto end_of_precheck )
	if "%version_GL32%" LSS "%verIF9%" if "%version_GL64%" LSS "%verIF9%" ( goto end_of_precheck )
	echo Warning: 
	echo Found mixed 32-bit/64-bit TEMA framework^(GL^) versions. If you need to enable Private situations, ^
Private Historical data, and Centralized Configuration for Instana Host Agent and Tivoli Enterprise Monitoring ^
Server^(TEMS^) simultaneously, upgrade both 32-bit and 64-bit TEMA to 06300709 or later.
	echo.
	goto end_of_precheck
)
:: if there is only one GL installed.
if defined version_GL64 if "%version_GL64%" GEQ "%verIF9%" ( set "isUpIF9=true" & goto end_of_precheck )
if defined version_GL32 if "%version_GL32%" GEQ "%verIF9%" ( set "isUpIF9=true" & goto end_of_precheck )
:end_of_precheck
endlocal & set "%1=%isUpIF9%" & exit /b %rc%
:: end of PreCheck

::%1 returened filter.     %2 %3 ...  all product code 
:make_filter
setlocal
set _filter_=
set _filter_var=%1
shift
:filter_loop
set _pc_=%1
if not defined _pc_ goto filter_loop_end
set "_filter_=%_filter_% \"%_pc_%\""
shift
goto filter_loop
:filter_loop_end
endlocal & set "%_filter_var%=%_filter_%" & exit /b 0

:: %1 returened version.  %2 %3 ... the line parsed from kincinfo -t
:getversion
setlocal
set "ver=%~1"
shift
:getversion_loop_begin
set tmpstr=%1
if not defined tmpstr goto getversion_loop_end
echo %tmpstr%| findstr /R "^[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]$" >nul 2>&1 && ( endlocal & set "%ver%=%tmpstr%" & exit /b 0 )
shift
goto getversion_loop_begin
:getversion_loop_end
exit /b 1

:Log_echo
setlocal
    set _tmp_=%~1
    echo %_tmp_%
    echo %_tmp_% >> %logfile%
endlocal & exit /b 0

:: %1 name of the file to be checked.
:Check_Override_Line
setlocal
set checkfile=%~1
findstr /C:"\[Override Local Settings\]" %checkfile% > %tmp%\tmpfileline && (
	for /f "usebackq tokens=1,2,3,4" %%i in ("%tmp%\tmpfileline") do (
		if "%%i"=="[Override" if "%%j"=="Local" if "%%k"=="Settings]" if "%%l"=="" endlocal & exit /b 0
	)
)
endlocal & exit /b 1


:HandleKey_v2
:: restore keyfiles_ITM regardless of http/https rollback/icam/dual
if exist %CandleHome_s%\keyfiles_ITM (
	rd /s /q %CandleHome_s%\keyfiles || (call :Log_echo "Failed to remove %CandleHome_s%\keyfiles rc=!errorlevel!." & exit /b 1)
	rename %CandleHome_s%\keyfiles_ITM keyfiles || (call :Log_echo "Failed to restore %CandleHome_s%\keyfiles_ITM with rc=!errorlevel!." & exit /b 1)
	call :Log_echo "Successfully restore keyfiles_ITM."
)
if /i not "%protocol%"=="https" exit /b 0
if defined rollback exit /b 0
:: following only required when https icam/dual
set "keyfiles_dir=%CandleHome_s%\keyfiles_ICAM"
:: dont't remove keyfiles_ICAM when roll back in case it is still in use by other agents.
if exist %keyfiles_dir% (
	rmdir /s /q %keyfiles_dir% 2>nul || ( call :Log_echo "Failed to remove %keyfiles_dir% with rc=!errorlevel!."  & exit /b 1)
)
mkdir %keyfiles_dir% || (call :Log_echo "Failed to create %keyfiles_dir% with rc=!errorlevel!." & exit /b 1)
copy /Y /V %CandleHome_s%\keyfiles\KAES256.ser %keyfiles_dir% >> %logfile% 2>&1 || (call :Log_echo "Failed to copy KAES256.ser rc=!errorlevel!" & exit /b 1)
copy /Y /V %SCRIPT_HOME_S%\keyfiles\keyfile.* %keyfiles_dir% >> %logfile% 2>&1 || (call :Log_echo "Failed to copy %SCRIPT_HOME_S%\keyfiles\keyfile.* rc=!errorlevel!" & exit /b 1)
echo Exit HandleKey_v2 with rc %errorlevel% >>%logfile%
exit /b 0



:: Convert hostname.ibm.com to HOSTNAME_IBM_COM
:: %1 input str, %2 output str
:formathost
setlocal
set "str=%~1"
set "output="
:: char1 to save previous char, in order to replace multiple '_' to single '_'
set "char1="
for %%i in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do set "str=!str:%%i=%%i!"
:formathost_loop
if not defined str goto formathost_end
set "char=%str:~0,1%"
::echo char=%char%
IF "%char%" LEQ "Z" IF "%char%" GEQ "A" goto formathost_skip
IF "%char%" LEQ "9" IF "%char%" GEQ "0" goto formathost_skip
if "%char1%"=="_" ( set "char=" ) else ( set "char=_" )
:formathost_skip
set "output=%output%%char%"
if defined char set "char1=%char%"
set "str=%str:~1%"
goto formathost_loop
:formathost_end
if "%output:~0,1%"=="_" set "output=%output:~1%"
if "%output:~-1%"=="_" set "output=%output:~0,-1%"
endlocal & set "%~2=%output%" & exit /b 0

:: Print connection mode for current _PC
:GetConnMode
:: if this PC is already known, skip this instance
echo %_KNOWN_PCLIST% | findstr %_PC% >nul && exit /b 0
setlocal
set mode=
set reg_path=
call :GetRegPath reg_path
if errorlevel 1 (
	call :Log_echo "Failed to find Registry path for %_PC% %_INST%. Can't check connection mode."
	endlocal & exit /b 1
)
set _server_url=
call :GetRegData %reg_path% IRA_ASF_SERVER_URL _server_url
if defined _server_url (
	set _itm_ip=
	call :GetRegData %reg_path% CT_CMSLIST _itm_ip
	if defined _itm_ip (
		set mode=dual
	) else (
		set mode=icam
	)
) else (
	set mode=itm
)
call :Log_echo "%_PC% is configured as %mode% mode."
endlocal & set "_KNOWN_PCLIST=%_KNOWN_PCLIST% %_PC%" & exit /b 0


:: 3 cases for a line after_v2018: append to remove list, append to clean file or abandon
:ProcessLine
setlocal
set "line=%~1"
for /f "tokens=1,2 delims==" %%k in ("%line%") do (
	findstr %%k %_TMPFILE_TEMPLATE% >nul 2>&1 && (
		findstr %%k %_TMPFILE_CLEANINI% >nul 2>&1 || echo %%k=>> %_TMPFILE_RMLIST%
		endlocal & exit /b 0
	) || (
	    rem trim key and value
		for /f "tokens=*" %%m in ("%%k") do set "key=%%m"
		for /f "tokens=*" %%n in ("%%l") do set "value=%%n"
		if "%_PC%"=="MQ" if "!key!"=="INSTANCE" if "!value!"=="@CanTask@" (
			findstr "INSTANCE=" %_TMPFILE_CLEANINI% >nul 2>&1 || ( echo INSTANCE=>> %_TMPFILE_RMLIST% )
			endlocal & exit /b 0
		)
		if "!key!"=="CT_CMSLIST" if "!value!"=="" ( endlocal&exit /b 0 )
		echo !key! | findstr "^GSK_KEYRING_FILE_ ^GSK_KEYRING_STASH_ ^GSK_KEYRING_LABEL_" >nul 2>&1 && (
			echo !key!=>> %_TMPFILE_RMLIST% 
		) || ( 
			echo %line%>> %_TMPFILE_CLEANINI% 
		)
	)
)
endlocal & exit /b 0


setlocal disabledelayedexpansion
endlocal
