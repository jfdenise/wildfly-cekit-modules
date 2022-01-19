#!/bin/sh

source $JBOSS_HOME/bin/launch/logging.sh

function prepareEnv() {
  unset APPLICATION_NAME
  unset APPLICATION_ROUTES
  unset HOSTNAME_HTTP
  unset HOSTNAME_HTTPS
  unset SECURE_DEPLOYMENTS
  unset SECURE_SAML_DEPLOYMENTS
  unset SSO_BEARER_ONLY
  unset SSO_DISABLE_SSL_CERTIFICATE_VALIDATION
  unset SSO_ENABLE_CORS
  unset SSO_PASSWORD
  unset SSO_PRINCIPAL_ATTRIBUTE
  unset SSO_PUBLIC_KEY
  unset SSO_REALM
  unset SSO_SAML_CERTIFICATE_NAME
  unset SSO_SAML_KEYSTORE
  unset SSO_SAML_KEYSTORE_DIR
  unset SSO_SAML_KEYSTORE_PASSWORD
  unset SSO_SAML_LOGOUT_PAGE
  unset SSO_SAML_VALIDATE_SIGNATURE
  unset SSO_SECRET
  unset SSO_SECURITY_DOMAIN
  unset SSO_SERVICE_URL
  unset SSO_TRUSTSTORE
  unset SSO_TRUSTSTORE_CERTIFICATE_ALIAS
  unset SSO_TRUSTSTORE_DIR
  unset SSO_TRUSTSTORE_PASSWORD
  unset SSO_URL
  unset SSO_USERNAME
}

function configure() {
  if [ ! -n "$SSO_USE_LEGACY" ] || [ "$SSO_USE_LEGACY" != "true" ]; then
    return
  fi
  configure_cli_keycloak
}

OPENIDCONNECT="KEYCLOAK"
SAML="KEYCLOAK-SAML"
SECURE_DEPLOYMENTS=$JBOSS_HOME/standalone/configuration/secure-deployments
SECURE_SAML_DEPLOYMENTS=$JBOSS_HOME/standalone/configuration/secure-saml-deployments
SECURE_DEPLOYMENTS_CLI=$JBOSS_HOME/standalone/configuration/secure-deployments.cli
SECURE_SAML_DEPLOYMENTS_CLI=$JBOSS_HOME/standalone/configuration/secure-saml-deployments.cli

SUBSYSTEM_END_MARKER="</profile>"
EXTENSIONS_END_MARKER="</extensions>"

function configure_cli_keycloak() {
    # We cannot have nested if sentences in CLI, so we use Xpath here to see if the subsystem=keycloak is in the file
    xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:keycloak:')]\""
    local ret_oidc
    testXpathExpression "${xpath}" "ret_oidc"

    # We cannot have nested if sentences in CLI, so we use Xpath here to see if the subsystem=keycloak-saml is in the file
    xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:keycloak-saml:')]\""
    local ret_saml
    testXpathExpression "${xpath}" "ret_saml"

    app_sec_domain=${SSO_SECURITY_DOMAIN:-keycloak}
    id=$(date +%s)

    local has_security_subsystem
    local xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:security:')]\""
    testXpathExpression "${xpath}" "has_security_subsystem"

    # No more supported
    if [ -n "${SSO_FORCE_LEGACY_SECURITY}" ]; then
      log_error "SSO_FORCE_LEGACY_SECURITY env variable can't be set, Elytron is used to configure keycloak integration."
      log_error "Exiting..."
      exit
    fi

    xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:undertow:')]/*[local-name()='application-security-domains']/*[local-name()='application-security-domain' and @name='other' and @security-domain='ApplicationDomain']\""
    local ret_domain
    testXpathExpression "${xpath}" "ret_domain"
    is_saml="false"
    is_oidc="false"
    other_exists="false"
    if [ "${ret_domain}" -eq 0 ]; then
      other_exists="true"
    fi
    if [ -f "$SECURE_DEPLOYMENTS_CLI" ] || [ -f "$SECURE_SAML_DEPLOYMENTS_CLI" ]; then

      elytron_assert="$(elytron_common_assert $app_sec_domain)"

      if [ -f "$SECURE_DEPLOYMENTS_CLI" ]; then
        if [ "${ret_oidc}" -ne 0 ]; then
          oidc_extension="$(configure_OIDC_extension)"
          oidc_elytron="$(configure_OIDC_elytron $id)"
          ejb_config="$(configure_ejb $id $app_sec_domain)"

          echo " 
            $elytron_assert
            $oidc_elytron
            $ejb_config" >> ${CLI_SCRIPT_FILE}
          echo " 
              $oidc_extension
              /subsystem=keycloak:add
              " >> ${CLI_SCRIPT_FILE}
          cat "$SECURE_DEPLOYMENTS_CLI" >> "$CLI_SCRIPT_FILE"
          is_oidc="true"
        else
          log_warning "keycloak subsystem already exists, no configuration applied"
        fi
      fi
      if [ -f "$SECURE_SAML_DEPLOYMENTS_CLI" ]; then
        if [ "${ret_saml}" -ne 0 ]; then
          saml_extension="$(configure_SAML_extension)"
          saml_elytron="$(configure_SAML_elytron $id)"
          echo "
            $elytron_assert
            $saml_elytron"  >> ${CLI_SCRIPT_FILE}
          echo " 
            $saml_extension
            /subsystem=keycloak-saml:add
            " >> ${CLI_SCRIPT_FILE}
          cat "$SECURE_SAML_DEPLOYMENTS_CLI" >> "$CLI_SCRIPT_FILE"
          is_saml="true"
        else
          log_warning "keycloak saml subsystem already exists, no configuration applied"
        fi
      fi
      if [ "$other_exists" == "true" ]; then
        other_config="$(configure_existing_other_cli $is_saml $is_oidc $id)"
        echo "
         $other_config" >> ${CLI_SCRIPT_FILE}
      fi
      undertow_config="$(configure_undertow $id $app_sec_domain)"
      echo "
       $undertow_config" >> ${CLI_SCRIPT_FILE}
      enable_keycloak_deployments
    elif [ -f "$SECURE_DEPLOYMENTS" ] || [ -f "$SECURE_SAML_DEPLOYMENTS" ]; then

      elytron_assert="$(elytron_common_assert $app_sec_domain)"

      if [ -f "$SECURE_DEPLOYMENTS" ]; then
        if [ "${ret_oidc}" -ne 0 ]; then
          keycloak_subsystem=$(cat "${SECURE_DEPLOYMENTS}" | sed ':a;N;$!ba;s/\n//g')
          keycloak_subsystem="<subsystem xmlns=\"urn:jboss:domain:keycloak:1.1\">${keycloak_subsystem}</subsystem>${SUBSYSTEM_END_MARKER}"

          sed -i "s|${SUBSYSTEM_END_MARKER}|${keycloak_subsystem}|" "${CONFIG_FILE}"

          oidc_elytron="$(configure_OIDC_elytron $id)"
          ejb_config="$(configure_ejb $id $app_sec_domain)"
          echo " 
            $elytron_assert
            $oidc_elytron
            $ejb_config" >> ${CLI_SCRIPT_FILE}
          is_oidc="true"
        else
          log_warning "keycloak subsystem already exists, no configuration applied"
        fi
      fi

      if [ -f "$SECURE_SAML_DEPLOYMENTS" ]; then
        if [ "${ret_saml}" -ne 0 ]; then
          keycloak_subsystem=$(cat "${SECURE_SAML_DEPLOYMENTS}" | sed ':a;N;$!ba;s/\n//g')
          keycloak_subsystem="<subsystem xmlns=\"urn:jboss:domain:keycloak-saml:1.1\">${keycloak_subsystem}</subsystem>${SUBSYSTEM_END_MARKER}"

          sed -i "s|${SUBSYSTEM_END_MARKER}|${keycloak_subsystem}|" "${CONFIG_FILE}"

          saml_elytron="$(configure_SAML_elytron $id)"
          echo "
            $elytron_assert
            $saml_elytron"  >> ${CLI_SCRIPT_FILE}
          is_saml="true"
        else
          log_warning "keycloak saml subsystem already exists, no configuration applied"
        fi
      fi
      if [ "$other_exists" == "true" ]; then
        other_config="$(configure_existing_other_cli $is_saml $is_oidc $id)"
        echo "
         $other_config" >> ${CLI_SCRIPT_FILE}
      fi
      undertow_config="$(configure_undertow $id $app_sec_domain)"
      echo "
       $undertow_config" >> ${CLI_SCRIPT_FILE}
      configure_extensions_no_marker
      enable_keycloak_deployments
  elif [ -n "$SSO_URL" ]; then
    enable_keycloak_deployments
    
    oidc_extension="$(configure_OIDC_extension)"
    saml_extension="$(configure_SAML_extension)"
    oidc_elytron="$(configure_OIDC_elytron $id)"
    saml_elytron="$(configure_SAML_elytron $id)"
    elytron_assert="$(elytron_common_assert $app_sec_domain)"
    undertow_config="$(configure_undertow $id $app_sec_domain)"
    ejb_config="$(configure_ejb $id $app_sec_domain)"

    sso_service="$SSO_URL"
    if [ -n "$SSO_SERVICE_URL" ]; then
      sso_service="$SSO_SERVICE_URL"
    fi

    if [ ! -n "${SSO_REALM}" ]; then
      log_warning "Missing SSO_REALM. Defaulting to ${SSO_REALM:=master} realm"
    fi
  
    set_curl
    get_token

    # We can't use output, functions are displaying content.
    cli=
    configure_OIDC_subsystem
    oidc="$cli"
    configure_SAML_subsystem
    saml="$cli"

    if [ ! -z "${oidc}" ]; then
      if [ "${ret_oidc}" -ne 0 ]; then
        echo " 
          $elytron_assert
          $oidc_extension
          $oidc_elytron
          $oidc
          $ejb_config" >> ${CLI_SCRIPT_FILE}
        is_oidc="true"
      else
          log_warning "keycloak subsystem already exists, no configuration applied"
      fi
    fi
    
    if [ ! -z "${saml}" ]; then
      if [ "${ret_saml}" -ne 0 ]; then
        echo "
          $elytron_assert
          $saml_extension
          $saml_elytron
          $saml"  >> ${CLI_SCRIPT_FILE}
        is_saml="true"
      else
        log_warning "keycloak saml subsystem already exists, no configuration applied"
      fi
    fi

    if [ "$other_exists" == "true" ]; then
      other_config="$(configure_existing_other_cli $is_saml $is_oidc $id)"
      echo "
      $other_config" >> ${CLI_SCRIPT_FILE}
    fi
    echo "
     $undertow_config" >> ${CLI_SCRIPT_FILE}
  fi
  
}

function configure_existing_other_cli() {
   is_saml=$1
   is_oidc=$2
   id=$3
   ext_domain="ext-KeycloakDomain-$id"
   ext_factory="ext-keycloak-http-authentication-$id"
   http_auth="/subsystem=elytron/http-authentication-factory=$ext_factory:add(\
      security-domain=$ext_domain,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id,\
      mechanism-configurations=[{mechanism-name=BASIC,mechanism-realm-configurations=[{realm-name=ApplicationRealm}]},\
      {mechanism-name=FORM},{mechanism-name=DIGEST,mechanism-realm-configurations=[{realm-name=ApplicationRealm}]},\
      {mechanism-name=CLIENT_CERT}"
   sec_domain="/subsystem=elytron/security-domain=$ext_domain:add(default-realm=ApplicationRealm,\
      permission-mapper=default-permission-mapper,security-event-listener=local-audit,\
      realms=[{realm=local},{realm=ApplicationRealm,role-decoder=groups-to-roles}"
   if [ "$is_saml" == "true" ]; then
     sec_domain="$sec_domain,{realm=KeycloakSAMLRealm-$id}"
     http_auth="$http_auth,{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[\
       {realm-name=KeycloakSAMLCRealm-$id,realm-mapper=keycloak-saml-realm-mapper-$id}]}"
   fi
   if [ "$is_oidc" == "true" ]; then
     sec_domain="$sec_domain,{realm=KeycloakOIDCRealm-$id}"
     http_auth="$http_auth,{mechanism-name=KEYCLOAK,mechanism-realm-configurations=[\
      {realm-name=KeycloakOIDCRealm-$id,realm-mapper=keycloak-oidc-realm-mapper-$id}]}"
   fi
   sec_domain="$sec_domain])"
   http_auth="$http_auth])"

   cli="
     if (outcome == success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:read-resource
       $sec_domain
       $http_auth
       /subsystem=undertow/application-security-domain=other:remove
       /subsystem=undertow/application-security-domain=other:add(http-authentication-factory=$ext_factory)
       echo Existing other application-security-domain is extended with support for keycloak >> \${warning_file}
     end-if"
    echo "$cli"
}

function configure_OIDC_extension() {
  cli="if (outcome != success) of /extension=org.keycloak.keycloak-adapter-subsystem:read-resource
        /extension=org.keycloak.keycloak-adapter-subsystem:add()
      else
        echo org.keycloak.keycloak-adapter-subsystem extension already added >> \${warning_file}
      end-if"
  echo "$cli"
}

function configure_SAML_extension() {
  cli="
      if (outcome != success) of /extension=org.keycloak.keycloak-saml-adapter-subsystem:read-resource
        /extension=org.keycloak.keycloak-saml-adapter-subsystem:add()
      else
        echo org.keycloak.keycloak-saml-adapter-subsystem extension already added >> \${warning_file}
      end-if"
  echo "$cli"
}

function elytron_common_assert() {
  undertow_sec_domain=$1
  cli="
if (outcome != success) of /subsystem=elytron:read-resource
    echo You have set environment variables to enable sso. Fix your configuration to contain elytron subsystem for this to happen. >> \${error_file}
    quit
end-if
if (outcome != success) of /subsystem=undertow:read-resource
    echo You have set environment variables to enable sso. Fix your configuration to contain undertow subsystem for this to happen. >> \${error_file}
    quit
end-if
if (outcome == success) of /subsystem=undertow/application-security-domain=$undertow_sec_domain:read-resource
    echo Undertow already contains $undertow_sec_domain application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
    quit
end-if"
  echo "$cli"
}

function configure_undertow() {
  id=$1
  security_domain=$2
  cli="
if (outcome == success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:read-resource
    /subsystem=undertow/application-security-domain=${security_domain}:add(http-authentication-factory=keycloak-http-authentication-$id)
else
    echo Undertow not configured, no keycloak-http-authentication-$id found, keycloak subsystems must have been already configured. >> \${warning_file}
end-if"
echo "$cli"
}

function configure_SAML_elytron() {
  id=$1
  cli="
if (outcome != success) of /subsystem=elytron/custom-realm=KeycloakSAMLRealm-$id:read-resource
    /subsystem=elytron/custom-realm=KeycloakSAMLRealm-$id:add(class-name=org.keycloak.adapters.saml.elytron.KeycloakSecurityRealm, module=org.keycloak.keycloak-saml-wildfly-elytron-adapter)
else
    echo Keycloak SAML Realm already installed >> \${warning_file}
end-if

if (outcome != success) of /subsystem=elytron/security-domain=KeycloakDomain-$id:read-resource
    /subsystem=elytron/security-domain=KeycloakDomain-$id:add(default-realm=KeycloakSAMLRealm-$id,permission-mapper=default-permission-mapper,security-event-listener=local-audit,realms=[{realm=KeycloakSAMLRealm-$id}])
else
    echo Keycloak Security Domain already installed. Trying to install Keycloak SAML Realm. >> \${warning_file}
    /subsystem=elytron/security-domain=KeycloakDomain-$id:list-add(name=realms, value={realm=KeycloakSAMLRealm-$id})
end-if

if (outcome != success) of /subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-$id:read-resource
    /subsystem=elytron/constant-realm-mapper=keycloak-saml-realm-mapper-$id:add(realm-name=KeycloakSAMLRealm-$id)
else
    echo Keycloak SAML Realm Mapper already installed >> \${warning_file}
end-if

if (outcome != success) of /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-$id:read-resource
    /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-saml-http-server-mechanism-factory-$id:add(module=org.keycloak.keycloak-saml-wildfly-elytron-adapter)
else
    echo Keycloak SAML HTTP Mechanism Factory already installed >> \${warning_file}
end-if

if (outcome != success) of /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id:read-resource
    /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id:add(http-server-mechanism-factories=[keycloak-saml-http-server-mechanism-factory-$id, global])
else
    echo Keycloak HTTP Mechanism Factory already installed. Trying to install Keycloak SAML HTTP Mechanism Factory. >> \${warning_file}
    /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id:list-add(name=http-server-mechanism-factories, value=keycloak-saml-http-server-mechanism-factory-$id)
end-if

if (outcome != success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:read-resource
    /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:add(security-domain=KeycloakDomain-$id,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id,mechanism-configurations=[{mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLCRealm-$id,realm-mapper=keycloak-saml-realm-mapper-$id}]}])
else
    echo Keycloak HTTP Authentication Factory already installed. Trying to install Keycloak SAML Mechanism Configuration >> \${warning_file}
    /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:list-add(name=mechanism-configurations, value={mechanism-name=KEYCLOAK-SAML,mechanism-realm-configurations=[{realm-name=KeycloakSAMLRealm-$id,realm-mapper=keycloak-saml-realm-mapper-$id}]})
end-if
"
echo "$cli"
}

function configure_OIDC_elytron() {
  id=$1
  cli="
if (outcome != success) of /subsystem=elytron/custom-realm=KeycloakOIDCRealm-$id:read-resource
    /subsystem=elytron/custom-realm=KeycloakOIDCRealm-$id:add(class-name=org.keycloak.adapters.elytron.KeycloakSecurityRealm, module=org.keycloak.keycloak-wildfly-elytron-oidc-adapter)
else
    echo Keycloak OpenID Connect Realm already installed >> \${warning_file}
end-if

if (outcome != success) of /subsystem=elytron/security-domain=KeycloakDomain-$id:read-resource
    /subsystem=elytron/security-domain=KeycloakDomain-$id:add(default-realm=KeycloakOIDCRealm-$id,permission-mapper=default-permission-mapper,security-event-listener=local-audit,realms=[{realm=KeycloakOIDCRealm-$id}])
else
    echo Keycloak Security Domain already installed. Trying to install Keycloak OpenID Connect Realm. >> \${warning_file}
    /subsystem=elytron/security-domain=KeycloakDomain-$id:list-add(name=realms, value={realm=KeycloakOIDCRealm-$id})
end-if

if (outcome != success) of /subsystem=elytron/constant-realm-mapper=keycloak-oidc-realm-mapper-$id:read-resource
    /subsystem=elytron/constant-realm-mapper=keycloak-oidc-realm-mapper-$id:add(realm-name=KeycloakOIDCRealm-$id)
else
    echo Keycloak OpenID Connect Realm Mapper already installed >> \${warning_file}
end-if

if (outcome != success) of /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-oidc-http-server-mechanism-factory-$id:read-resource
    /subsystem=elytron/service-loader-http-server-mechanism-factory=keycloak-oidc-http-server-mechanism-factory-$id:add(module=org.keycloak.keycloak-wildfly-elytron-oidc-adapter)
else
    echo Keycloak OpenID Connect HTTP Mechanism already installed >> \${warning_file}
end-if

if (outcome != success) of /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id:read-resource
    /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id:add(http-server-mechanism-factories=[keycloak-oidc-http-server-mechanism-factory-$id, global])
else
    echo Keycloak HTTP Mechanism Factory already installed. Trying to install Keycloak OpenID Connect HTTP Mechanism Factory. >> \${warning_file}
    /subsystem=elytron/aggregate-http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id:list-add(name=http-server-mechanism-factories, value=keycloak-oidc-http-server-mechanism-factory-$id)
end-if

if (outcome != success) of /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:read-resource
    /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:add(security-domain=KeycloakDomain-$id,http-server-mechanism-factory=keycloak-http-server-mechanism-factory-$id,mechanism-configurations=[{mechanism-name=KEYCLOAK,mechanism-realm-configurations=[{realm-name=KeycloakOIDCRealm-$id,realm-mapper=keycloak-oidc-realm-mapper-$id}]}])
else
    echo Keycloak HTTP Authentication Factory already installed. Trying to install Keycloak OpenID Connect Mechanism Configuration >> \${warning_file}
    /subsystem=elytron/http-authentication-factory=keycloak-http-authentication-$id:list-add(name=mechanism-configurations, value={mechanism-name=KEYCLOAK,mechanism-realm-configurations=[{realm-name=KeycloakOIDCRealm-$id,realm-mapper=keycloak-oidc-realm-mapper-$id}]})
end-if"

  echo "$cli"
}

configure_ejb() {
  id=$1
  security_domain=$2
  
  # We cannot have nested if sentences in CLI, so we use Xpath here to see if the subsystem=ejb3 is in the file
  xpath="\"//*[local-name()='subsystem' and starts-with(namespace-uri(), 'urn:jboss:domain:ejb3:')]\""
  local ret
  testXpathExpression "${xpath}" "ret"

  if [ "${ret}" -eq 0 ]; then
    cli="$cli
if (outcome != success) of /subsystem=ejb3/application-security-domain=$security_domain:read-resource
    /subsystem=ejb3/application-security-domain=$security_domain:add(security-domain=KeycloakDomain-$id)
else
    echo ejb3 already contains $security_domain application security domain. Fix your configuration or set SSO_SECURITY_DOMAIN env variable. >> \${error_file}
    quit
end-if"
    echo "$cli"
  fi
}

function configure_OIDC_subsystem() {
  cli=
  configure_subsystem $OPENIDCONNECT "openid-connect"
  secure_deployments="$cli"
  if [ ! -z "$secure_deployments" ]; then
    subsystem=/subsystem=keycloak
    realm=$subsystem/realm=${SSO_REALM}
    cli="
      ${subsystem}:add
      ${realm}:add(auth-server-url=${SSO_URL},register-node-at-startup=true,register-node-period=600,ssl-required=external,allow-any-hostname=false)"
  
    if [ -n "$SSO_PUBLIC_KEY" ]; then
      cli="$cli
        ${realm}:write-attribute(name=realm-public-key,value=${SSO_PUBLIC_KEY})"
    fi
    
    if [ -n "$SSO_TRUSTSTORE" ] && [ -n "$SSO_TRUSTSTORE_DIR" ]; then
      cli="$cli
        ${realm}:write-attribute(name=truststore,value=${SSO_TRUSTSTORE_DIR}/${SSO_TRUSTSTORE})
        ${realm}:write-attribute(name=truststore-password,value=${SSO_TRUSTSTORE_PASSWORD})"
    else
      cli="$cli
        ${realm}:write-attribute(name=disable-trust-manager,value=true)"
    fi
    cli="$cli
       ${secure_deployments}"
  fi
}

function configure_SAML_subsystem() {
  cli=
  configure_subsystem $SAML "saml"
  secure_deployments="$cli"
  if [ ! -z "$secure_deployments" ]; then
    cli="
       /subsystem=keycloak-saml:add
       ${secure_deployments}
"
  fi
}

function set_curl() {
  CURL="curl -s"
  if [ -n "$SSO_DISABLE_SSL_CERTIFICATE_VALIDATION" ] && [[ $SSO_DISABLE_SSL_CERTIFICATE_VALIDATION == "true" ]]; then
    CURL="curl --insecure -s"
  elif [ -n "$SSO_TRUSTSTORE" ] && [ -n "$SSO_TRUSTSTORE_DIR" ] && [ -n "$SSO_TRUSTSTORE_CERTIFICATE_ALIAS" ]; then
    TMP_SSO_TRUSTED_CERT_FILE=$(mktemp)
    keytool -exportcert -alias "$SSO_TRUSTSTORE_CERTIFICATE_ALIAS" -rfc -keystore ${SSO_TRUSTSTORE_DIR}/${SSO_TRUSTSTORE} -storepass ${SSO_TRUSTSTORE_PASSWORD} -file "$TMP_SSO_TRUSTED_CERT_FILE"
    CURL="curl -s --cacert $TMP_SSO_TRUSTED_CERT_FILE"
    unset TMP_SSO_TRUSTED_CERT_FILE
  fi
}

function enable_keycloak_deployments() {
  if [ -n "$SSO_OPENIDCONNECT_DEPLOYMENTS" ]; then
    explode_keycloak_deployments $SSO_OPENIDCONNECT_DEPLOYMENTS $OPENIDCONNECT
  fi

  if [ -n "$SSO_SAML_DEPLOYMENTS" ]; then
    explode_keycloak_deployments $SSO_SAML_DEPLOYMENTS $SAML
  fi
}

function explode_keycloak_deployments() {
  local sso_deployments="${1}"
  local auth_method="${2}"

  for sso_deployment in $(echo $sso_deployments | sed "s/,/ /g"); do
    if [ ! -d "${JBOSS_HOME}/standalone/deployments/${sso_deployment}" ]; then
      mkdir ${JBOSS_HOME}/standalone/deployments/tmp
      unzip -o ${JBOSS_HOME}/standalone/deployments/${sso_deployment} -d ${JBOSS_HOME}/standalone/deployments/tmp
      rm -f ${JBOSS_HOME}/standalone/deployments/${sso_deployment}
      mv ${JBOSS_HOME}/standalone/deployments/tmp ${JBOSS_HOME}/standalone/deployments/${sso_deployment}
      if [ ! -f ${JBOSS_HOME}/standalone/deployments/${sso_deployment}.dodeploy ]; then
        touch ${JBOSS_HOME}/standalone/deployments/${sso_deployment}.dodeploy
      fi
    fi

    if [ -f "${JBOSS_HOME}/standalone/deployments/${sso_deployment}/WEB-INF/web.xml" ]; then
      requested_auth_method=$(cat ${JBOSS_HOME}/standalone/deployments/${sso_deployment}/WEB-INF/web.xml | xmllint --nowarning --xpath "string(//*[local-name()='auth-method'])" - | sed ':a;N;$!ba;s/\n//g' | tr -d '[:space:]')
      sed -i "s|${requested_auth_method}|${auth_method}|" "${JBOSS_HOME}/standalone/deployments/${sso_deployment}/WEB-INF/web.xml"
    fi
  done
}

function get_token() {

  token=""
  if [ -n "$SSO_USERNAME" ] && [ -n "$SSO_PASSWORD" ]; then
    token=$($CURL --data "username=${SSO_USERNAME}&password=${SSO_PASSWORD}&grant_type=password&client_id=admin-cli" ${sso_service}/realms/${SSO_REALM}/protocol/openid-connect/token)
    if [ $? -ne 0 ] || [[ $token != *"access_token"* ]]; then
      log_warning "Unable to connect to SSO/Keycloak at $sso_service for user $SSO_USERNAME and realm $SSO_REALM. SSO Clients *not* created"
      if [ -z "$token" ]; then
        log_warning "Reason: Check the URL, no response from the URL above, check if it is valid or if the DNS is resolvable."
      else
        log_warning "Reason: $(echo $token | grep -Po '((?<=\<p\>|\<body\>).*?(?=\</p\>|\</body\>)|(?<="error_description":")[^"]*)' | sed -e 's/<[^>]*>//g')"
      fi
      token=
    else
      token=$(echo $token | grep -Po '(?<="access_token":")[^"]*')
      log_info "Obtained auth token from $sso_service for realm $SSO_REALM"
    fi
  else
    log_warning "Missing SSO_USERNAME and/or SSO_PASSWORD. Unable to generate SSO Clients"
  fi

}


function configure_extensions_no_marker() {
  sed -i "s|${EXTENSIONS_END_MARKER}|<extension module=\"org.keycloak.keycloak-adapter-subsystem\"/><extension module=\"org.keycloak.keycloak-saml-adapter-subsystem\"/>${EXTENSIONS_END_MARKER}|" "${CONFIG_FILE}"
}

function configure_subsystem() {
  auth_method=$1
  protocol=$2

  get_application_routes

  cli=
  subsystem=
  deployments=
  redirect_path=

 # We need it to be retrieved prior to iterate the web deployments, needed by CLI
  if [ -n "$token" ]; then
    ### CIAM-690 -- Start of RH-SSO add-on:
    ### -----------------------------------
    ### Add support for RH-SSO 7.5

    realm_signing_key_certificate="xx"
    # SSO Server 7.0
    realm_certificate_url="${sso_service}/admin/realms/${SSO_REALM}"
    response=$(${CURL} -H "Accept: application/json" -H "Authorization: Bearer ${token}" "${realm_certificate_url}")
    if ! grep -q '"certificate":' <<< "${response}"; then
      # SSO Server 7.1+
      realm_certificate_url="${sso_service}/admin/realms/${SSO_REALM}/keys"
      response=$(${CURL} -H "Accept: application/json" -H "Authorization: Bearer ${token}" "${realm_certificate_url}")
      if ! grep -q '"certificate":' <<< "${response}"; then
        echo "Failed to retrieve signing key PEM certificate of the ${SSO_REALM}"
        exit 1
      else
        # SSO Server 7.1 up to 7.4
        if ! grep -q '"use":"SIG"' <<< "${response}"; then
          realm_signing_key_certificate=$(grep -Po '(?<="certificate":")[^"]*' <<< "${response}")
        # SSO Server 7.5+
        else
          realm_signing_key_certificate=$(grep -Po '(?<="certificate":")[^"]*(?=","use":"SIG")' <<< "${response}")
        fi
      fi
    # SSO Server 7.0
    else
     realm_signing_key_certificate=$(grep -Po '(?<="certificate":")[^"]*' <<< "${response}")
    fi

    if [ "x${realm_signing_key_certificate}x" == "xx" ]; then
      echo "Failed to retrieve signing key PEM certificate of the ${SSO_REALM}"
      exit 1
    fi

     ### CIAM-690 -- End of RH-SSO add-on
     ### --------------------------------
  fi

  pushd $JBOSS_HOME/standalone/deployments &> /dev/null
  files=*.war

  for f in $files
  do
    if [[ $f != "*.war" ]];then
      keycloak_configure_secure_deployment "$f" "$realm_signing_key_certificate"
    fi
  done
  popd &> /dev/null
  # discover deployments in $JBOSS_HOME/standalone/data/content
  keycloak_discover_deployed_deployments "$realm_signing_key_certificate"
}

function keycloak_discover_deployed_deployments() {
  realm_certificate="$1"
  local deployments_xpath="//*[local-name()='deployments']//*[local-name()='deployment']"
  local count=$(xmllint --xpath "count($deployments_xpath)" "${CONFIG_FILE}" 2>/dev/null)
  for ((deployment_index=1; deployment_index<=count; deployment_index++)); do
    local deployment_runtime_name=$(xmllint --xpath "string($deployments_xpath[$deployment_index]/@runtime-name)" "${CONFIG_FILE}" 2>/dev/null)
    if [[ "${deployment_runtime_name}" == *.war ]]; then
      local deployment_name=$(xmllint --xpath "string($deployments_xpath[$deployment_index]/@name)" "${CONFIG_FILE}")
      local deployment_content=$(xmllint --xpath "string($deployments_xpath[$deployment_index]//*[local-name()='content']/@sha1)" "${CONFIG_FILE}" 2>/dev/null)
      local deployment_dir1=${deployment_content:0:2}
      local deployment_dir2=${deployment_content:2}
      local deployment_file="${JBOSS_HOME}/standalone/data/content/$deployment_dir1/$deployment_dir2/content"
      if [ -f "$deployment_file" ]; then
        log_info "Checking if name=$deployment_name runtime-name=$deployment_runtime_name content=$deployment_content is secured with SSO"
        local tmp_file="/tmp/${deployment_runtime_name}"
        cp "$deployment_file" "$tmp_file"
        pushd /tmp &> /dev/null
        keycloak_configure_secure_deployment "${deployment_runtime_name}" "${realm_certificate}"
        rm -f "${deployment_runtime_name}"
        popd &> /dev/null
      else
        log_warning "Deployment $deployment_runtime_name not found in content dir, deployment is ignored when scanning for SSO deployment"
      fi
    fi
  done
}

function keycloak_configure_secure_deployment() {
  f="$1"
  realm_certificate="$2"
  module_name=
  web_xml=$(read_web_dot_xml $f WEB-INF/web.xml)
  if [ -n "$web_xml" ]; then
    requested_auth_method=$(echo $web_xml | xmllint --nowarning --xpath "string(//*[local-name()='auth-method'])" - | sed ':a;N;$!ba;s/\n//g' | tr -d '[:space:]')
    if [[ $requested_auth_method == "${auth_method}" ]]; then
      if [ $auth_method == ${SAML} ]; then
        cli="$cli
              /subsystem=keycloak-saml/secure-deployment=${f}:add()"
      else
        cli="$cli
              /subsystem=keycloak/secure-deployment=${f}:add(enable-basic-auth=true, auth-server-url=${SSO_URL}, realm=${SSO_REALM})"
      fi

      if [[ $web_xml == *"<module-name>"* ]]; then
        module_name=$(echo $web_xml | xmllint --nowarning --xpath "//*[local-name()='module-name']/text()" -)
      fi

      local jboss_web_xml=$(read_web_dot_xml $f WEB-INF/jboss-web.xml)
      if [ -n "$jboss_web_xml" ]; then
        if [[ $jboss_web_xml == *"<context-root>"* ]]; then
          context_root=$(echo $jboss_web_xml | xmllint --nowarning --xpath "string(//*[local-name()='context-root'])" - | sed ':a;N;$!ba;s/\n//g' | tr -d '[:space:]')
        fi
        if [ -n "$context_root" ]; then
          if [[ $context_root == /* ]]; then
            context_root="${context_root:1}"
          fi
        fi
      fi

      if [ $f == "ROOT.war" ]; then
        redirect_path=""
        if [ -z "$module_name" ]; then
          module_name="root"
        fi
      else
        if [ -n "$module_name" ]; then
          if [ -n "$context_root" ]; then
            redirect_path="${context_root}/${module_name}"
          else
            redirect_path=$module_name
          fi
        else
          if [ -n "$context_root" ]; then
            redirect_path=$context_root
            module_name=$(echo $f | sed -e "s/.war//g")
          else
            redirect_path=$(echo $f | sed -e "s/.war//g")
            module_name=$redirect_path
          fi
        fi
      fi

      if [ -n "$SSO_CLIENT" ]; then
        keycloak_client=${SSO_CLIENT}
      elif [ -n "$APPLICATION_NAME" ]; then
        keycloak_client=${APPLICATION_NAME}-${module_name}
      else
        keycloak_client=${module_name}
      fi

      if [ -n "$token" ]; then
        configure_client $module_name $protocol $APPLICATION_ROUTES
      fi

      if [ -n "$APPLICATION_NAME" ]; then
        entity_id=${APPLICATION_NAME}-${module_name}
      else
        entity_id=${module_name}
      fi
      if [ $auth_method == ${SAML} ]; then
        if [ -n "$realm_certificate" ]; then
          validate_signature=true
          if [ -n "$SSO_SAML_VALIDATE_SIGNATURE" ]; then
            validate_signature="$SSO_SAML_VALIDATE_SIGNATURE"
          fi
        else
          validate_signature=true
        fi
        cli="$cli
              /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}:add(sslPolicy=EXTERNAL)
              /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/Key=Key:add(signing=true,encryption=true)
              /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/IDP=idp:add(signatureAlgorithm=RSA_SHA256, \
              signatureCanonicalizationMethod=\"http://www.w3.org/2001/10/xml-exc-c14n#\", SingleSignOnService={signRequest=true,requestBinding=POST,\
              bindingUrl=${SSO_URL}/realms/${SSO_REALM}/protocol/saml,validateSignature=${validate_signature}},\
              SingleLogoutService={validateRequestSignature=${validate_signature},validateResponseSignature=${validate_signature},signRequest=true,\
              signResponse=true,requestBinding=POST,responseBinding=POST, postBindingUrl=${SSO_URL}/realms/${SSO_REALM}/protocol/saml,\
              redirectBindingUrl=${SSO_URL}/realms/${SSO_REALM}/protocol/saml})"
        if [ -n "$realm_certificate" ]; then
          cli="$cli
                  /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/IDP=idp/Key=Key:add(signing=true,CertificatePem=\"${realm_certificate}\")"
        fi
        if [ -n "$SSO_SAML_KEYSTORE" ] && [ -n "$SSO_SAML_KEYSTORE_DIR" ]; then
          cli="$cli
                  /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/Key=Key:write-attribute(name=KeyStore.file,value=${SSO_SAML_KEYSTORE_DIR}/${SSO_SAML_KEYSTORE})"
        fi
        if [ -n "$SSO_SAML_KEYSTORE_PASSWORD" ]; then
          cli="$cli
                  /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/Key=Key:write-attribute(name=KeyStore.password,value=${SSO_SAML_KEYSTORE_PASSWORD})
                  /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/Key=Key:write-attribute(name=KeyStore.PrivateKey-password,value=${SSO_SAML_KEYSTORE_PASSWORD})"
        fi
        if [ -n "$SSO_SAML_CERTIFICATE_NAME" ]; then
          cli="$cli
                  /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/Key=Key:write-attribute(name=KeyStore.Certificate-alias,value=${SSO_SAML_CERTIFICATE_NAME})
                  /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}/Key=Key:write-attribute(name=KeyStore.PrivateKey-alias,value=${SSO_SAML_CERTIFICATE_NAME})"
        fi
      fi
      if [ $auth_method == $OPENIDCONNECT ]; then
        cli="$cli
               /subsystem=keycloak/secure-deployment=${f}:write-attribute(name=resource, value=${keycloak_client})"
      fi
      if [ $auth_method == $OPENIDCONNECT ] && [ -n "${SSO_SECRET}" ]; then
        cli="$cli
              /subsystem=keycloak/secure-deployment=${f}/credential=secret:add(value=${SSO_SECRET})"
      fi

      if [ -n "$SSO_ENABLE_CORS" ]; then
        cors=${SSO_ENABLE_CORS}
      else
        cors=false
      fi

      if [ $auth_method == $OPENIDCONNECT ]; then
        cli="$cli
            /subsystem=keycloak/secure-deployment=${f}:write-attribute(name=enable-cors, value=${cors})"
      fi

      if [ -n "$SSO_BEARER_ONLY" ]; then
        bearer=${SSO_BEARER_ONLY}
      else
        bearer=false
      fi
      if [ $auth_method == $OPENIDCONNECT ]; then
        cli="$cli
            /subsystem=keycloak/secure-deployment=${f}:write-attribute(name=bearer-only, value=${bearer})"
      fi

      if [ -n "$SSO_SAML_LOGOUT_PAGE" ]; then
        logoutPage="${SSO_SAML_LOGOUT_PAGE}"
      else
        logoutPage=/
      fi

      if [ $auth_method == ${SAML} ]; then
        cli="$cli
              /subsystem=keycloak-saml/secure-deployment=${f}/SP=${entity_id}:write-attribute(name=logoutPage,value=$logoutPage)"
      fi

      if [ -n "$SSO_PRINCIPAL_ATTRIBUTE" ]; then
        if [ $auth_method == $OPENIDCONNECT ]; then
          cli="$cli
              /subsystem=keycloak/secure-deployment=${f}:write-attribute(name=principal-attribute, value=${SSO_PRINCIPAL_ATTRIBUTE})"
        fi
      fi

      log_info "Configured keycloak subsystem for $protocol module $module_name from $f"
    fi
  fi
}

function configure_client() {
  module_name=$1
  protocol=$2
  application_routes=$3

  IFS_save=$IFS
  IFS=";"
  redirects=""
  endpoint=""
  for route in ${application_routes}; do
    if [ -n "$redirect_path" ]; then
      redirects="$redirects,\"${route}/${redirect_path}/*\""
      endpoint="${route}/${redirect_path}/"
    else
      redirects="$redirects,\"${route}/*\""
      endpoint="${route}/"
    fi
  done
  redirects="${redirects:1}"
  IFS=$IFS_save

  if [[ $protocol == "saml" ]]
  then
    client_config="{\"adminUrl\":\"${endpoint}saml\""
    if [ -n "$SSO_SAML_KEYSTORE" ] && [ -n "$SSO_SAML_KEYSTORE_DIR" ] && [ -n "$SSO_SAML_CERTIFICATE_NAME" ] && [ -n "$SSO_SAML_KEYSTORE_PASSWORD" ]; then
      keytool -export -keystore ${SSO_SAML_KEYSTORE_DIR}/${SSO_SAML_KEYSTORE} -alias $SSO_SAML_CERTIFICATE_NAME -storepass $SSO_SAML_KEYSTORE_PASSWORD -file $JBOSS_HOME/standalone/configuration/keycloak.cer
      base64 $JBOSS_HOME/standalone/configuration/keycloak.cer > $JBOSS_HOME/standalone/configuration/keycloak.pem
      pem=$(cat $JBOSS_HOME/standalone/configuration/keycloak.pem | sed ':a;N;$!ba;s/\n//g')

      server_signature=
      if [ -n "$SSO_SAML_VALIDATE_SIGNATURE" ]; then
        server_signature=",\"saml.server.signature\":\"${SSO_SAML_VALIDATE_SIGNATURE}\""
      fi
      client_config="${client_config},\"attributes\":{\"saml.signing.certificate\":\"${pem}\"${server_signature}}"
    fi
  else
    service_addr=$(hostname -i)
    client_config="{\"redirectUris\":[${redirects}]"

    if [ -n "$HOSTNAME_HTTP" ]; then
      client_config="${client_config},\"adminUrl\":\"http://\${application.session.host}:8080/${redirect_path}\""
    else
      client_config="${client_config},\"adminUrl\":\"https://\${application.session.host}:8443/${redirect_path}\""
    fi
  fi

  if [ -n "$SSO_BEARER_ONLY" ] && [ "$SSO_BEARER_ONLY" == "true" ]; then
    client_config="${client_config},\"bearerOnly\":\"true\""
  fi

  client_config="${client_config},\"clientId\":\"${keycloak_client}\""
  client_config="${client_config},\"protocol\":\"${protocol}\""
  client_config="${client_config},\"baseUrl\":\"${endpoint}\""
  client_config="${client_config},\"rootUrl\":\"\""
  client_config="${client_config},\"publicClient\":\"false\",\"secret\":\"${SSO_SECRET}\""
  client_config="${client_config}}"

  if [ -z "$SSO_SECRET" ]; then
    log_warning "ERROR: SSO_SECRET not set. Make sure to generate a secret in the SSO/Keycloak client '$module_name' configuration and then set the SSO_SECRET variable."
  fi

  result=$($CURL -H "Content-Type: application/json" -H "Authorization: Bearer ${token}" -X POST -d "${client_config}" ${sso_service}/admin/realms/${SSO_REALM}/clients)

  if [ -n "$result" ]; then
    log_warning "ERROR: Unable to register $protocol client for module $module_name in realm $SSO_REALM on $redirects: $result"
  else
    log_info "Registered $protocol client for module $module_name in realm $SSO_REALM on $redirects"
  fi
}

function read_web_dot_xml {
  local jarfile="${1}"
  local filename="${2}"
  local result=

  if [ -d "$jarfile" ]; then
    if [ -e "${jarfile}/${filename}" ]; then
        result=$(cat ${jarfile}/${filename})
    fi
  else
    file_exists=$(unzip -l "$jarfile" "$filename")
    if [[ $file_exists == *"$filename"* ]]; then
      result=$(unzip -p "$jarfile" "$filename" | xmllint --format --recover --nowarning - | sed ':a;N;$!ba;s/\n//g')
    fi
  fi
  echo "$result"
}

function get_application_routes {
  
  if [ -n "$HOSTNAME_HTTP" ]; then
    route="http://${HOSTNAME_HTTP}"
  fi

  if [ -n "$HOSTNAME_HTTPS" ]; then
    secureroute="https://${HOSTNAME_HTTPS}"
  fi

  if [ -z "$HOSTNAME_HTTP" ] && [ -z "$HOSTNAME_HTTPS" ]; then
    log_warning "HOSTNAME_HTTP and HOSTNAME_HTTPS are not set, trying to discover secure route by querying internal APIs"
    APPLICATION_ROUTES=$(discover_routes)
  else
    if [ -n "$route" ] && [ -n "$secureroute" ]; then
      APPLICATION_ROUTES="${route};${secureroute}"
    elif [ -n "$route" ]; then
      APPLICATION_ROUTES="${route}"
    elif [ -n "$secureroute" ]; then
      APPLICATION_ROUTES="${secureroute}"
    fi
  fi

  APPLICATION_ROUTES=$(add_route_with_default_port ${APPLICATION_ROUTES})
}


# Adds an aditional route to the route list with the default port only if the route doesn't have a port
# {1} Route or Route list (splited by semicolon)
function add_route_with_default_port() {
  local routes=${1}
  local routesWithPort="";
  local IFS_save=$IFS
  IFS=";"

  for route in ${routes}; do
    routesWithPort="${routesWithPort}${route};"
    # this regex match URLs with port
    if ! [[ "${route}" =~ ^(https?://.*):(\d*)\/?(.*)$ ]]; then
      if [[ "${route}" =~ ^(http://.*)$ ]]; then
        routesWithPort="${routesWithPort}${route}:80;"
      elif [[ "${route}" =~ ^(https://.*)$ ]]; then
        routesWithPort="${routesWithPort}${route}:443;"
      fi
    fi
  done
  
  IFS=$IFS_save

  echo ${routesWithPort%;}
}

# Tries to discover the route using the pod's hostname
function discover_routes() {
  local service_name=$(keycloak_compute_service_name)
  echo $(query_routes_from_service  $service_name)
}

# Verify if the container is on OpenShift. The variable K8S_ENV could be set to emulate this behavior
function is_running_on_openshift() {
  if [ -e /var/run/secrets/kubernetes.io/serviceaccount/token ] || [ "${K8S_ENV}" = true ] ; then
    return 0
  else
    return 1
  fi
}

# Queries the Routes from the Kubernetes API based on the service name
# ${1} - service name
# see: https://docs.openshift.com/container-platform/3.11/rest_api/apis-route.openshift.io/v1.Route.html#Get-apis-route.openshift.io-v1-routes
function query_routes_from_service() {
  local serviceName=${1}
  # only execute the following lines if this container is running on OpenShift
  if is_running_on_openshift; then
    local namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    local token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    local response=$(curl -s -w "%{http_code}" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
        -H "Authorization: Bearer $token" \
        -H 'Accept: application/json' \
        ${KUBERNETES_SERVICE_PROTOCOL:-https}://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}/apis/route.openshift.io/v1/namespaces/${namespace}/routes?fieldSelector=spec.to.name=${serviceName})
    if [[ "${response: -3}" = "200" && "${response::- 3},," = *"items"* ]]; then
      response=$(echo ${response::- 3})
      echo $(keycloak_get_routes_from_json "$response")
    else
      log_warning "Fail to query the Route using the Kubernetes API, the Service Account might not have the necessary privileges."
      
      if [ ! -z "${response}" ]; then
        log_warning "Response message: ${response::- 3} - HTTP Status code: ${response: -3}"
      fi
    fi
  fi
}

function keycloak_compute_service_name() {
  IFS_save=$IFS
  IFS='-' read -ra pod_name_array <<< "${HOSTNAME}"
  local bound=$((${#pod_name_array[@]}-2))
  local name=
  for ((i=0;i<bound;i++)); do
    name="$name${pod_name_array[$i]}"
    if (( i < bound-1 )); then
      name="$name-"
    fi
  done
  IFS=$IFS_save
  echo $name
}

function keycloak_get_routes_from_json() {
  json_reply="${1}"
  json_routes=$(jq -r '.items[].spec|if .tls then "https" else "http" end + "://" + .host' <<< $json_reply)
  IFS_save=$IFS
  json_routes="$(readarray -t JSON_ROUTES_ARRAY <<< "${json_routes}"; IFS=';'; echo "${JSON_ROUTES_ARRAY[*]}")"
  IFS=$IFS_save
  echo "${json_routes}"
}