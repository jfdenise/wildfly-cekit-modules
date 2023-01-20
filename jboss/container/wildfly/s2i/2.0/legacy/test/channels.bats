#!/usr/bin/env bats
source $BATS_TEST_DIRNAME/../artifacts/opt/jboss/container/wildfly/s2i/galleon/s2i_galleon

@test "No channel defined" {
  run galleon_parse_channels
  [ "${output}" = "" ]
  [ "$status" -eq 0 ]
}

@test "Channel Manifests coordinates and URLS" {
  expected="<channels><channel><manifest-coordinate><groupId>org.foo</groupId><artifactId>bar</artifactId><version>1.0</version></manifest-coordinate></channel>\
<channel><manifest-coordinate><groupId>com.foo</groupId><artifactId>bar2</artifactId></manifest-coordinate></channel><channel><manifest-coordinate><url>file:///tmp/manifest.yaml</url></manifest-coordinate></channel>\
<channel><manifest-coordinate><url>http://example.com/channel2.yaml</url></manifest-coordinate></channel></channels>"
  GALLEON_PROVISION_CHANNELS="org.foo:bar:1.0,com.foo:bar2,file:///tmp/manifest.yaml,http://example.com/channel2.yaml"
  run galleon_parse_channels
  echo "${output}"
  echo "${expected}"
  [ "${output}" = "${expected}" ]
  [ "$status" -eq 0 ]
}

@test "Channel URL" {
  expected="<channels><channel><manifest-coordinate><groupId>org.foo</groupId><artifactId>bar</artifactId><version>1.0</version></manifest-coordinate></channel>\
<channel><manifest-coordinate><groupId>com.foo</groupId><artifactId>bar2</artifactId></manifest-coordinate></channel><channel><url>file:///tmp/channel.yaml</url></channel>\
<channel><manifest-coordinate><url>http://example.com/channel2.yaml</url></manifest-coordinate></channel></channels>"
  GALLEON_PROVISION_CHANNELS="org.foo:bar:1.0,com.foo:bar2,channel-url:file:///tmp/channel.yaml,http://example.com/channel2.yaml"
  run galleon_parse_channels
  echo "${output}"
  echo "${expected}"
  [ "${output}" = "${expected}" ]
  [ "$status" -eq 0 ]
}