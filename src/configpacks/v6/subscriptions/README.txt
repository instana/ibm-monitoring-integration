This directory contains asf_definition.xml subscription files for ITM V6 agents.

An asf_definition.xml file is an Agent Subscription Facility definition which tells the
ITM agent which attribute groups (tables) and attributes (columns) to subscribe to and
send as monitoring data.

Note: this mechanism is NOT for custom agents built with Agent Builder or Agent Factory.
Those agents upload their own sda jar and the Instana host agent extracts the
asf_definition.xml automatically.  Use the -j option for those agents instead.

Structure
---------
Each agent has its own subdirectory named after its two-character product code:

  subscriptions/
    rz/asf_definition.xml    Oracle Database agent
    ud/asf_definition.xml    DB2 agent
    ...

Extracting the asf_definition.xml file
---------------------------------------
The file is inside the agent's sda jar, nested inside CentralConfigurationServer.war:

  <ITMhome>/<arch>/<pc>/support/k<pc>_sda_<version>.jar
    └── config/CentralConfigurationServer.war
        └── asf_definition.xml  (path inside the WAR varies by agent)

To extract (Linux/AIX example for product code RZ):
  cd /tmp
  jar xf <ITMhome>/lx8266/rz/support/krz_sda_<version>.jar config/CentralConfigurationServer.war
  jar xf config/CentralConfigurationServer.war asf_definition.xml
  mkdir -p <configpack>/subscriptions/rz
  cp asf_definition.xml <configpack>/subscriptions/rz/

What the script does
---------------------
When agent2server_itm.sh (or .bat) is run, for each configured product code it checks
whether subscriptions/<pc>/asf_definition.xml exists.  If found, it copies the file to:

  Single-instance agent:  <ITMhome>/localconfig/<pc>_icam/<pc>_asfSubscription.xml
  Multi-instance agent:   <ITMhome>/localconfig/<pc>_icam/<instance>/<pc>_<instance>_asfSubscription.xml

No extra options are required — the copy happens automatically as part of normal configuration.
