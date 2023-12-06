#!/bin/bash
# This script must be sourced by external projects. It prepares all the environment to work with wildfly-cekit-modules

if [ "${SCRIPT_DEBUG}" = "true" ] ; then
    set -x
    echo "Script debugging is enabled, allowing bash commands and their arguments to be printed as they are executed"
fi

source $JBOSS_HOME/bin/launch/logging.sh
# sources external project configuration file. External projects will configure the common modules using launch-config.sh file.
# Specifically, they have to add the scripts they want to run into CONFIG_SCRIPT_CANDIDATES array
if [[ -s $JBOSS_HOME/bin/launch/launch-config.sh ]]; then
  source $JBOSS_HOME/bin/launch/launch-config.sh
fi
# Common environment variables, functions and configurations
source $JBOSS_HOME/bin/launch/launch.sh
configure_scripts
executeModules delayedPostConfigure
if [ -f "${CLI_SCRIPT_FILE}" ]; then
  cp "${CLI_SCRIPT_FILE}" "$1"
else
  echo "No CLI script generated"
fi

