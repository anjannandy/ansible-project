#!/bin/bash
# Keycloak Certificate Installation Commands

# Copy certificates to Keycloak server
scp ./keycloak-ssl-certs/keycloak.crt root@10.0.2.10:/opt/keycloak/conf/ssl/
scp ./keycloak-ssl-certs/keycloak.key root@10.0.2.10:/opt/keycloak/conf/ssl/
scp ./keycloak-ssl-certs/keycloak-ca.crt root@10.0.2.10:/opt/keycloak/conf/ssl/

# Set proper permissions
ssh root@10.0.2.10 "chown keycloak:keycloak /opt/keycloak/conf/ssl/* && chmod 600 /opt/keycloak/conf/ssl/*.key && chmod 644 /opt/keycloak/conf/ssl/*.crt"

# Restart Keycloak service
ssh root@10.0.2.10 "systemctl restart keycloak"
