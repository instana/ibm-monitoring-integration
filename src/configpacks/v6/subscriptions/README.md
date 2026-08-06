# Subscription files for ITM V6 agents

This directory contains `asf_definition.xml` subscription files for ITM V6 agents.

An `asf_definition.xml` file is an Agent Subscription Facility definition which tells the
ITM agent which attribute groups (tables) and attributes (columns) to subscribe to and
send as monitoring data.

> **Note:** This mechanism is NOT for custom agents built with Agent Builder or Agent Factory.
> Those agents upload their own sda jar and the Instana host agent extracts the
> `asf_definition.xml` automatically. Use the `-j` option for those agents instead.

## Structure

Each agent has its own subdirectory named after its two-character product code:

```
subscriptions/
  rz/asf_definition.xml    Oracle Database agent
  ud/asf_definition.xml    DB2 agent
  ...
```

## How the script uses these files

When `agent2server_itm.sh` (or `.bat`) is run, for each configured product code it checks
whether `subscriptions/<pc>/asf_definition.xml` exists. If found, it copies the file to:

- **Single-instance agent:** `<ITMhome>/localconfig/<pc>_icam/<pc>_asfSubscription.xml`
- **Multi-instance agent:** `<ITMhome>/localconfig/<pc>_icam/<instance>/<pc>_<instance>_asfSubscription.xml`

No extra options are required — the copy happens automatically as part of normal configuration.

## Customising what data is collected

Each `asf_definition.xml` file controls exactly which attribute groups (tables) and
attributes (columns) the agent subscribes to and forwards as monitoring data.
You can edit these files to tune the data collection to your needs:

- **Too much data?** Open the agent's `asf_definition.xml` and remove the `<SQLTABLE>` blocks
  or individual `<COLUMN>` elements you no longer need. The agent will stop collecting and
  forwarding those metrics on its next restart.
- **Need more data?** Add `<SQLTABLE>` blocks or `<COLUMN>` elements for the groups/columns
  you want. Refer to the agent's product documentation for the full list of available
  attribute groups and attributes.

Changes take effect after the `agent2server_itm.sh` (or `.bat`) script is re-run, which
re-copies the updated file to the agent's `localconfig` directory and restarts the agent.

## Pre-populated agents (45)

The following agents ship with a pre-populated `asf_definition.xml` in this configpack.
If you need a file for an additional agent, contact your IBM support representative.

| PC | Agent | Version |
|----|-------|---------|
| `3z` | Microsoft Active Directory Agent | 8.2.2.0400 |
| `ak` | Azure Compute Agent | 8.2.2.0100 |
| `al` | Amazon ELB Agent | 8.2.2.0100 |
| `b5` | Amazon EC2 Agent | 8.2.2.0100 |
| `bn` | DataPower Agent | 8.2.3.0500 |
| `ck` | CouchDB Agent | 8.2.2.0700 |
| `d0` | WebSphere Application Server Deployment Manager Agent | 8.2.2.0700 |
| `dt` | DataStage Agent | 8.2.4.0300 |
| `ex` | Microsoft Exchange Server Agent | 8.2.3.0500 |
| `fc` | Sterling Connect:Direct Agent | 8.2.2.0700 |
| `fg` | Sterling File Gateway Agent | 8.2.3.0500 |
| `h8` | Hadoop Agent | 8.2.2.0700 |
| `hu` | IBM HTTP Server Agent | 8.2.0.1300 |
| `hv` | Microsoft Hyper-V Agent | 8.2.2.0400 |
| `is` | Internet Service Monitoring Agent | 8.2.3.0500 |
| `je` | JBoss Application Server Agent | 8.2.2.0400 |
| `kj` | MongoDB Agent | 8.2.2.0700 |
| `lo` | Log File Agent | 6.3.0.1100 |
| `mj` | MariaDB Agent | 8.2.2.0700 |
| `mo` | Microsoft Office 365 Agent | 8.2.2.0100 |
| `nu` | NetApp Storage Agent | 8.2.3.0500 |
| `oq` | Microsoft SQL Server Agent | 8.2.4.0300 |
| `ot` | Tomcat Agent | 8.2.4.0300 |
| `oy` | Sybase ASE Agent | 8.2.2.1000 |
| `pn` | PostgreSQL Agent | 8.2.2.0700 |
| `q5` | Microsoft Cluster Server Agent | 8.2.2.0100 |
| `q7` | Microsoft IIS Agent | 8.2.3.0500 |
| `qe` | Microsoft .NET Agent | 8.2.3.0500 |
| `qi` | IBM Integration Bus Agent | 8.2.4.0300 |
| `ql` | Microsoft Lync Server Agent | 8.2.2.0100 |
| `qp` | Microsoft SharePoint Agent | 8.1.9.0900 |
| `rz` | Oracle Database Agent | 8.2.4.0300 |
| `s7` | SAP HANA Agent | 8.2.2.0700 |
| `sa` | SAP Applications Agent | 8.2.3.0500 |
| `se` | MySQL Agent | 8.2.2.0700 |
| `sv` | SAP NetWeaver Agent | 8.2.4.0300 |
| `ud` | DB2 Agent | 8.2.4.0300 |
| `v1` | KVM Agent | 8.2.2.0700 |
| `v6` | Cisco UCS Agent | 8.2.2.0700 |
| `vd` | Citrix Virtual Desktop Infrastructure Agent | 8.1.4.0076 |
| `vm` | VMware Agent | 8.2.2.0700 |
| `wb` | Oracle WebLogic Agent | 8.2.2.0400 |
| `yn` | WebSphere Application Server Agent | 7.3.0.1420 |
| `zc` | Cassandra Agent | 8.2.2.0700 |
| `zr` | RabbitMQ Agent | 8.2.2.0700 |
