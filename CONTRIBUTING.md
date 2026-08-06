# Contributing

## Adding or updating an `asf_definition.xml` for an ITM V6 agent

> **This section is for developers of this repository only.**
> Customers using the built configpack do not need to perform these steps.
> If you have a custom agent built with Agent Builder or Agent Factory, use the
> `-j` option with `agent2server_itm.sh` / `agent2server_itm.bat` instead —
> those agents manage their own `asf_definition.xml` automatically.

The configpack ships a pre-populated `asf_definition.xml` for each known standard ITM V6
agent under `src/configpacks/v6/subscriptions/<pc>/`. These files were extracted from the
agent's sda jar. Follow the procedure below to add a file for a new agent or to refresh an
existing one after an agent version upgrade.

### Where the file lives inside the sda jar

```
<ITMhome>/<arch>/<pc>/support/k<pc>_sda_<version>.jar
  └── config/CentralConfigurationServer.war
      └── data_source/<pc>/asf_definition.xml
```

### Extraction procedure (Linux/AIX example for product code `rz`)

```sh
cd /tmp
jar xf <ITMhome>/lx8266/rz/support/krz_sda_<version>.jar config/CentralConfigurationServer.war
jar xf config/CentralConfigurationServer.war data_source/rz/asf_definition.xml
mkdir -p <repo>/src/configpacks/v6/subscriptions/rz
cp data_source/rz/asf_definition.xml <repo>/src/configpacks/v6/subscriptions/rz/
```

Replace `lx8266` with the appropriate architecture directory for your system, `rz` / `krz`
with the two-character product code and its `k<pc>` prefix, and `<version>` with the actual
version string in the filename.

No need to modify the contents — copy it as-is and let the customer decide what to keep or remove.

### Adding the agent to the pre-populated list in the customer README

Update the table in `src/configpacks/v6/subscriptions/README.md` with the new product code,
agent name, and the version from the sda jar filename.
