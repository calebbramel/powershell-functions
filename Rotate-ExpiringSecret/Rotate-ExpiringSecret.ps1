# Rotate Expiring Secret

## Version
1.0

## Description
Ingests webhook from Azure Event listener, then attempts to find a matching app registration.
If exists, generate a new client secret and upload to KeyVault.
Search ADO Projects for connections using the AppRegistration, and updates the connection secret.
Afterward, delete secrets for the specified application with an expiry in the past.

**Author:** Caleb Bramel

## Requirements

### Azure
- Read Access to target Subscription(s)

### Azure DevOps
- Basic License
- Endpoint Administrator
- Project Contributor

### Enterprise App
- `microsoft.directory/applications/credentials/update`
- `microsoft.directory/servicePrincipals/credentials/update`
- `microsoft.directory/servicePrincipals/synchronizationCredentials/manage`

### KeyVault
- Key Vault Secrets Officer (Secret Get/List/Set)

### Modules
- Az
- Az.Accounts
- Az.Resources
- AzureAD

### Webhook format
- Cloud Event Schema v1.0

## ToDo
- Account for non-secret authentication types such as certificate auth.
- Tighten search scope for Service Principal matches.
