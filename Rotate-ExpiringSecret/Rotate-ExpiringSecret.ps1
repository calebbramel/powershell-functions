Param(
    [parameter (Mandatory=$false)]
    [object] $WebhookData
)

# Static Variables
$apiVersion = "7.1"
$erroraction = "Stop"
$azureDevOpsResourceId = "499b84ac-1321-427f-aa17-267ca6975798"

$TenantID = $'TenantID'
$organizations = @(
    "org1"
)
$expiryDate = (Get-Date).AddDays(+37).ToString("yyyy-MM-ddTHH:mm:ssZ")

try{
    # Structure Webhook Input Data
    if ($WebhookData.WebhookName) { # Live Payload
        Write-Output("Parsing WebHook")
        $RequestBody = ConvertFrom-Json($WebhookData.RequestBody)
        $AppName         =     ($RequestBody.Subject)
        $vaultName       =     ($RequestBody.source -split '\/')[-1]
        $subscriptionID    =     ($RequestBody.source -split '\/')[2]
    } 
    elseIf ($WebhookData) {         # Test JSON 
        Write-Output("Converting string to JSON")
        $RequestBody = ConvertFrom-Json -InputObject((ConvertFrom-Json -InputObject $WebhookData).RequestBody)
        $AppName = $RequestBody.Subject
        $vaultName = ($RequestBody.source -split '\/')[-1]
        $subscriptionID = ($RequestBody.source -split '\/')[2]
    }
    else {
        Write-Error("Error Parsing Webhook Data")
        throw
    }
}
catch {
    Write-Error("Data Did not appear to be formatted as JSON object or string")
    throw
}

try{
    Write-Output("Authenticating to Entra ID")
    $az = Connect-AzAccount -Identity -TenantId $TenantID -SubscriptionId $subscriptionID
    $az = Set-AzContext -SubscriptionId $subscriptionID -DefaultProfile $az.context -TenantId $TenantID
    $token = (Get-AzAccessToken -ResourceUrl $azureDevOpsResourceId).Token # By default expires in 1 day 
    $APIheaders = @{
        Authorization = "Bearer $token"
        'Content-Type' = "application/json"
    }
}
catch{
    Write-Error("Error Authenticating to Entra ID")
    Write-Error($_)
    throw
}


try{
    Write-Output("Retrieving App Registration")
    $AppRegistrationID = (Get-AzADApplication -Filter "DisplayName eq '$AppName'").ID
    $ServicePrincipalID = (Get-AzADApplication -Filter "DisplayName eq '$AppName'").AppID
    if (($AppRegistrationID -eq $null) -or ($ServicePrincipalID -eq $null)){
        Write-Error("No matching App Registration")
        throw
    }
}
catch{
    Write-Error("Error Retrieving App Registration")
    Write-Error($_)
    throw
}

try{
    Write-Output("Generating and Storing Secret")
    $secretvalue = ConvertTo-SecureString((New-AzADAppCredential -ObjectID $AppRegistrationID -EndDate $expiryDate).SecretText) -AsPlainText -Force
    $vaultSecret = Set-AzKeyVaultSecret -VaultName $vaultName -Name $AppName -SecretValue $secretvalue -Expires $expiryDate
    Write-Output("["+ $AppName + "] Secret stored in " + "[" + $vaultName + "]. New expiry: [" + $expiryDate + "]")
}
catch{
    Write-Error("Error Generating and Storing Secret")
    Write-Error($_)
    throw
}

# Making API Calls
try{
    Write-Output("Authenticating to Azure DevOps.")
    $serviceConnections = @()
    foreach($organization in $organizations) {
        $projects = Invoke-RestMethod -Headers $APIheaders -Method GET -Uri "https://dev.azure.com/$organization/_apis/projects?api-version=$apiVersion"
        Write-Output("Successfully Authenticated to $organization.")
        Write-Output("Looking for Endpoints with ID: $ServicePrincipalID")
        foreach ($project in $projects.value) {
            $projectName = $project.name
            $endPoints = Invoke-RestMethod -Headers $APIheaders -Method GET -Uri "https://dev.azure.com/$organization/$projectName/_apis/serviceendpoint/endpoints?api-version=$apiVersion"
# Debug Search
#            foreach ($endpoint in $endpoints.value) {
                if (-not($endpoint.authorization.parameters.serviceprincipalid -eq $ServicePrincipalID )) {
                        # -and ($endpoint.type -eq "azurerm") `
                        # -and ($endpoint.authorization.parameters.authenticationType -eq "spnKey")) {
#                    Write-Output("Skipping " + $endpoint.authorization.parameters.serviceprincipalid)
                    continue
                }
                else{
                    if ($endpoint.authorization.parameters.PSObject.Properties.Name -notcontains 'serviceprincipalkey'){
                        $endpoint.authorization.parameters | Add-Member -NotePropertyName 'serviceprincipalkey' -NotePropertyValue $ApplicationSecret
                    }    
                    $endpoint.authorization.parameters.serviceprincipalkey = $ApplicationSecret
                    $serviceConnections += $endpoint
                    $endpoint | Add-Member -NotePropertyName 'organization' -NotePropertyValue $organization
                }
        }
    }
}
catch {
    Write-Error($_)
}

if ($serviceConnections -eq $null){

    try { 
        $responses = @()
        foreach ($serviceConnection in $serviceConnections) {
            $serviceConnectionID = $serviceConnection.ID
            $ProjectName = $serviceConnection.serviceEndpointProjectReferences.projectReference.name
            $organization = $serviceConnection.organization
            Write-Output("Updating the Service Connection [" + $($serviceConnection.name) + "] from project ["+ $ProjectName + "] in [" + $organization + "]")
            $response = Invoke-RestMethod -Uri "https://dev.azure.com/$organization/$ProjectName/_apis/serviceendpoint/endpoints?endpointID=$serviceConnectionID&api-version=$apiVersion" -Headers $headers -Method PUT -Body ($serviceConnection | ConvertTo-Json -Depth 4) -ContentType application/json
            }
        Write-Output("Connection(s) Updated.")
    }
    catch {
        Write-Error("Error updating " + $serviceConnection.Name)
        Write-Error($_)
    }
}
else{
    Write-Output("No AzureDevOps Endpoints to update.")
} 

try{
    Write-Output("Pruning Secrets")
    $expiredSecrets = (Get-AzADAppCredential -ObjectID $AppRegistrationID | Where {$_.EndDateTime -lt (Get-Date).AddDays(+30)})
    ForEach ($secret in $expiredSecrets) {
        Remove-AzADAppCredential -ObjectID $AppRegistrationID -KeyId $secret.keyid
    }
    Write-Output("Secrets pruned successfully.")
    exit 0
}
catch{
    Write-Error("Error Pruning Secrets")
    Write-Error($_)
    exit 1
}
