#!/usr/bin/env bats

source $BATS_TEST_DIRNAME/../../../../../../../test-common/cli_utils.sh

# fake JBOSS_HOME
export JBOSS_HOME=$BATS_TMPDIR/jboss_home
rm -rf $JBOSS_HOME 2>/dev/null
mkdir -p $JBOSS_HOME/bin/launch

# copy scripts we are going to use
cp $BATS_TEST_DIRNAME/../../../../launch-config/config/added/launch/openshift-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../launch-config/os/added/launch/launch-common.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../../../../../../test-common/logging.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../added/oidc.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../added/oidc-keycloak-env.sh $JBOSS_HOME/bin/launch
cp $BATS_TEST_DIRNAME/../../added/oidc-keycloak-hooks.sh $JBOSS_HOME/bin/launch

mkdir -p $JBOSS_HOME/standalone/configuration
mkdir -p $JBOSS_HOME/standalone/deployments

# Set up the environment variables and load dependencies
WILDFLY_SERVER_CONFIGURATION=standalone-openshift.xml

# source the scripts needed
source $JBOSS_HOME/bin/launch/logging.sh
source $JBOSS_HOME/bin/launch/openshift-common.sh
source $JBOSS_HOME/bin/launch/oidc.sh

BATS_PATH_TO_EXISTING_FILE=$BATS_TEST_DIRNAME/oidc.bats

setup() {
  cp $BATS_TEST_DIRNAME/../../../../../../../test-common/configuration/standalone-openshift.xml $JBOSS_HOME/standalone/configuration
  cp $BATS_TEST_DIRNAME/simple-webapp.war $JBOSS_HOME/standalone/deployments
  cp $BATS_TEST_DIRNAME/simple-webapp2.war $JBOSS_HOME/standalone/deployments
}

teardown() {
  if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    rm "${CONFIG_FILE}"
  fi
}

@test "Unconfigured" {
  run oidc_configure
  [ "${output}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Legacy SSO, nothing should be generated" {
    SSO_USE_LEGACY="true"
    SSO_URL="http://foo:9999/auth"

    run oidc_configure
    echo "CONSOLE:${output}"
    [ "${output}" = "" ]
    [ "$status" -eq 0 ]
    [ ! -a "${CLI_SCRIPT_FILE}" ]
}

@test "SSO env variables, provider enabled, generation expected" {
    expected=$(cat << EOF
      if (outcome != success) of /extension=org.wildfly.extension.elytron-oidc-client:read-resource
   /extension=org.wildfly.extension.elytron-oidc-client:add()
   end-if
   if (outcome != success) of /subsystem=elytron-oidc-client:read-resource
   /subsystem=elytron-oidc-client:add()
   end-if
   /subsystem=elytron-oidc-client/provider=sso:add(provider-url=http://foo:9999/auth/realms/master,register-node-at-startup=true,register-node-period=600,ssl-required=external,allow-any-hostname=false)
   /subsystem=elytron-oidc-client/provider=sso:write-attribute(name=disable-trust-manager,value=true)
   /subsystem=elytron-oidc-client/provider=sso:write-attribute(name=enable-cors, value=false)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:add(enable-basic-auth=true, provider=sso)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=client-id, value=simple-webapp2)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=bearer-only, value=false)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:add(enable-basic-auth=true, provider=sso)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=client-id, value=simple-webapp)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=bearer-only, value=false)

EOF
)
    SSO_URL="http://foo:9999/auth"

    run oidc_configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    echo "FILE: ${output}"
    [ "${output}" = "${expected}" ]
}

@test "sso provider, provider enabled, generation expected" {
    expected=$(cat << EOF
    if (outcome != success) of /extension=org.wildfly.extension.elytron-oidc-client:read-resource
   /extension=org.wildfly.extension.elytron-oidc-client:add()
   end-if
   if (outcome != success) of /subsystem=elytron-oidc-client:read-resource
   /subsystem=elytron-oidc-client:add()
   end-if
   /subsystem=elytron-oidc-client/provider=sso:add(provider-url=http://foo:9999/auth/realms/Wildfly,register-node-at-startup=true,register-node-period=600,ssl-required=external,allow-any-hostname=false)
   /subsystem=elytron-oidc-client/provider=sso:write-attribute(name=disable-trust-manager,value=true)
   /subsystem=elytron-oidc-client/provider=sso:write-attribute(name=enable-cors, value=false)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:add(enable-basic-auth=true, provider=sso)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=client-id, value=simple-webapp2)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=bearer-only, value=false)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:add(enable-basic-auth=true, provider=sso)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=client-id, value=simple-webapp)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=bearer-only, value=false)

EOF
)
    OIDC_PROVIDER_URL="http://foo:9999/auth/realms/Wildfly"
    OIDC_PROVIDER_NAME="sso"
    run oidc_configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    echo "FILE: ${output}"
    [ "${output}" = "${expected}" ]
}

@test "keycloak provider, provider enabled, generation expected" {
    expected=$(cat << EOF
      if (outcome != success) of /extension=org.wildfly.extension.elytron-oidc-client:read-resource
   /extension=org.wildfly.extension.elytron-oidc-client:add()
   end-if
   if (outcome != success) of /subsystem=elytron-oidc-client:read-resource
   /subsystem=elytron-oidc-client:add()
   end-if
   /subsystem=elytron-oidc-client/provider=keycloak:add(provider-url=http://foo:9999/auth/realms/Wildfly,register-node-at-startup=true,register-node-period=600,ssl-required=external,allow-any-hostname=false)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=disable-trust-manager,value=true)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=enable-cors, value=false)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:add(enable-basic-auth=true, provider=keycloak)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=client-id, value=simple-webapp2)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=bearer-only, value=false)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:add(enable-basic-auth=true, provider=keycloak)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=client-id, value=simple-webapp)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=bearer-only, value=false)

EOF
)
    OIDC_PROVIDER_URL="http://foo:9999/auth/realms/Wildfly"
    OIDC_PROVIDER_NAME="keycloak"
    run oidc_configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    echo "FILE: ${output}"
    [ "${output}" = "${expected}" ]
}

@test "keycloak provider, provider enabled, all env vars generation expected" {
    expected=$(cat << EOF
       if (outcome != success) of /extension=org.wildfly.extension.elytron-oidc-client:read-resource
   /extension=org.wildfly.extension.elytron-oidc-client:add()
   end-if
   if (outcome != success) of /subsystem=elytron-oidc-client:read-resource
   /subsystem=elytron-oidc-client:add()
   end-if
   /subsystem=elytron-oidc-client/provider=keycloak:add(provider-url=http://foo:9999/auth/realms/Wildfly,register-node-at-startup=true,register-node-period=600,ssl-required=none,allow-any-hostname=false)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=realm-public-key,value=pub-key)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=truststore,value=/etc/dir/foo.jks)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=truststore-password,value=foo-trust-password)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=enable-cors, value=true)
   /subsystem=elytron-oidc-client/provider=keycloak:write-attribute(name=principal-attribute, value=preferred_username)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:add(enable-basic-auth=true, provider=keycloak)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=client-id, value=simple-webapp2)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war/credential=secret:add(secret=my-secret)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp2.war:write-attribute(name=bearer-only, value=true)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:add(enable-basic-auth=true, provider=keycloak)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=client-id, value=simple-webapp)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war/credential=secret:add(secret=my-secret)
   /subsystem=elytron-oidc-client/secure-deployment=simple-webapp.war:write-attribute(name=bearer-only, value=true)

EOF
)
    OIDC_PROVIDER_URL="http://foo:9999/auth/realms/Wildfly"
    OIDC_PROVIDER_NAME="keycloak"
    OIDC_REALM_PUBLIC_KEY="pub-key"
    OIDC_SECURE_DEPLOYMENT_SECRET="my-secret"
    OIDC_SECURE_DEPLOYMENT_PRINCIPAL_ATTRIBUTE="preferred_username"
    OIDC_SECURE_DEPLOYMENT_ENABLE_CORS="true"
    OIDC_SECURE_DEPLOYMENT_BEARER_ONLY="true"
    OIDC_PROVIDER_SSL_REQUIRED="none"
    OIDC_PROVIDER_TRUSTSTORE="foo.jks"
    OIDC_PROVIDER_TRUSTSTORE_DIR="/etc/dir"
    OIDC_PROVIDER_TRUSTSTORE_PASSWORD="foo-trust-password"
    run oidc_configure
    echo "CONSOLE: ${output}"
    output=$(<"${CLI_SCRIPT_FILE}")
    normalize_spaces_new_lines
    echo "FILE: ${output}"
    [ "${output}" = "${expected}" ]
}