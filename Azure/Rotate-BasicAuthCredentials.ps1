Function Rotate-BasicAuthCredentials {
    param (
        [string]$ApiId,
        [string]$ApiManagementService,
        [string]$ResourceGroupName,
        [string]$SubscriptionID,
        [string]$User
    )
    <# Authentication #>
    try {
        Write-Output("Authenticating to Azure")
        Connect-AzAccount -Identity
        Set-AzContext -SubscriptionID $SubscriptionID
    }
    catch{
        Write-Output("Error authenticating to Azure")
        Write-Error($_)
    }

    <# Process #>
    try{
        Write-Output("Downloading API Policy")
        $apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroupName -ServiceName $ApiManagementService      
        Get-AzApiManagementPolicy -context $apimContext -ApiId $ApiId -SaveAs "$pwd/APIPolicy.xml"
    }
    catch{
        Write-Output("Error downloading API Policy")
        Write-Error($_)
    }

    try{
        Write-Output("Writing XML Policy")
        [xml]$xml = Get-Content ./APIPolicy.xml
        $newPassword = Get-RandomPassword
        Write-Output("`nOriginal XML content:")
        Write-Output($(Get-Content ./APIPolicy.xml -Raw))

        # Extract current passwords from the condition attribute
        $condition = $xml.policies.inbound.choose.when.condition
        $pattern = "$($User):([^""]+)"
        $matches = [regex]::Matches($condition, $pattern)

        $cred1 = $matches.Value[0]
        $cred2 = $matches.Value[1]

        # Cred1, Cred2 = Cred2, NewPassword
        Write-Output("`nReplacing '$Cred2' with '$($User):$newPassword'")
        Write-Output("Replacing '$Cred1' with '$Cred2'")
        $condition = $condition -replace [regex]::Escape($cred2), "$($User):$newPassword"
        $condition = $condition -replace [regex]::Escape($cred1), $cred2

        $xml.policies.inbound.choose.when.condition = $condition

        $xml.Save("APIPolicy_new.xml")

        $policyContent = Get-Content -Path "./APIPolicy_new.xml" -Raw
        Write-Output("`nNew XML Content:")
        Write-Output($policyContent)
    }
    catch{
        Write-Output("Error writing XML Policy")
        Write-Error($_)
    }
    try{
        Write-Output("Updating API Policy")
        Set-AzApiManagementPolicy -Context $apimContext -ApiId $ApiId -Policy $policyContent
    }
    catch{
        Write-Output("Error updating API Policy")
        Write-Error($_)
    }
    Write-Output("API Policy Updated successfully.")
}
