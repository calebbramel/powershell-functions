# Need to convert UPNs to url-encoded strings for ID lookup
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

    # HTTP Headers for all subsequent API calls
    $headers = @{
        "Content-Type" = "application/json";
        Authorization = "Basic $token" 
    }
    
    foreach ($group in $FsRequesterADGroups.GetEnumerator()) {
        $groupMembers = Get-AdGroupMember -server $adDomain -identity $group.Key -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        if ($groupMembers) {
                Write-Output("Setting users from $($group.Key)")
        }
        foreach ($samAccountName in $groupMembers.samAccountName) {
            # Get AD User
            $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
            # Parse FreshService ID
            $uri = "https://$($fsDomain).freshservice.com/api/v2/requesters?$(Convert-UPNToURLEncoded $user.UserPrincipalName)"
            $fsUserID = ((Invoke-RestMethod -Headers $headers -Method GET -Uri $uri).requesters[0]).id
            # Pause to avoid Rate Limit
            Start-Sleep -Milliseconds 333
            # Update Group Membership
            $groupId = $FsRequesterADGroups[$group.Key]
            Invoke-RestMethod -Headers $headers -Method POST "https://$($fsDomain).freshservice.com/api/v2/requester_groups/$($groupId)/members/$fsUserID"
        }
        Write-Output("`nCurrent members:")
        (Invoke-RestMethod -Headers $headers -Method GET "https://$($fsDomain).freshservice.com/api/v2/requester_groups/$($groupId)/members").requesters
    }

    foreach ($group in $FsAgentADGroups.GetEnumerator()) {
        # Create Empty Array for Group Membership
        $fsGroupMembers = @()

        $groupMembers = Get-AdGroupMember -server $adDomain -identity "$($group.Key)-Members" -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        if ($groupMembers) {
            Write-Output("Setting users from $($group.Key)")
        }

        foreach ($samAccountName in $groupMembers.samAccountName) {
            # Get AD User
            $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName

            # Parse FreshService Info
            $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]
            
            # Requester to Agent Conversion
            if (-not($fsUser.is_agent) -and (-not($fsUser -eq $null))) {
                # Skip conversion if flagged false
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

                # If scope not defined, make scope workspace
                if ($group.value.scope) {
                    $assignmentScope = $group.value.scope
                } else {
                    $assignmentScope = 'entire_helpdesk'
                }
                # If role not defined, make role Inspira IT Agent
                if ($group.Value.fsroleID) {
                    $fsroleID = $group.value.fsroleID
                } else {
                    $fsroleID = 23000234020
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

                # Non-Group roles must be added via a user call
                foreach ($globalGroup in $FsGlobalADGroups.Keys){
                    $globalGroupMembers = Get-ADGroupMember -server $adDomain -identity $globalGroup -credential $credential
                        # Query User Group Membership
                        if ($globalGroupMembers.samAccountName -contains $user.samaccountName) {
                            # Add Role Assignment without Group tie-in
                            $body.roles += @{
                                role_id = $FsGlobalADGroups[$globalGroup]
                                assignment_scope = 'entire_helpdesk'
                        }
                    }
                }
            }
            # Update User Roles
            (Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/agents/$($fsUser.ID)?can_see_all_tickets_from_associated_departments=True" -Method Put -Headers $headers -Body ($body | ConvertTo-JSON)).agent

            # Add User to Member Array for Assignment
            $fsGroupMembers += $fsUser.ID
        }

        # Create Empty Array for Group Observers
        $fsGroupObservers = @()

        $groupObservers = Get-AdGroupMember -server $adDomain -identity "$($group.Key)-Observers" -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
        if ($groupObservers) {
            foreach ($samAccountName in $groupObservers.samAccountName) {
                # AD Lookup
                $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
                # Parse FreshService Info
                $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]

                if ($debug) {
                    Write-Output("Adding $samAccountName to $($group.key) as observer")
                }
                # Add User to Observer Array for Assignment
                $fsGroupObservers += $fsuser.Id
            }
        }

        $groupBody = @{
            members = $fsGroupMembers
            observers = $fsGroupObservers
        } | ConvertTo-Json
            if ($debug) {
                Write-Output "`nObservers"
                Write-Output $fsGroupObservers                
                $uri = "https://$($FsDomain).freshservice.com/api/v2/groups/$($group.value.fsGroup)"
                Write-Output "`nHeaders:"
                Write-Output $headers
                Write-Output "`nBody:"
                Write-Output $groupBody
                Write-Output "`nUri:"
                Write-Output $uri
            }
        # Update the Group
        (Invoke-RestMethod -Uri "https://$($FsDomain).freshservice.com/api/v2/groups/$($group.value.fsGroup)" -Method Put -Headers $headers -Body $groupBody).Value
    }
    
    # Ungrouped FreshService Users 
    $groupMembers = Get-AdGroupMember -server $adDomain -identity $noGroup -Recursive -credential $credential | Where-Object { $_.objectClass -eq 'user' }
    if ($groupMembers) {
        Write-Output("Setting users from $noGroup")
    }
    
    foreach ($samAccountName in $groupMembers.samAccountName) {
        # Get AD User
        $user = Get-ADUser -server $adDomain -Identity $samAccountName -credential $credential -Properties extensionAttribute3, UserPrincipalName
        # Parse FreshService Info
        $fsUser = (Invoke-RestMethod -Headers $headers -Method GET -Uri "https://$($FsDomain).freshservice.com/api/v2/requesters?include_agents=true&$(Convert-UPNToURLEncoded $user.UserPrincipalName)").requesters[0]
            
        # Prepare to add roles to user if the user is an Agent
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
            # Update Agent
            (Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body ($body | ConvertTo-JSON)).agent
        }
    }
}
