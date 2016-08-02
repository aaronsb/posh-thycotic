function Get-CachedCredential
{
param($CredPath,$IntegratedCred,[switch]$ListCreds)

<#
	.SYNOPSIS
	Stores a credential as a session encrypted xml file on the machine.
	.EXAMPLE
	Get-MyCredential -CredPath $CredPath

    If a credential is stored in $CredPath, it will be used.
    If no credential is found, Export-Credential will start and offer to
    Store a credential at the location specified.
#>

	
	if ($ListCreds)
	{
		(Get-ToolboxXMLConfigs -ConfigType services -NamedConfig Authentication).authentication.account
	}
	else
	{
		if ($IntegratedCred)
		{
			$IntegratedCredConfig = (Get-ToolboxXMLConfigs -ConfigType services -NamedConfig Authentication).authentication.account
			$Cred = $IntegratedCredConfig | ?{$_.id -match "$IntegratedCred"}
			if ($Cred)
			{
				$CredPath = ($env:toolBoxXML + "\" + $Cred.credCacheRelativePath + "\" + $Cred.username + "_" + $Cred.id + ".xml")
			}
		}
		else
		{
			if (!$CredPath)
			{
				$CredPath = read-host "Fully qualified path for credential file"
			}
		}
		#=====================================================================
		# Export-Credential
		# Usage: Export-Credential $CredentialObject $FileToSaveTo
		#=====================================================================
		function Export-Credential($cred, $path) {
			  $cred = $cred | Select-Object *
			  $cred.password = $cred.Password | ConvertFrom-SecureString
			  $cred | Export-Clixml $path
		}
		if (!(Test-Path -Path $CredPath -PathType Leaf))
		{
			Export-Credential (Get-Credential -Message "Provide a credential you want to cache for future use.`r`nThe cache file will be saved to $CredPath.") $CredPath
		}
		$cred = Import-Clixml $CredPath
		$cred.Password = $cred.Password | ConvertTo-SecureString
		$Credential = New-Object System.Management.Automation.PsCredential($cred.UserName, $cred.Password)
		Return $Credential
	}
}