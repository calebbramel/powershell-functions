# Set FreshService Users

## Description
- Gathers members from AD groups, maps them to FreshService groups.
- Updates each user's roles and permissions, then the members of the respective group.
- A user must be in an Agent group to receive an Admin role with the current structure.

**Author:** Caleb Bramel

## Requirements
- PowerShell Core
- ActiveDirectory Module

## TODO
- Untested on restricted groups.
- Reduce noise by using a state file CSV/XML and referencing it before making API calls.
- Moving to Entra Cloud groups would remove the need for credentials (using a MID) but will lose the ability to nest groups.
