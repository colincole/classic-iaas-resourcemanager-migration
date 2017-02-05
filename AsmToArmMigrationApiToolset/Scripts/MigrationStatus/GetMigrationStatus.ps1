
<#
 
Purpose: Retrieves the status of an actual ARM migration using the Migration API Move-AzureVirtualNetwork cmdlet.  This will show each cloud service as its being prepared and committed to ARM.
This is a helper Script that can make REST API calls for and pull back metadata for all production deployments in a subscription

Three parameters 
    -- subscription ID
    -- CSV from metadata extract
    -- AzureAD tenant

Sample Command:

.\MetadataExtract.ps1 -subscriptionID 98f9a3cd-a241-4ad0-9057-8d8cff55ca1f -Csv "file.csv" -AzureAdTenant org.onmicrosoft.com
 
#>

[CmdletBinding()]
Param
(
    [Parameter(Mandatory=$true)]         # subscription id
    [string]$SubscriptionID,
    [Parameter(Mandatory=$true)]         # csv containing the services to check migration status. Alternatively, Can comment this out and run a query to select services.
    [string]$Csv,
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

Write-Host "Importing csv"
$csvItems = Import-Csv $Csv -ErrorAction Stop

$csList = @{}
foreach ($item in $csvItems)
{
    if (!$csList.ContainsKey($item.csname))
    {
        $csList.Add($item.csname, $item.csname)
    }
}

#Uncomment the $services query and change code -- if checking cloud services through query instead of CSV
#Write-Host "Selecting the cloud services within the subscription" 
#$services = Get-AzureService  #| Where-Object {$_.ServiceName.StartsWith("b")}  

$ApiEndpointUri = "https://management.core.windows.net/"
# Getting authentication token
$token = GetAuthToken -ApiEndPointUri $ApiEndpointUri -AADTenant $AzureAdTenant

Write-Host "Now walking through each cloud service deployment and retrieving its metadata"

foreach ($svc in $csList.Keys)
{
    $uri = "https://management.core.windows.net/" + $subscription.SubscriptionId +"/services/hostedservices/" + $svc + "/deploymentslots/Production"
    $header = @{"x-ms-version" = "2015-10-01";'Authorization'=$token.CreateAuthorizationHeader()}

    $xml = try {Invoke-RestMethod -Uri $uri -Method Get -Headers $header} catch {$_.exception.response}

    if($xml.StatusCode -ne 'NotFound') 
    {
        if($xml.Deployment.RoleList.Role.MigrationState)
        {
            if ($xml.Deployment.RoleList.Role.MigrationState -eq "Prepared")
            {
                Write-Host -ForegroundColor Green "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            elseif ($xml.Deployment.RoleList.Role.MigrationState -eq "Preparing")
            {
                Write-Host -ForegroundColor Magenta "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            elseif ($xml.Deployment.RoleList.Role.MigrationState -eq "Committing")
            {
                Write-Host -ForegroundColor Magenta "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            elseif ($xml.Deployment.RoleList.Role.MigrationState -eq "Committed")
            {
                Write-Host -ForegroundColor Green "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            elseif ($xml.Deployment.RoleList.Role.MigrationState -eq "Aborting")
            {
                Write-Host -ForegroundColor Magenta "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            elseif ($xml.Deployment.RoleList.Role.MigrationState -eq "Aborted")
            {
                Write-Host -ForegroundColor Green "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            elseif ($xml.Deployment.RoleList.Role.MigrationState -eq $null)
            {
                Write-Host -ForegroundColor Yellow "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
            else
            {
                Write-Host -ForegroundColor Red "Migration State for" $svc ":" $xml.Deployment.RoleList.Role.MigrationState
            }
        }
        else
        {
            Write-Host -ForegroundColor Yellow "Migration State for" $svc ": NotPrepared"
        }
    }
    else
    {
        write-host -ForegroundColor Cyan ("Status Code for GET Cloud Service: " + $svc + " Status: cloud service not found or completed migration.")
    }
}

Write-Host "Completed" -ForegroundColor Green



