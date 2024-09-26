This PowerShell function rotates the basic authentication credentials for a specified API in Azure API Management.

# Parameters
* ApiID: The ID of the API for which the credentials are being rotated.
* ApiManagementService: The name of the API Management service instance.
* ResourceGroupName: The name of the resource group containing the API Management service.
* SubscriptionID: The subscription ID associated with the API Management service.
* User: The username for which the credentials are being rotated.

# Requirements
* `Az.ApiManagement` PowerShell Module
* Contributor Access over API Manager
* `Get-RandomPassword` Function

# Usage
To use the Rotate-BasicAuthCredentials function, define the parameters in a hash table and call the function with the hash table using splatting.

## Example

### XML
```xml
<policies>
    <inbound>
        <base />
        <choose>
            <when condition="@(context.Request.Headers.GetValueOrDefault("Authorization") == "Basic " + Convert.ToBase64String(System.Text.Encoding.ASCII.GetBytes("user1:Cred1")) || context.Request.Headers.GetValueOrDefault("Authorization") == "Basic " + Convert.ToBase64String(System.Text.Encoding.ASCII.GetBytes("user1:Cred2")))">
                <set-header name="Authorization" exists-action="override">
                    <value>@(context.Request.Headers.GetValueOrDefault("Authorization"))</value>
                </set-header>
            </when>
            <otherwise>
                <return-response>
                    <set-status code="401" reason="Unauthorized" />
                    <set-header name="WWW-Authenticate" exists-action="override">
                        <value>Basic realm="example"</value>
                    </set-header>
                </return-response>
            </otherwise>
        </choose>
    </inbound>
    <!-- Control if and how the requests are forwarded to services  -->
    <backend>
        <base />
    </backend>
    <!-- Customize the responses -->
    <outbound>
        <base />
    </outbound>
    <!-- Handle exceptions and customize error responses  -->
    <on-error>
        <base />
    </on-error>
</policies>
```
### PowerShell
```powershell
$params = @{
    ApiID = "api1"
    ApiManagementService = "APIM-PRD-CUS-1"
    ResourceGroupName = "RG-PRD-CUS-1"
    SubscriptionID = "12345678-abcd-efga"
    User = "user1"
}

Rotate-BasicAuthCredentials @params
```
