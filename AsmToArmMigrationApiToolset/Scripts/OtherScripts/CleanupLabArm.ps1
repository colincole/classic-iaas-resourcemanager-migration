<#
  Delete resource groups and cleanup lab.  BE CAREFUL running this -- don't accidently delete something you didn't want deleted.

  version: 1.02
  1/24/2017

  Colin Cole
  Cloud Solution Architect
  colinco@microsoft.com   
#>

Param
(
    [Parameter(Mandatory=$true)]         # subscription id
    [string]$SubscriptionID,                
    [Parameter(Mandatory=$true)]         # AAD tenant name -- needed to establish a bearer token. i.e. xxxx.onmicrosoft.com. For Microsoft subscriptions, use: microsoft.onmicrosoft.com 
    [string]$AzureAdTenant,
    [Parameter(Mandatory=$true)]         # CSV contining the vm's to be removed. This comes from AsmMetadataParser.exe.
    [string]$Csv                         
)

$global:ScriptStartTime = (Get-Date -Format hh-mm-ss.ff)

if((Test-Path "Output") -eq $false)
{
	md "Output" | Out-Null
}

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

function Write-Log
{
	param(
        [string]$logMessage,
	    [string]$color="White"
    )

    $timestamp = ('[' + (Get-Date -Format hh:mm:ss.ff) + '] ')
	$message = $timestamp + $logMessage
    Write-Host $message -ForeGroundColor $color
	$fileName = "Output\Log-" + $global:ScriptStartTime + ".log"
	Add-Content $fileName $message
}

try
{
    $ApiEndpointUri = "https://management.core.windows.net/"
    Select-AzureRmSubscription -SubscriptionId $subscriptionID

    # Getting authentication token
    $token = GetAuthToken -ApiEndPointUri $ApiEndpointUri -AADTenant $AzureAdTenant
    $header = @{"x-ms-version" = "2015-10-01";"Authorization"=$token.CreateAuthorizationHeader()}

    Write-Host "Importing csv"
    $csvItems = Import-Csv $Csv -ErrorAction Stop
    $availsets = @{}

    foreach ($item in $csvItems)
    {
        $cloudservicename = $item.csname
        if ($cloudservices.ContainsKey($cloudservicename)) { continue }

        $cloudservices.Add($cloudservicename, $cloudservicename)

        $ResourceGroupName = $item.csname + '-Migrated'  # the name of the RG after the migration api has migrated it
        $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$($ResourceGroupName)?api-version=2014-04-01" 
        Write-Log "Delete RG: $uri" 

        $response = try {Invoke-RestMethod -Uri $uri -Method Delete -Headers $header} catch {$_.exception.response}

        if (($response -eq $null) -or ($response -eq ""))
        {
            Write-Log -color Green "Successfully deleted the RG: $($ResourceGroupName)"
        }
        elseif (($response.StatusCode.value__ -eq 202) -or ($response.StatusCode.value__ -eq 200) -or ($response.StatusCode.value__ -eq $null) -or ($response.StatusCode.value__ -eq ""))
        {
            Write-Log -color Green "Successfully deleted the RG: $($ResourceGroupName). Status Code: $($response.StatusCode.value__)"
        }
        else
        {
            Write-Log -color Red "Delete RG Error. Status Code: $($response.StatusCode) for RG: $($ResourceGroupName)"
            Write-Log -color Red "Status Code Value: $($response.StatusCode.value__) for RG: $($ResourceGroupName)"
        }
    }
}
catch
{
    Write-Log "Error deleting resource group $ResourceGroupName. Following exception was caught $($_.Exception.Message)" -color "Red"
}