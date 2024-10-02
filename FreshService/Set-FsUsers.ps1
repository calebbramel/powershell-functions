function Convert-UPNToURLEncoded {
    param (
        [string]$UPN,
        [switch]$agent
    )
    Add-Type -AssemblyName System.Web
    $encodedUPN = [System.Web.HttpUtility]::UrlEncode($UPN)
    if ($agent) {
        $formattedString = "query=`"email:%27$encodedUPN%27`"" # (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)")
    } else {
        $formattedString = "query=`"primary_email:%27$encodedUPN%27`"" # (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/agents?$(Convert-UPNToURLEncoded -agent $user.UserPrincipalName)").agents[0]

    }
    
    return $formattedString
}

function Set-FsUsers {
    param (
        $token,
        $credential,
        $adDomain,
        $fsDomain
    )
    $headers = @{
        "Content-Type" = "application/json";
        Authorization = "Basic $token" 
    }
    
    foreach ($group in $FsRequesterADGroups.GetEnumerator()) {
        Write-Output("Setting users from $($group.Key)")
        $groupMembers = Get-AdGroupMember -server $adDomain -identity $group.Key -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        foreach ($samAccountName in $groupMembers.samAccountName) {
            $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
            $uri = "https://$($fsDomain).freshservice.com/api/v2/requesters?$(Convert-UPNToURLEncoded $user.UserPrincipalName)"
            $groupId = $($FsRequesterADGroups[$group.Key]
            $fsUserID = ((Invoke-RestMethod -Headers $headers -Method GET -Uri $uri).requesters[0]).id
            Start-Sleep 1
            Invoke-RestMethod -Headers $headers -Method POST "https://$($fsDomain).freshservice.com/api/v2/requester_groups/$($groupId)/members/$fsUserID"
        }
        Write-Output("`nCurrent members:")
        (Invoke-RestMethod -Headers $headers -Method GET "https://$($fsDomain).freshservice.com/api/v2/requester_groups/$($groupId)/members").requesters
    }

    foreach ($group in $FsAgentADGroups.GetEnumerator()) {
        $fsGroupMembers = @()
        Write-Output("Setting users from $($group.Key)")
        $groupMembers = Get-AdGroupMember -server $adDomain -identity $group.Key -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        foreach ($samAccountName in $groupMembers.samAccountName) {
            $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
            $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]
            # Convert to Agent if not already
            if (-not($fsUser.is_agent) -and (-not($fsUser -eq $null))) {
                try {
                    Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters/$($fsUser.ID)/convert_to_agent" -Method PUT -Headers $headers
                }
                catch {
                    Write-Error("Failed converting requester: $($_.Exception)")
                }
            }
            if ($group.value.fsGroup -like (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/agents?$(Convert-UPNToURLEncoded -agent $user.UserPrincipalName)").agents[0].member_of) {
                $body = @{
                    roles = @(
                        @{
                            role_id = $group.Value.fsroleID
                            assignment_scope = 'entire_helpdesk'
                        }
                    )
                }

                foreach ($adminGroup in $FsAdminADGroups.Keys){
                    $adminGroupMembers = Get-ADGroupMember -server $adDomain -identity $adminGroup -credential $credential
                        if ($adminGroupMembers.samAccountName -contains $user.samaccountName) {
                        # Admin access is a global role and not a group.
                            $body.roles += @{
                                role_id = $FsAdminADGroups[$adminGroup]
                                assignment_scope = 'entire_helpdesk'
                        }
                    }
                }
            }
            (Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/agents/$($fsUser.ID)?can_see_all_tickets_from_associated_departments=True" -Method Put -Headers $headers -Body ($body | ConvertTo-JSON)).agent
            $fsGroupMembers += $fsUser.ID
            }
        $groupBody = @{
            members = $fsGroupMembers
        } | ConvertTo-Json
        (Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/groups/$($group.value.fsGroup)" -Method Put -Headers $headers -Body $groupBody).Value
    }
}
