<#
    Microsoft.TeamFoundation.DistributedTask.Task.Deployment.Azure.psm1
#>

function Get-AzureCmdletsVersion
{
    $module = Get-Module AzureRM
    if($module)
    {
        return ($module).Version
    }
    return (Get-Module Azure).Version
}

function Get-AzureVersionComparison
{
    param
    (
        [System.Version] [Parameter(Mandatory = $true)]
        $AzureVersion,

        [System.Version] [Parameter(Mandatory = $true)]
        $CompareVersion
    )

    $result = $AzureVersion.CompareTo($CompareVersion)

    if ($result -lt 0)
    {
        #AzureVersion is before CompareVersion
        return $false 
    }
    else
    {
        return $true
    }
}

function Set-CurrentAzureSubscription
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $azureSubscriptionId,
        
        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $storageAccount
    )

    if (Get-SelectNotRequiringDefault)
    {                
        Write-Host "Select-AzureSubscription -SubscriptionId $azureSubscriptionId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureSubscription -SubscriptionId $azureSubscriptionId        
    }
    else
    {
        Write-Host "Select-AzureSubscription -SubscriptionId $azureSubscriptionId -Default"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureSubscription -SubscriptionId $azureSubscriptionId -Default
    }
    
    if ($storageAccount)
    {
        Write-Host "Set-AzureSubscription -SubscriptionId $azureSubscriptionId -CurrentStorageAccountName $storageAccount"
        Set-AzureSubscription -SubscriptionId $azureSubscriptionId -CurrentStorageAccountName $storageAccount
    }
}

function Set-CurrentAzureRMSubscription
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $azureSubscriptionId,
        
        [String]
        $tenantId
    )

    if([String]::IsNullOrWhiteSpace($tenantId))
    {
        Write-Host "Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId
    }
    else
    {
        Write-Host "Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId -tenantId $tenantId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId -tenantId $tenantId
    }
}

function Get-SelectNotRequiringDefault
{
    $azureVersion = Get-AzureCmdletsVersion

    #0.8.15 make the Default parameter for Select-AzureSubscription optional
    $versionRequiring = New-Object -TypeName System.Version -ArgumentList "0.8.15"

    $result = Get-AzureVersionComparison -AzureVersion $azureVersion -CompareVersion $versionRequiring

    return $result
}

function Get-RequiresEnvironmentParameter
{
    $azureVersion = Get-AzureCmdletsVersion

    #0.8.8 requires the Environment parameter for Set-AzureSubscription
    $versionRequiring = New-Object -TypeName System.Version -ArgumentList "0.8.8"

    $result = Get-AzureVersionComparison -AzureVersion $azureVersion -CompareVersion $versionRequiring

    return $result
}

function Set-UserAgent
{
    if ($env:AZURE_HTTP_USER_AGENT)
    {
        try
        {
            [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent($UserAgent)
        }
        catch
        {
        Write-Verbose "Set-UserAgent failed with exception message: $_.Exception.Message"
        }
    }
}

function Initialize-AzureSubscription 
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $ConnectedServiceName,

        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $StorageAccount
    )

    Import-Module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"

    Write-Host ""
    Write-Host "Get-ServiceEndpoint -Name $ConnectedServiceName -Context $distributedTaskContext"
    $serviceEndpoint = Get-ServiceEndpoint -Name "$ConnectedServiceName" -Context $distributedTaskContext
    if ($serviceEndpoint -eq $null)
    {
        throw "A Connected Service with name '$ConnectedServiceName' could not be found.  Ensure that this Connected Service was successfully provisioned using services tab in Admin UI."
    }

    $x509Cert = $null
    if ($serviceEndpoint.Authorization.Scheme -eq 'Certificate')
    {
        $subscription = $serviceEndpoint.Data.SubscriptionName
        Write-Host "subscription= $subscription"

        Write-Host "Get-X509Certificate -CredentialsXml <xml>"
        $x509Cert = Get-X509Certificate -ManagementCertificate $serviceEndpoint.Authorization.Parameters.Certificate
        if (!$x509Cert)
        {
            throw "There was an error with the Azure management certificate used for deployment."
        }

        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName
        $azureServiceEndpoint = $serviceEndpoint.Url

		$EnvironmentName = "AzureCloud"
		if( $serviceEndpoint.Data.Environment )
        {
            $EnvironmentName = $serviceEndpoint.Data.Environment
        }

        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"
        Write-Host "azureServiceEndpoint= $azureServiceEndpoint"
    }
    elseif ($serviceEndpoint.Authorization.Scheme -eq 'UserNamePassword')
    {
        $username = $serviceEndpoint.Authorization.Parameters.UserName
        $password = $serviceEndpoint.Authorization.Parameters.Password
        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName

        Write-Host "Username= $username"
        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $psCredential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
        
        if(Get-Module Azure)
        {
             Write-Host "Add-AzureAccount -Credential `$psCredential"
             $azureAccount = Add-AzureAccount -Credential $psCredential
        }

        if(Get-module -Name Azurerm.profile -ListAvailable)
        {
             Write-Host "Add-AzureRMAccount -Credential `$psCredential"
             $azureRMAccount = Add-AzureRMAccount -Credential $psCredential
        }

        if (!$azureAccount -and !$azureRMAccount)
        {
            throw "There was an error with the Azure credentials used for deployment."
        }

        if($azureAccount)
        {
            Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
        }

        if($azureRMAccount)
        {
            Set-CurrentAzureRMSubscription -azureSubscriptionId $azureSubscriptionId
        }
    }
    elseif ($serviceEndpoint.Authorization.Scheme -eq 'ServicePrincipal')
    {
        $servicePrincipalId = $serviceEndpoint.Authorization.Parameters.ServicePrincipalId
        $servicePrincipalKey = $serviceEndpoint.Authorization.Parameters.ServicePrincipalKey
        $tenantId = $serviceEndpoint.Authorization.Parameters.TenantId
        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName

        Write-Host "tenantId= $tenantId"
        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"

        $securePassword = ConvertTo-SecureString $servicePrincipalKey -AsPlainText -Force
        $psCredential = New-Object System.Management.Automation.PSCredential ($servicePrincipalId, $securePassword)

        $currentVersion =  Get-AzureCmdletsVersion
        $minimumAzureVersion = New-Object System.Version(0, 9, 9)
        $isPostARMCmdlet = Get-AzureVersionComparison -AzureVersion $currentVersion -CompareVersion $minimumAzureVersion

        if($isPostARMCmdlet)
        {
             if(!(Get-module -Name Azurerm.profile -ListAvailable))
             {
                  throw "AzureRM Powershell module is not found. SPN based authentication is failed."
             }

             Write-Host "Add-AzureRMAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential"
             $azureRMAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential 
        }
        else
        {
             Write-Host "Add-AzureAccount -ServicePrincipal -Tenant `$tenantId -Credential `$psCredential"
             $azureAccount = Add-AzureAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential
        }

        if (!$azureAccount -and !$azureRMAccount)
        {
            throw "There was an error with the service principal used for deployment."
        }

        if($azureAccount)
        {
            Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
        }

        if($azureRMAccount)
        {
            Set-CurrentAzureRMSubscription -azureSubscriptionId $azureSubscriptionId -tenantId $tenantId
        }
    }
    else
    {
        throw "Unsupported authorization scheme for azure endpoint = " + $serviceEndpoint.Authorization.Scheme
    }

    if ($x509Cert)
    {
        if(!(Get-Module Azure))
        {
             throw "Azure Powershell module is not found. Certificate based authentication is failed."
        }

        if (Get-RequiresEnvironmentParameter)
        {
            if ($StorageAccount)
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -CurrentStorageAccountName $StorageAccount -Environment $EnvironmentName"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -CurrentStorageAccountName $StorageAccount -Environment $EnvironmentName
            }
            else
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -Environment $EnvironmentName"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -Environment $EnvironmentName
            }
        }
        else
        {
            if ($StorageAccount)
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -ServiceEndpoint $azureServiceEndpoint -CurrentStorageAccountName $StorageAccount"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -ServiceEndpoint $azureServiceEndpoint -CurrentStorageAccountName $StorageAccount
            }
            else
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -ServiceEndpoint $azureServiceEndpoint"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -ServiceEndpoint $azureServiceEndpoint
            }
        }

        Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
    }
}

function Get-AzureModuleLocation
{
    #Locations are from Web Platform Installer
    $azureModuleFolder = ""
    $azureX86Location = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"
    $azureLocation = "${env:ProgramFiles}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"

    if (Test-Path($azureX86Location))
    {
        $azureModuleFolder = $azureX86Location
    }
     
    elseif (Test-Path($azureLocation))
    {
        $azureModuleFolder = $azureLocation
    }

    $azureModuleFolder
}

function Import-AzurePowerShellModule
{
    # Try this to ensure the module is actually loaded...
    $moduleLoaded = $false
    $azureFolder = Get-AzureModuleLocation

    if(![string]::IsNullOrEmpty($azureFolder))
    {
        Write-Host "Looking for Azure PowerShell module at $azureFolder"
        Import-Module -Name $azureFolder -Global:$true
        $moduleLoaded = $true
    }
    else
    {
        if(Get-Module -Name "Azure" -ListAvailable)
        {
            Write-Host "Importing Azure Powershell module."
            Import-Module "Azure"
            $moduleLoaded = $true
        }

        if(Get-Module -Name "AzureRM" -ListAvailable)
        {
            Write-Host "Importing AzureRM Powershell module."
            Import-Module "AzureRM"
            $moduleLoaded = $true
        }
    }

    if(!$moduleLoaded)
    {
         throw "Windows Azure Powershell (Azure.psd1) and Windows AzureRM Powershell (AzureRM.psd1) modules are not found. Retry after restart of VSO Agent service, if modules are recently installed."
    }
}

function Initialize-AzurePowerShellSupport
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $ConnectedServiceName,

        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $StorageAccount
    )

    #Ensure we can call the Azure module/cmdlets
    Import-AzurePowerShellModule

    $minimumAzureVersion = "0.8.10.1"
    $minimumRequiredAzurePSCmdletVersion = New-Object -TypeName System.Version -ArgumentList $minimumAzureVersion
    $installedAzureVersion = Get-AzureCmdletsVersion
    Write-Host "AzurePSCmdletsVersion= $installedAzureVersion"

    $result = Get-AzureVersionComparison -AzureVersion $installedAzureVersion -CompareVersion $minimumRequiredAzurePSCmdletVersion
    if (!$result)
    {
        throw "The required minimum version ($minimumAzureVersion) of the Azure Powershell Cmdlets are not installed."
    }

    # Set UserAgent for Azure
    Set-UserAgent

    # Intialize the Azure subscription based on the passed in values
    Initialize-AzureSubscription -ConnectedServiceName $ConnectedServiceName -StorageAccount $StorageAccount
}
# SIG # Begin signature block
# MIInoQYJKoZIhvcNAQcCoIInkjCCJ44CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCAjLHErWkQVhiJ
# h63kfMHLxaqf1YYraTQRHNVPTTxRuqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZdjCCGXICAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgAdp1GtVJ
# YU6rgcrIIARGNB/NYA5cbqqQNL4WNDcVFa0wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQC5Xx7Y1f6wkLRGYnfAxaMX4/z60yQbTRqaZpBGOMCb
# 0RNbgQclSlQ0O091skUNG3L18zsrF5ZGAnGJ6WxrCBLZY7DrOErNuAnjaQ3IaZCr
# 7t/n1SW2Plx2nNJ6VPSwk/xA2myNegccD8IdE1pjQSDFRYKgb+M4m5z8tGrRjmke
# BNkvAR1S8BcNXQSh19bPJuqVLEfONukHdqFf3UJ2+QkS9OHWlknL++iA8iqkksg9
# +51KKDghCRpeEJv5P7UE88jVNRTxXp18IFzJXH0qAOAkAH212VgRxvXkuCmUtKBc
# O+6ONe6t6RwSTSWOnQkTSwC5YeqQ/nJNI1JXT/gzjghCoYIXADCCFvwGCisGAQQB
# gjcDAwExghbsMIIW6AYJKoZIhvcNAQcCoIIW2TCCFtUCAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEINsQx0dmXIofz73ELRYMR4DXF7Uxzt0Xm1Ggh0Rf
# bazwAgZh7vK+UBYYEzIwMjIwMTI1MTMyNjMxLjE0MVowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkREOEMtRTMzNy0yRkFFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIRVzCCBwwwggT0oAMCAQICEzMAAAGcD6ZNYdKeSygAAQAAAZww
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjExMjAyMTkwNTE5WhcNMjMwMjI4MTkwNTE5WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046REQ4Qy1FMzM3LTJG
# QUUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDbUioMGV1JFj+s612s02mKu23KPUNs
# 71OjDeJGtxkTF9rSWTiuA8XgYkAAi/5+2Ff7Ck7JcKQ9H/XD1OKwg1/bH3E1qO1z
# 8XRy0PlpGhmyilgE7KsOvW8PIZCf243KdldgOrxrL8HKiQodOwStyT5lLWYpMsuT
# 2fH8k8oihje4TlpWiFPaCKLnFDaAB0Ccy6vIdtHjYB1Ie3iOZPisquL+vNdCx7gO
# hB8iiTmTdsU8OSUpC8tBTeTIYPzmhaxQZd4moNk6qeCJyi7fiW4fyXdHrZ3otmgx
# xa5pXz5pUUr+cEjV+cwIYBMkaY5kHM9c6dEGkgHn0ZDJvdt/54FOdSG61WwHh4+e
# vUhwvXaB4LCMZIdCt5acOfNvtDjV3CHyFOp5AU/qgAwGftHU9brv4EUwcuteEAKH
# 46NufE20l/WjlNUh7gAvt2zKMjO4zXRxCUTh/prBQwXJiUZeFSrEXiOfkuvSlBni
# yAYYZp5kOnaxfCKdGYjvr4QLA93vQJ6p2Ox3IHvOdCPaCr8LsKVcFpyp8MEhhJTM
# +1LwqHJqFDF5O1Z9mjbYvm3R9vPhkG+RDLKoTpr7mTgkaTljd9xvm94Obp8BD9Hk
# 4mPi51mtgLiuN8/6aZVESVZXtvSuNkD5DnIJQerIy5jaRKW/W2rCe9ngNDJadS7R
# 96GGRl7IIE37lwIDAQABo4IBNjCCATIwHQYDVR0OBBYEFLtpCWdTXY5dtddkspy+
# oxjCA/qyMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggIBAKcAKqYjGEczTWMs9z0m7Yo23sgqVF3LyK6gOMz7TCHAJN+F
# vbvZkQ53VkvrZUd1sE6a9ToGldcJnOmBc6iuhBlpvdN1BLBRO8QSTD1433VTj4XC
# Qd737wND1+eqKG3BdjrzbDksEwfG4v57PgrN/T7s7PkEjUGXfIgFQQkr8TQi+/HZ
# Z9kRlNccgeACqlfb4uGPxn5sdhQPoxdMvmC3qG9DONJ5UsS9KtO+bey+ohUTDa9L
# vEToc4Qzy5fuHj2H1JsmCaKG78nXpfWpwBLBxZYSpfml29onN8jcG7KD8nGSS/76
# PDlb2GMQsvv+Ra0JgL6FtGRGgYmHCpM6zVrf4V/a+SoHcC+tcdGYk2aKU5KOlv+f
# FE3n024V+z54tDAKR9z78rejdCBWqfvy5cBUQ9c5+3unHD08BEp7qP2rgpoD856v
# NDgEwO77n7EWT76nl/IyrbK2kjbHLzUMphFpXKnV1fYWJI2+E/0LHvXFGGqF4OvM
# BRxbrJVn03T2Dy5db6s5TzJzSaQvCrXYqA4HKvstQWkqkpvBHTX8M09+/vyRbVXN
# xrPdeXw6oD2Q4DksykCFfn8N2j2LdixE9wG5iilv69dzsvHIN/g9A9+thkAQCVb9
# DUSOTaMIGgsOqDYFjhT6ze9lkhHHGv/EEIkxj9l6S4hqUQyWerFkaUWDXcnZMIIH
# cTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCB
# iDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEw
# OTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIh
# C3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNx
# WuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFc
# UTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAc
# nVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUo
# veO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyzi
# YrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9
# fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdH
# GO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7X
# KHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiE
# R9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/
# eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3
# FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAd
# BgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEE
# AYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4IC
# AQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pk
# bHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gng
# ugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3
# lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHC
# gRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6
# MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEU
# BHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvsh
# VGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+
# fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrp
# NPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHI
# qzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCAs4wggI3AgEBMIH4
# oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUw
# IwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjpERDhDLUUzMzctMkZBRTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAzdlp6t3ws/bnErbm
# 9c0M+9dvU0CggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAN
# BgkqhkiG9w0BAQUFAAIFAOWaGfwwIhgPMjAyMjAxMjUxNDQxMDBaGA8yMDIyMDEy
# NjE0NDEwMFowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA5ZoZ/AIBADAKAgEAAgIZ
# 1wIB/zAHAgEAAgIRTjAKAgUA5ZtrfAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUA
# A4GBAGGCKSA8SyThmVHmhbzcoeymWZHvXgbR5k4Z5yLQ91pPrCDpTQPNGbe3uebg
# /t4Y2S4LYT/V2m99S8mzyz4QbK+sTtUMS11fPnNA94OwdE8Quv+dAs0iOexF0BPp
# YNatvNLHAvSM7USSDxMD+N9MmNkIiyUg05u2HNMGg7XX7YRQMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGcD6ZNYdKeSygA
# AQAAAZwwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQguGo4oUt0K9sDAnIvJRym5O/TLgKx36axXdfe
# 2JSayA0wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCA3D0WFII0syjoRd/Xe
# EIG0WUIKzzuy6P6hORrb0nqmvDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAABnA+mTWHSnksoAAEAAAGcMCIEIAZbQNVgiICxfnDUBgTh
# GUSjhWUsjrP0m/Z+192ni+cfMA0GCSqGSIb3DQEBCwUABIICAH9vRIcz3hwcfOSl
# RyjJNDTZki/KCrk9+WQOGJcIotEgasMMDfrp5UnY7i5L4gKWRphJqeOshSGCiUMR
# CapYBUtmURpfGLdO4WZ3i5aXW5MLBj0+Na2AOJgdhYqDUmyoFOqFs9sdKRynVErI
# hyDYuzCgRPhrSl1XDDmYpfHB7PJSy5amo04jyW7kW5xMyDNyhivqSfIWkz9iKNmp
# 0zSB+R6UY9Sji3X7ZUvDWcijRWdxyOWslRpE6PTCyRMxECzcXw6RoXLG1185OOL/
# 1GCXo17X/ETgZxJEsykLDb+kSI4lIgYbtd8okvDgEwuwJ2GdfWzZ0dSHj/VBqEhu
# r2iUIA6WjoJ7U5zYs9Itdpgy+zbVqw2MMTzxhercxugkEnVj50BEt3/3kiNfV+c3
# 1Hgjy/HP9BdTbzQwsIuxaweHyCCttEpP8ZbBfSogX+sHCBA6py4aA0mtt68zvrJY
# AA0C4nvLODGy4GkhWqaixjYyu9bpReBB96D3OBKoM58BaFKMYjPgB6c6YcgS7NY9
# JAaMZ+NOrzRXPDtd1gYk8c/UkqL/mgDsz7yipGoAUk8ovOLdLe00/Hj3LKzU6Yxg
# iib6zv534zle88MBPoLK4tCxMtquOgFY721Zw4JIy62N4COCkDICXPVwVTchv/S8
# 23rC1oLfQUo41O5t2aEMKsxaiJ7s
# SIG # End signature block
