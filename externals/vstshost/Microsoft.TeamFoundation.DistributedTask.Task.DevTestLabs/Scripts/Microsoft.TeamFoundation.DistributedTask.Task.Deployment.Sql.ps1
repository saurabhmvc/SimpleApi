param (        
     [string]$sqlPackageArguments     
    )

$ErrorActionPreference = 'Stop'
Write-Verbose "Entering script Microsoft.TeamFoundation.DistributedTask.Task.Deployment.Sql.ps1" -Verbose

function Get-SqlPackageOnTargetMachine
{
    try
    {
        $sqlDacPath, $sqlVersion = Locate-HighestVersionSqlPackageWithSql
        $sqlVersionNumber = [decimal] $sqlVersion
    }
    catch [System.Exception]
    {
        Write-Verbose ("Failed to get Dac Framework (installed with SQL Server) location with exception: " + $_.Exception.Message) -verbose
        $sqlVersionNumber = 0
    }

	try
    {
        $sqlMsiDacPath, $sqlMsiVersion = Locate-HighestVersionSqlPackageWithDacMsi
        $sqlMsiVersionNumber = [decimal] $sqlMsiVersion
    }
    catch [System.Exception]
    {
        Write-Verbose ("Failed to get Dac Framework (installed with DAC Framework) location with exception: " + $_.Exception.Message) -verbose
        $sqlMsiVersionNumber = 0
    }

    try
    {
        $vsDacPath, $vsVersion = Locate-HighestVersionSqlPackageInVS
        $vsVersionNumber = [decimal] $vsVersion
    }
    catch [System.Exception]
    {
        Write-Verbose ("Failed to get Dac Framework (installed with Visual Studio) location with exception: " + $_.Exception.Message) -verbose
        $vsVersionNumber = 0
    }

    if (($vsVersionNumber -ge $sqlVersionNumber) -and ($vsVersionNumber -ge $sqlMsiVersionNumber))
    {
        $dacPath = $vsDacPath
    }
	elseif ($sqlVersionNumber -ge $sqlMsiVersionNumber)
    {
        $dacPath = $sqlDacPath
    }
    else
    {
        $dacPath = $sqlMsiDacPath
    }

    if ($dacPath -eq $null)
    {
        throw  "Unable to find the location of Dac Framework (SqlPackage.exe) from registry on machine $env:COMPUTERNAME"
    }
    else
    {
        return $dacPath
    }
}

function Get-RegistryValueIgnoreError
{
    param
    (
        [parameter(Mandatory = $true)]
        [Microsoft.Win32.RegistryHive]
        $RegistryHive,

        [parameter(Mandatory = $true)]
        [System.String]
        $Key,

        [parameter(Mandatory = $true)]
        [System.String]
        $Value,

        [parameter(Mandatory = $true)]
        [Microsoft.Win32.RegistryView]
        $RegistryView
    )

    try
    {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($RegistryHive, $RegistryView)
        $subKey =  $baseKey.OpenSubKey($Key)
        if($subKey -ne $null)
        {
            return $subKey.GetValue($Value)
        }
    }
    catch
    {
    }
    return $null
}

function Get-SubKeysInFloatFormat($keys)
{
    $targetKeys = @() 
        foreach ($key in $keys) 
        {		  
            try {
                $targetKeys += [decimal] $key
            }
            catch {}
        }
   
    $targetKeys    
}

function Get-SqlPackageForSqlVersion([int] $majorVersion, [bool] $wow6432Node)
{
    $sqlInstallRootRegKey = "SOFTWARE", "Microsoft", "Microsoft SQL Server", "$majorVersion" -join [System.IO.Path]::DirectorySeparatorChar

    if ($wow6432Node -eq $true)
    {
        $sqlInstallRootPath = Get-RegistryValueIgnoreError LocalMachine "$sqlInstallRootRegKey" "VerSpecificRootDir" Registry64
    }
    else
    {        
        $sqlInstallRootPath = Get-RegistryValueIgnoreError LocalMachine "$sqlInstallRootRegKey" "VerSpecificRootDir" Registry32
    }
    
    if ($sqlInstallRootPath -eq $null)
    {
        return $null
    }
    
    Write-Verbose -verbose "Sql Version Specific Root Dir for version $majorVersion as read from registry: $sqlInstallRootPath"    
        
    $DacInstallPath = [System.IO.Path]::Combine($sqlInstallRootPath, "Dac", "bin", "SqlPackage.exe")

    if (Test-Path $DacInstallPath)
    {
        Write-Verbose -verbose "Dac Framework installed with SQL Version $majorVersion found at $DacInstallPath on machine $env:COMPUTERNAME"
        return $DacInstallPath
    }
    else
    {
        return $null
    }
}

function Locate-HighestVersionSqlPackageWithSql()
{
    $sqlRegKey = "HKLM:", "SOFTWARE", "Wow6432Node", "Microsoft", "Microsoft SQL Server"-join [System.IO.Path]::DirectorySeparatorChar
    $sqlRegKey64 = "HKLM:", "SOFTWARE", "Microsoft", "Microsoft SQL Server"-join [System.IO.Path]::DirectorySeparatorChar

    if (-not (Test-Path $sqlRegKey))
    {
        $sqlRegKey = $sqlRegKey64
    }

    if (-not (Test-Path $sqlRegKey))
    {
        return $null, 0
    }

    $keys = Get-Item $sqlRegKey | %{$_.GetSubKeyNames()} 
    $versions = Get-SubKeysInFloatFormat $keys | Sort-Object -Descending

    Write-Verbose -verbose "Sql Versions installed on machine $env:COMPUTERNAME as read from registry: $versions"        

    foreach ($majorVersion in $versions) 
    {
        $DacInstallPathWow6432Node = Get-SqlPackageForSqlVersion $majorVersion $true
        $DacInstallPath = Get-SqlPackageForSqlVersion $majorVersion $false

        if ($DacInstallPathWow6432Node -ne $null)
        {            
            return $DacInstallPathWow6432Node, $majorVersion
        }
        elseif ($DacInstallPath -ne $null)
        {
            return $DacInstallPath, $majorVersion
        }
    }

    Write-Verbose -verbose "Dac Framework (installed with SQL) not found on machine $env:COMPUTERNAME"      

    return $null, 0
}

function Locate-HighestVersionSqlPackageWithDacMsi()
{
    $sqlRegKeyWow = "HKLM:", "SOFTWARE", "Wow6432Node", "Microsoft", "Microsoft SQL Server", "DACFramework", "CurrentVersion" -join [System.IO.Path]::DirectorySeparatorChar
    $sqlRegKey = "HKLM:", "SOFTWARE", "Microsoft", "Microsoft SQL Server", "DACFramework", "CurrentVersion" -join [System.IO.Path]::DirectorySeparatorChar

	$sqlKey = "SOFTWARE", "Microsoft", "Microsoft SQL Server", "DACFramework", "CurrentVersion" -join [System.IO.Path]::DirectorySeparatorChar
	
    if (Test-Path $sqlRegKey)
    {
        $dacVersion = Get-RegistryValueIgnoreError LocalMachine "$sqlKey" "Version" Registry64
        $majorVersion = $dacVersion.Substring(0, $dacVersion.IndexOf(".")) + "0"
    }
    
    if (Test-Path $sqlRegKeyWow)
    {
        $dacVersionX86 = Get-RegistryValueIgnoreError LocalMachine "$sqlKey" "Version" Registry32
        $majorVersionX86 = $dacVersionX86.Substring(0, $dacVersionX86.IndexOf(".")) + "0"
    }

	if ((-not($dacVersion)) -and (-not($dacVersionX86)))
	{
	    Write-Verbose -verbose "Dac Framework (installed with DAC Framework) not found on machine $env:COMPUTERNAME"   
	    return $null, 0
	}    

    if ($majorVersionX86 -gt $majorVersion)
    {
        $majorVersion = $majorVersionX86
    }

	$dacRelativePath = "Microsoft SQL Server", "$majorVersion", "DAC", "bin", "SqlPackage.exe" -join [System.IO.Path]::DirectorySeparatorChar
	$programFiles = $env:ProgramFiles
	$programFilesX86 = "${env:ProgramFiles(x86)}"

	if (-not ($programFilesX86 -eq $null))
	{
	    $dacPath = $programFilesX86, $dacRelativePath -join [System.IO.Path]::DirectorySeparatorChar

		if (Test-Path("$dacPath"))
		{
            Write-Verbose -verbose "Dac Framework (installed with DAC Framework Msi) found on machine $env:COMPUTERNAME at $dacPath"  
            return $dacPath, $majorVersion
		}		
	}

	if (-not ($programFiles -eq $null))
	{
	    $dacPath = $programFiles, $dacRelativePath -join [System.IO.Path]::DirectorySeparatorChar

		if (Test-Path($dacPath))
		{
            Write-Verbose -verbose "Dac Framework (installed with DAC Framework Msi) found on machine $env:COMPUTERNAME at $dacPath"  
            return $dacPath, $majorVersion
		}		
	}
    
    return $null, 0
}

function Locate-SqlPackageInVS([string] $version)
{
    $vsRegKeyForVersion = "SOFTWARE", "Microsoft", "VisualStudio", $version -join [System.IO.Path]::DirectorySeparatorChar

    $vsInstallDir = Get-RegistryValueIgnoreError LocalMachine "$vsRegKeyForVersion" "InstallDir" Registry64

    if ($vsInstallDir -eq $null)
    {
        $vsInstallDir = Get-RegistryValueIgnoreError LocalMachine "$vsRegKeyForVersion"  "InstallDir" Registry32
    } 

    if ($vsInstallDir)
    {
        Write-Verbose -verbose "Visual Studio install location: $vsInstallDir" 

        $dacExtensionPath = [System.IO.Path]::Combine("Extensions", "Microsoft", "SQLDB", "DAC")
        $dacParentDir = [System.IO.Path]::Combine($vsInstallDir, $dacExtensionPath)

        if (Test-Path $dacParentDir)
        {
            $dacVersionDirs = Get-ChildItem $dacParentDir | Sort-Object @{e={$_.Name -as [int]}} -Descending

            foreach ($dacVersionDir in $dacVersionDirs) 
            {
                $dacVersion = $dacVersionDir.Name
                $dacFullPath = [System.IO.Path]::Combine($dacVersionDir.FullName, "SqlPackage.exe")

                if(Test-Path $dacFullPath -pathtype leaf)
                {
                    Write-Verbose -verbose "Dac Framework installed with Visual Studio found at $dacFullPath on machine $env:COMPUTERNAME"
                    return $dacFullPath, $dacVersion
                }
                else
                {
                    Write-Verbose -verbose "Unable to find Dac framework installed with Visual Studio at $($dacVersionDir.FullName) on machine $env:COMPUTERNAME"
                }
            }
        }
    }

    return $null, 0
}

function Locate-HighestVersionSqlPackageInVS()
{
    $vsRegKey = "HKLM:", "SOFTWARE", "Wow6432Node", "Microsoft", "VisualStudio" -join [System.IO.Path]::DirectorySeparatorChar
    $vsRegKey64 = "HKLM:", "SOFTWARE", "Microsoft", "VisualStudio" -join [System.IO.Path]::DirectorySeparatorChar

    if (-not (Test-Path $vsRegKey))
    {
        $vsRegKey = $vsRegKey64
    }

    if (-not (Test-Path $vsRegKey))
    {
        Write-Verbose -verbose "Visual Studio not found on machine $env:COMPUTERNAME"     
        return $null, 0
    }

    $keys = Get-Item $vsRegKey | %{$_.GetSubKeyNames()} 
    $versions = Get-SubKeysInFloatFormat $keys | Sort-Object -Descending 

    Write-Verbose -verbose "Visual Studio versions found on machine $env:COMPUTERNAME as read from registry: $versions"        

    foreach ($majorVersion in $versions)
    {
        $dacFullPath, $dacVersion = Locate-SqlPackageInVS $majorVersion

        if ($dacFullPath -ne $null)
        {
            return $dacFullPath, $dacVersion
        }
    }

    Write-Verbose -verbose "Dac Framework (installed with Visual Studio) not found on machine $env:COMPUTERNAME"    

    return $null, 0
}

$ASTERISK_PASSWORD = "********"

$indexOfTargetPassword = $sqlPackageArguments.IndexOf("/TargetPassword");
if( $indexOfTargetPassword -ge 0 )
{
    $indexOfFirstQuote = $sqlPackageArguments.IndexOf("'",$indexOfTargetPassword);
    $indexOfSecondQuote = $sqlPackageArguments.IndexOf("'",$indexOfFirstQuote+1);
    $sqlPackageArgumentsToBeLogged = $sqlPackageArguments.Substring(0,$indexOfFirstQuote+1) + $ASTERISK_PASSWORD + $sqlPackageArguments.Substring($indexOfSecondQuote) 
}
else
{
    $sqlPackageArgumentsToBeLogged = $sqlPackageArguments
}
Write-Verbose "sqlPackageArguments = $sqlPackageArgumentsToBeLogged" -Verbose

$sqlPackage = Get-SqlPackageOnTargetMachine

$sqlPackageArguments = $sqlPackageArguments.Trim('"', ' ')

$command = "`"$sqlPackage`" $sqlPackageArguments"

$command = $command.Replace("'", "`"")

$indexOfTargetPassword = $command.IndexOf("/TargetPassword");
if( $indexOfTargetPassword -ge 0 )
{
    $indexOfFirstQuote = $command.IndexOf('"',$indexOfTargetPassword);
    $indexOfSecondQuote = $command.IndexOf('"',$indexOfFirstQuote+1);
    $commandToBeLogged = $command.Substring(0,$indexOfFirstQuote+1) + $ASTERISK_PASSWORD + $command.Substring($indexOfSecondQuote) 
}
else
{
    $commandToBeLogged = $command
}
Write-Verbose "Executing : $commandToBeLogged" -Verbose

$PowershellVersion5 = "5"
$ErrorActionPreference = 'Continue'

if ($PSVersionTable.PSVersion.Major -ge $PowershellVersion5)
{
    cmd.exe /c "$command"
}
else
{
    cmd.exe /c "`"$command`""
}

$ErrorActionPreference = 'Stop'

# SIG # Begin signature block
# MIIjkgYJKoZIhvcNAQcCoIIjgzCCI38CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCASfteqeV7jt1Fl
# qrQmDCdwFY9iW8VvbialeekQtAqBEKCCDYEwggX/MIID56ADAgECAhMzAAACUosz
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVZzCCFWMCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgk+0i4u7t
# lVNENchkNwonv+nMLJrr66liJU0hd8m9nQQwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAJuFvmt4ACj0KguPRzyCxZd+Nzl0YTTHvZYw2R4hNB
# EOj9AXDlPoadGp17FkFTXeLX8CNX4KDhhWDrbPupByiu9whU//RAEJ38MjydQkex
# kbz5POVqy9i9zbkpRqwcu85YlzSPyjYsXDFcVAxmliZm1t4t+O5Qu63frxqTY3uF
# SaCE0cX+dZ53T5hzKp/6ZwVjOlfbpksdECcStIt5puu2gHC84vK6YHFn+k79kByV
# o8KzlSJVTJWJ8/zBf+dwlvKqf6IRsur6InrK9YajDTLDt6qEXRNYh/x8r803ddV2
# k1tpI7UYmd3vqwXXpK64aWas7nuIrf7aFBL0i+CUUaF6oYIS8TCCEu0GCisGAQQB
# gjcDAwExghLdMIIS2QYJKoZIhvcNAQcCoIISyjCCEsYCAQMxDzANBglghkgBZQME
# AgEFADCCAVUGCyqGSIb3DQEJEAEEoIIBRASCAUAwggE8AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEICOpFfTdN5tNhxKAfc+BruQrFLBiPhyfqxwOS9ko
# 6UwyAgZhvLPAB10YEzIwMjIwMTI1MTMyNjA4LjE5NVowBIACAfSggdSkgdEwgc4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1p
# Y3Jvc29mdCBPcGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjozMkJELUUzRDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZaCCDkQwggT1MIID3aADAgECAhMzAAABYtD+AvMB5c1JAAAA
# AAFiMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MB4XDTIxMDExNDE5MDIyMloXDTIyMDQxMTE5MDIyMlowgc4xCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVy
# YXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjozMkJE
# LUUzRDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAO+GodT2ucL3Mr2DQsv2
# ELNbSvKyBpYdUKtUBWiZmFVy18pG/pucgkrc5i9tu8CY7GpWV/CQNmHG2mVeSHMJ
# vbwCc/AAv7JP3bFCt6Zg75IbVSNOGA1eqLbmQiC6UAfSKXLN3dHtQ5diihb3Ymzp
# NP9K0cVPZfv2MXm+ZVU0RES8cyPkXel7+UEGE+kqdiBNDdb8yBXd8sju+90+V4nz
# YC+ZWW7SFJ2FFZlASpVaHpjv+eGohXlQaSBvmM4Q0xe3LhzQM8ViGz9cLeFSKgFf
# SY7qizL7wUg+eqYvDUyjPX8axEQHmk0th23wWH5p0Wduws43qNIo0OQ0mRotBK71
# nykCAwEAAaOCARswggEXMB0GA1UdDgQWBBTLxEoRYEpDtzp84B5WlZN2kP4qazAf
# BgNVHSMEGDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBH
# hkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNU
# aW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUF
# BzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0
# YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IBAQAtQa3DoXYbW/cXACbcVSFGe4gC8GXs
# FxSHT3JgwFU/NdJOcbkcFTVvTp6vlmTvHm6sIjknRBB0Xi1NBTqPw20u6u/T7Cnc
# /z0gT6mf9crI0VR9C+R1CtjezYKZEdZZ7fuNQWjsyftNDhQy+Rqnqryt0VoezLal
# heiinHzZD/4Y4hZYPf0u8TSv1ZfKtdBweWG3QU0Lp/I9SbIoemDG97RULMcPvq2u
# fhUp3OMiYQGL1WqkykSnqRJsM2IcA4l4dmoPNP6dLg5Dr7NVoYKIMInaQVZjSwDM
# ZhWryvfizX0SrzyLgkMPhLMVkfLxQQSQ37NeFk7F1RfeAkNWAh6mCORBMIIGcTCC
# BFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJv
# b3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcN
# MjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0
# VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEw
# RA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQe
# dGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKx
# Xf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4G
# kbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEA
# AaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7
# fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMC
# AYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvX
# zpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20v
# cGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYI
# KwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0g
# AQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYB
# BQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUA
# bQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOh
# IW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS
# +7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlK
# kVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon
# /VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOi
# PPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/
# fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCII
# YdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0
# cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7a
# KLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQ
# cdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+
# NR4Iuto229Nfj950iEkSoYIC0jCCAjsCAQEwgfyhgdSkgdEwgc4xCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKTAnBgNVBAsTIE1pY3Jvc29mdCBP
# cGVyYXRpb25zIFB1ZXJ0byBSaWNvMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjoz
# MkJELUUzRDUtM0IxRDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIjCgEBMAcGBSsOAwIaAxUAmrP6Chrbz0ax7s57n5Pop3VC8gyggYMwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIF
# AOWZ8zQwIhgPMjAyMjAxMjUwNzU1MzJaGA8yMDIyMDEyNjA3NTUzMlowdzA9Bgor
# BgEEAYRZCgQBMS8wLTAKAgUA5ZnzNAIBADAKAgEAAgIi2AIB/zAHAgEAAgIRZzAK
# AgUA5ZtEtAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIB
# AAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBAIr2Gn4K2aGSNkCB
# /9ZuiZOqOxqojIQX5opeHcY96tL5Tb43n3hGucqxwg6hZnOp3THn7xTF9DP+JN0P
# OJkc9PG5BbwGR2xFTT9lR3OowIreuhZhrhnWEN+AHxpwHUhyfl1HuHgtjI7v7Tvm
# zljBOsbKEQOGn/t+VZoDewilxGolMYIDDTCCAwkCAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAFi0P4C8wHlzUkAAAAAAWIwDQYJYIZIAWUD
# BAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQgr07B6K/kawoH99XwbSUgrD5DI7OJhCJchB93ZrDdaCEwgfoGCyqGSIb3
# DQEJEAIvMYHqMIHnMIHkMIG9BCCKqhiV+zwNDrpU7DRB7Mi57xi6GBNYsGjgZqq2
# qVMKMjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# YtD+AvMB5c1JAAAAAAFiMCIEIKxo1pvH3/40TmGZ/NFOiv0aBYJ6kGIHQZ++tNY8
# MMpVMA0GCSqGSIb3DQEBCwUABIIBAC3jSkEK6jCZSZDynle7/Rp2PnXOINxZoVWB
# 3RejQ7L2s00ysnNeocJsSC8qWzr+YUhVgnT7nLkldIpvg2vJVWoa8DYDY4fd3Xc3
# KCwkNsPlC2WJip94fe2BgA5dJ2uGzbsays90W4JOUoVHRauyYvXbgAkBnKYX1QLm
# Uj3SyAcSl860bfo/K3yP/HtEn16z2dh350qa/GsKg+sJtT523lMik/5IKc2uHjkD
# k2dLVwi5Qwu6EEGZGNKB2JuBiU7sTEhTPKeY4f6qFMgttEw/URsc7CZXW4ja4vip
# rsx4QKSRSmT60icnNX8KkMXPrBDl6WHwZlJhZbgaTmoTMdJeXU0=
# SIG # End signature block
