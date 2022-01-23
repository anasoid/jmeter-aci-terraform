# Adding plugins to JMeter Docker image

JMeter allows the use of custom plugins to improve the load testing experience and execute different load testing scenarios. The [jmeter-plugins.org](https://jmeter-plugins.org/) contains a catalogue with available custom plugins created by the community that can be used with [Plugins Manager](https://jmeter-plugins.org/wiki/PluginsManager/).

By default, this repository uses the [Test Plan Check Tool](https://jmeter-plugins.org/wiki/TestPlanCheckTool/) to automatically check the test plan consistency before running load tests. This validation is done in the load testing pipeline on Azure DevOps to avoid provisioning the infrastructure – VNet + ACI instances – if the JMX file is invalid (e.g. plugins that were not installed on JMeter root folder and invalid test parameters).

The image [anasoid/jmeter](https://hub.docker.com/r/anasoid/jmeter) is already pre-configured by [Test Plan Check Tool](https://jmeter-plugins.org/wiki/TestPlanCheckTool/)

By default Jmeter will detect plugin from [jmeter-plugins.org](https://jmeter-plugins.org/) and download them, you can also install more plugins by using other ways:

1- In jmeter folder add "plugins" folder with jar plugins.
2- Add environment variable "TF_VAR_JMETER_PLUGINS_MANAGER_INSTALL_LIST" with list of plugins see [download-dependencies-list-with-plugin-manager](https://github.com/anasoid/docker-jmeter#download-dependencies-list-with-plugin-manager)
