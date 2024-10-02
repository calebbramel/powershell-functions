# Set FreshService Users

## Description
- Gathers members from AD groups, maps them to FreshService groups.
- Updates each user's roles and permissions, then the members of the respective group.
- A user must be in an Agent group to receive an Admin role with the current structure.

**Author:** Caleb Bramel

## Requirements
- PowerShell Core
- ActiveDirectory Module

## Usage

```PowerShell
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

$FsRequesterADGroups = @{
    # Admin groups are global by default and cannot be scoped to groups.
    "ACC-APP-FreshService-Requesters1" = 44444444444 # Change Manager
}

$splat = {
    token = Get-AutomationVariable -Name "FreshServiceAPIKey"
    credential = Get-AutomationPSCredential -Name 'ServiceAccount'
    adDomain = "ad.contoso.com"
    fsDomain = "contoso"
}

Set-FsUsers @splat
```
## TODO
- Untested on restricted groups.
- Reduce noise by using a state file CSV/XML and referencing it before making API calls.
- Moving to Entra Cloud groups would remove the need for credentials (using a MID) but will lose the ability to nest groups.
