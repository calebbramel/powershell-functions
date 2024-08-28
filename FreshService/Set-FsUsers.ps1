$FsAgentADGroups = @{
    # AD Group = @{ roleID; groupID } 
    "ACC-APP-FreshService-Group1" = [PSCustomObject]@{
        fsroleID = 00000000000 # IT Agent 'role'
        fsGroup = $Group1Int   # Member of Group1
    }
    "ACC-APP-FreshService-Group2" = [PSCustomObject]@{
        fsroleID = 11111111111 # IT Supervisor 'role'
        fsGroup = $Group2Int   # Member of Group2
    }
}

$FsAdminADGroups = @{
    # Admin groups are global by default and cannot be scoped to groups.
    "ACC-APP-FreshService-Admins" = 22222222222       # ITSM Admin
    "ACC-APP-FreshService-GlobalAdmins" = 33333333333 # Account Admin
}

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
    $token = Get-AutomationVariable -Name "FreshServiceAPIKey"
    $headers = @{
        "Content-Type" = "application/json";
        Authorization = "Basic $token" 
    }
    $credential = Get-AutomationPSCredential -Name 'ServiceAccount'
    $adDomain = "ad.contoso.com"
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

Set-FsUsers
