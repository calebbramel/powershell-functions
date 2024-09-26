# Overview
Get-RandomPassword is a PowerShell function designed to generate a readable random password consisting of a specified number of words from the NATO alphabet, followed by a random digit. This function is useful for creating memorable yet secure passwords.

# Usage
## Parameters
* **$PasswordLength**: Number of words to include in the password. Default is 3.

# Example
## PowerShell
```PowerShell
$randomPassword = Get-RandomPassword
Write-Output $randomPassword
```
```PowerShell
$randomPassword = Get-RandomPassword -PasswordLength 5
Write-Output $randomPassword
```
