#!/bin/bash

function oidc_keycloak_prepareEnv() {
# These 2 are used internally
  unset APPLICATION_NAME

# Used as an attribute in the subsystem secure-deployment and in the client config sent to server.
  unset SSO_BEARER_ONLY
  # Used to compute client routes
  unset HOSTNAME_HTTP
  unset HOSTNAME_HTTPS
 # To disable curl security
  unset SSO_DISABLE_SSL_CERTIFICATE_VALIDATION
# In the secure-deployment subsystem
  unset SSO_ENABLE_CORS
# To retrieve token using curl
  unset SSO_PASSWORD
# Attribute set in secure deployment
  unset SSO_PRINCIPAL_ATTRIBUTE
# realm public key in dubsystem secure deployment
  unset SSO_PUBLIC_KEY
# SSO Realm used in curl API and subsystem realm, default to master
  unset SSO_REALM
# Set in subsystem secure deployment and in client config sent to rest endpoint
  unset SSO_SECRET
 # Used to do CURL and configure realm in subsystem
  unset SSO_TRUSTSTORE
  unset SSO_TRUSTSTORE_CERTIFICATE_ALIAS
  unset SSO_TRUSTSTORE_DIR
  unset SSO_TRUSTSTORE_PASSWORD
  unset SSO_URL
# To retrieve token thanks to REST API.
  unset SSO_USERNAME
}