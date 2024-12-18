$FsRequesterADGroups = @{
    #"FsChangeRequesters" = 00000000000
}
$FsAgentADGroups = @{
    # AD Group = @{ roleID; groupID; [optional]scope } 

    "FreshService-Group1" = [PSCustomObject]@{
        fsroleID = 11111111111 # IT Agent 'role'
        fsGroup  = 22222222222 # Member of CloudEng
        scope    = 'entire_helpdesk'
    }
}

$FsGlobalADGroups = @{
    # Admin groups are scoped to the workspace by default and cannot be scoped to groups.
    "FsAccountAdmin"     = 33333333333 # Account Admin, Most privilaged

    # Agent Roles to be used globally
    "FsMajorIncidentPromoters" = 44444444444
}

# Assign just the Global Groups to users in the 'NoGroup' AD Group
$noGroup = "FreshService-NoGroup"

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
        [string]$adDomain,
        [pscredential]$credential,
        [switch]$convertRequesters,
        [string]$fsDomain,
        [string]$token
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
            $groupId = $FsRequesterADGroups[$group.Key]
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
        $groupMembers = Get-AdGroupMember -server $adDomain -identity "$($group.Key)-Members" -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        foreach ($samAccountName in $groupMembers.samAccountName) {
            $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
            $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]
            
            # Requester to Agent Conversion
            if (-not($fsUser.is_agent) -and (-not($fsUser -eq $null))) {
                if(-not($convertRequesters)) {
                    continue  
                } 
                else {
                    try {
                        Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters/$($fsUser.ID)/convert_to_agent" -Method PUT -Headers $headers
                    }
                    catch {
                        Write-Error("Failed converting requester: $($_.Exception)")
                    }
                }
            }

            # Agent Role Gathering
            if ($group.value.fsGroup -like (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/agents?$(Convert-UPNToURLEncoded -agent $user.UserPrincipalName)").agents[0].member_of) {

                if ($group.value.scope) {
                    $assignmentScope = $group.value.scope
                } else {
                    $assignmentScope = 'entire_helpdesk'
                }

                $body = @{
                    roles = @(
                        @{
                            role_id = $group.Value.fsroleID
                            assignment_scope = $assignmentScope
                        }
                    )
                }
                # Todo: Ternary operators supported in PS7
                <#
                    $body = @{
                        roles = @(
                            @{
                                role_id = $group.Value.fsroleID
                                assignment_scope = $group.Value.scope ? $group.Value.scope : 'entire_helpdesk'
                            }
                        )
                    }
                #>


                foreach ($globalGroup in $FsGlobalADGroups.Keys){
                    $globalGroupMembers = Get-ADGroupMember -server $adDomain -identity $globalGroup -credential $credential
                        if ($globalGroupMembers.samAccountName -contains $user.samaccountName) {
                            # Add Role Assignment without Group tie-in
                            $body.roles += @{
                                role_id = $FsGlobalADGroups[$globalGroup]
                                assignment_scope = 'entire_helpdesk'
                        }
                    }
                }
            }
            (Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/agents/$($fsUser.ID)?can_see_all_tickets_from_associated_departments=True" -Method Put -Headers $headers -Body ($body | ConvertTo-JSON)).agent
            $fsGroupMembers += $fsUser.ID
        }

        $fsGroupObservers = @()
        $groupObservers = Get-AdGroupMember -server $adDomain -identity "$($group.Key)-Observers" -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        foreach ($samAccountName in $groupObservers.samAccountName) {
            $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
            $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]
            $fsGroupObservers += $fsuser.Id
        }

        $groupBody = @{
            members = $fsGroupMembers
            observers = $fsGroupObservers
        } | ConvertTo-Json
            if ($debug) {
                $uri = "https://$($FsDomain).freshservice.com/api/v2/groups/$($group.value.fsGroup)"
                Write-Output "`nHeaders:"
                Write-Output $headers
                Write-Output "`nBody:"
                Write-Output $groupBody
                Write-Output "`nUri:"
                Write-Output $uri
            }

        (Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/groups/$($group.value.fsGroup)" -Method Put -Headers $headers -Body $groupBody).Value
    }

    $groupMembers = Get-AdGroupMember -server $adDomain -identity $noGroup -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
    if ($groupMembers) {
        Write-Output("Setting users from $noGroup")
    }
    foreach ($samAccountName in $groupMembers.samAccountName) {
        $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
        $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]
            
        if (($fsUser.is_agent) -and (-not($fsUser -eq $null))) {
            Write-Output("Found Agent $($user.Samaccountname)")
            $body = @{
                roles = @(
                @{}
                )
            }

            foreach ($globalGroup in $FsGlobalADGroups.Keys){
                $globalGroupMembers = Get-ADGroupMember -server $adDomain -identity $globalGroup -credential $credential
                if ($globalGroupMembers.samAccountName -contains $user.samaccountName) {
                    Write-Output("Adding $($user.Samaccountname) to $globalGroup")
                    # Add Role Assignment without Group tie-in
                    $body.roles += @{
                        role_id = $FsGlobalADGroups[$globalGroup]
                        assignment_scope = 'entire_helpdesk'
                    }
                }
            }
            if ($debug) {
                $uri = "https://$($FsDomain).freshservice.com/api/v2/agents/$($fsUser.ID)?can_see_all_tickets_from_associated_departments=True"
                Write-Output "`nHeaders:"
                Write-Output $headers
                Write-Output "`nBody:"
                Write-Output $body | ConvertTo-JSON
                Write-Output "`nUri:"
                Write-Output $uri
            }
            (Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body ($body | ConvertTo-JSON)).agent
        }
    }
}
