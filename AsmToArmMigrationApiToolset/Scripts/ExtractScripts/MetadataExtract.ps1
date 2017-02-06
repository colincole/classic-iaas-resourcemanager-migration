<#
 
Purpose: Extract the deployment metadata from a production Azure subscription running ASM virtual networks. Output is a single XML file.
This is a helper Script that can make REST API calls for and pull back metadata for all production deployments in a subscription.
The output can then be run through AsmMetadataParser.exe to build a CSV from a vNet's deployments. The CSV can be used to 
test, validate, and monitor an actial migration with Move-AzureVirtualNetwork.

Sample Command:

.\MetadataExtract.ps1 -subscriptionID 98f9a3cd-a241-4ad0-9057-8d8cff55ca1f -AzureAdTenant org.onmicrosoft.com
 
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    $subscriptionID,
    [Parameter(Mandatory=$true)]         # AAD tenant name -- needed to establish a bearer token. i.e. xxxx.onmicrosoft.com. For Microsoft subscriptions, use: microsoft.onmicrosoft.com 
    [string]$AzureAdTenant 
)

function GetAuthToken
{
    # Obtained from: https://blogs.technet.microsoft.com/stefan_stranger/2016/10/21/using-the-azure-arm-rest-apin-get-access-token/
    param
    (
            [Parameter(Mandatory=$true)]
            $ApiEndpointUri,
         
            [Parameter(Mandatory=$true)]
            $AADTenant
    )
  
    $adal = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Services\" + `
                "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    $adalforms = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Services\" + `
                    "Microsoft.IdentityModel.Clients.ActiveDirectory.WindowsForms.dll"
    
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $authorityUri = “https://login.windows.net/$aadTenant”
    
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authorityUri
    
    $authResult = $authContext.AcquireToken($ApiEndpointUri, $clientId,$redirectUri, "Auto")
  
    return $authResult
} 

Select-AzureSubscription -SubscriptionId $subscriptionID
$subscription = Get-AzureSubscription -SubscriptionId $subscriptionID

$ApiEndpointUri = "https://management.core.windows.net/"
# Getting authentication token
$token = GetAuthToken -ApiEndPointUri $ApiEndpointUri -AADTenant $AzureAdTenant

Write-Host "Selecting the cloud services within the subscription" 
$services = Get-AzureService
$deployments = "<deployments>"

Write-Host "Now walking through each cloud service deployment and retrieving its metadata"

foreach ($svc in $services)
{
    Write-Host ("Pulling metadata for " + $svc.ServiceName) -ForegroundColor Cyan
    $uri = "https://management.core.windows.net/" + $subscription.SubscriptionId +"/services/hostedservices/" + $svc.ServiceName + "/deploymentslots/Production"
    $header = @{"x-ms-version" = "2015-10-01";'Authorization'=$token.CreateAuthorizationHeader()}

    $xml = try {Invoke-RestMethod -Uri $uri -Method Get -Headers $header} catch {$_.exception.response}

    if($xml.StatusCode -eq 'NotFound') 
    {
        write-host -ForegroundColor Magenta ("Cloud Service: " + $svc.ServiceName + " : No deployments")
    }
    else
    {
        $deployments = $deployments + $xml.InnerXml
    }
}

$deployments = $deployments + "</deployments>"
$deployments | Out-File (".\metadata_" + $subscription.SubscriptionId + ".xml")
Write-Host ("Completed. Metadata saved to file metadata_" + $subscription.SubscriptionId + ".xml") -ForegroundColor Green
Write-Host ("Now run this through AsmMetadataParser to build a CSV from the a vNet's deployments.")
