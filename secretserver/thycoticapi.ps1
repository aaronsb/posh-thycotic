#Powershell service integration for thycotic secret server
#https://secretserver.domain.com/SecretServer/webservices/sswebservice.asmx
# add an error handler.


function Remove-ThycoticAPI
{
	Remove-Variable ThycoticService -scope global
	Remove-Variable ThycoticConfig -scope global
}

function Init-ThycoticAPI
{param($ThyConfigFile = ".\ThycoticAPIConf.xml",[switch]$Persistent = $true)

	#this api init allows you to set global objects on init or not.
	#this means that you can init an object for your own use somewhere privately,
	#or leave it global for a more command-line oriented interaction with secretserver.
	#regardless, it's dependent on a configuration xml to give it the WSDL url and associated connection string info.
	#when you're done with this, be a good chap and execute Remove-ThycoticAPI to clear up your stuff.
	if ($Persistent -eq $true)
	{
		#instantiate the config file
		if ((test-path $ThyConfigFile) -eq $true)
		{
			#use standalone configuration file
			$global:ThycoticConfig = [xml](gc $ThyConfigFile)
		}
		else
		{
			#use toolbox environment integration
			$global:ThycoticConfig = Get-ToolboxXMLConfigs -ServiceName SecretServer
		}
		#Generate the WSDL url from the config file.
		$WSDL = ($ThycoticConfig.root.Server.protocol + "://" + $ThycoticConfig.root.server.DNSHostName + $ThycoticConfig.root.server.WSDL)
		#instantiate the webservice proxy with the namespace "Thycotic" - handy for creating objects that need to be submitted back to the mothership
		$global:ThycoticService =  New-WebServiceProxy -uri $WSDL -namespace "Thycotic" -UseDefaultCredential
		#write verbose, because we're all team players here.
		write-verbose "Setting global objects ThycoticConfig and ThycoticService"
	}
	else
	{
		#same as above, but return the service once to the caller, and don't allocate a global object.
		$ThycoticConfig = [xml](gc $ThycoticConfig)
		$WSDL = ($ThycoticConfiguration.root.Server.protocol + "://" + $ThycoticConfiguration.root.server.DNSHostName + $ThycoticConfiguration.root.server.WSDL)
		$ThycoticService =  New-WebServiceProxy -uri $WSDL -namespace "Thycotic"
		write-verbose "Not returning any global objects and emitting the WebServiceProxy"
		return $ThycoticService
	}	
}

function Get-ThyAuthToken
{param([switch]$UseSessionDomain = $true,$CredentialCacheFile = ($env:username + "-ThycoticCred.xml"),[switch]$Persistent=$true)
	if (!$ThycoticService.Url)
	{
		try
		{
			Init-ThycoticAPI
		}
		catch
		{
			Resolve-Error
		}
	}
	
	if ((test-path $CredentialCacheFile) -eq $false)
	{
		$CredentialCacheFile = ((gci $Profile.CurrentUserCurrentHost).DirectoryName + "\" + $env:username + "-ThycoticCred.xml")
		#default cache file wasn't found. Let's try our powershell profile default.
	}
	else
	{
		$CredentialCacheFile = (gci $CredentialCacheFile).FullName
		#The default cache file was found. Let's try that one.
	}
	
	#get the secure(ish) credential object. 
	try
	{
		$CredentialCache = Get-CachedCredential -CredPath $CredentialCacheFile
	}
	catch
	{
		Resolve-Error
		break;
	}
	
	
	if ($ThycoticService.Url -and $ThycoticConfig.Root)
	{
		if ($UseSessionDomain -eq $true)
		{
			$SSDomain = $ThycoticConfig.root.Server.SSUserDomains.Domain | ?{$_.Primary -eq $true}
			if ([Environment]::UserDomainName -eq $SSDomain.WindowsDomain)
			{
				#do some secure string things that are...shady
				#copy the secure object.
				$password = $CredentialCache.password
				#marshall the binary string datatype to an interop object.
				$BSTR = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password);
				#allocate the string to an unmanaged object.
				$password = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($BSTR);
				#free the data type pointer representing the (formerly) secure string.
				[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR);
				#insert the request through the web service proxy api
				$Token = $ThycoticService.Authenticate($CredentialCache.UserName, $password, $null, $SSDomain.Name)
				#overwrite the clear text password from memory. This is important. Clear-item overwrites (nulls) the string.
				#Using a method like Remove-item would only mark garbage collection for eventual removal and is insecure.
				Clear-Item variable:password
				Parse-ThycoticErrorObject $Token
				if ($Persistent = $true)
				{
					$global:ThyAuth = $Token.Token
					$ThyAuth
				}
				if ($Persistent = $false)
				{
					$Token.Token
				}
			}
			else
			{
				write-error "Current user does not match any found primary Thycotic Domains"
			}
		}
		else
		{
			write-error "Sorry, not yet implemented!"
		}
		
	}
	else
	{
		write-error "Thycotic Powershell API not initialized properly."
	}
}


function Get-ThySecret
{param($SearchString,[int]$SecretID,[int]$minSearchTermLength = 2,[int]$maxSecrets = 5,[switch]$Full)
	Renew-ThyAuthToken
	$Secret = $null
	if ($SecretID -eq "")
	{
		try
		{
			if ($SearchString.length -le $minSearchTermLength)
			{
				write-error "$minSearchTermLength or more characters are needed to Search for secrets."
				return
			}
			else
			{
				$Secrets = Search-ThySecret $SearchString
				
				$i=0
				do
				{
					if ($i -ge $Secrets.count)
					{
						#stop processing if no more secrets are available to retrieve.
						break
					}
					$Secret = $null #clear secret object
					$Secret = $ThycoticService.GetSecret($ThyAuth,$Secrets[$i].SecretId,$false,$null)
					Parse-ThycoticErrorObject $Secret
					$Secret = $Secret.Secret
					
					#return a pendantic security object.
					if ($Full -eq $False)
					{
						[pscustomobject]@{	"Description" = $Secret.Name;`
						"Username"= ($Secret.Items | ?{$_.FieldDisplayName -eq "Username"}).Value;`
						"Password"= ($Secret.Items | ?{$_.IsPassword -eq $true}).Value;}
					}
					else
					{
						$Secret
					}
					$i++
					if ($i -gt $maxSecrets)
					{
						write-warning ("maxSecrets (" + $maxSecrets + ") reached. Specifiy higher integer to return more objects.")
					}
				}
				until ($i -gt $maxSecrets)
			}
			
		}
		catch
		{
		}
	}
	else
	{
		$Secret = $ThycoticService.GetSecret($ThyAuth,$SecretID,$false,$null)
		Parse-ThycoticErrorObject $Secret
		$Secret = $Secret.Secret
		
		#return a pendantic security object.
		if ($Simple -eq $true)
		{
			[pscustomobject]@{	"Description" = $Secret.Name;`
			"Username"= ($Secret.Items | ?{$_.FieldDisplayName -eq "Username"}).Value;`
			"Password"= ($Secret.Items | ?{$_.IsPassword -eq $true}).Value;}
		}
		else
		{
			$Secret
		}
	}
}

function Search-ThySecret
{param($SearchString)
	Renew-ThyAuthToken
	if ($ThycoticService.Url -and $ThyAuth)
	{
		$Result = $ThycoticService.SearchSecrets($ThyAuth,$SearchString,$false,$false)
		Parse-ThycoticErrorObject $Result
	}
	if ($Result.SecretSummaries)
	{
		return $Result.SecretSummaries
	}
}

function Get-ThyField
{param($TemplateObject,[int]$FieldID,$FieldName)
	if ($FieldID)
	{
		Return ($TemplateObject.Fields | Where {$_.DisplayName -eq $FieldName}).Id
	}
	else
	{
		Return ($TemplateObject.Fields | Where {$_.Id -eq $FieldID}).Id
	}
	
}



function Get-ThySecretTemplateConstructor
{param($FilterString,[int]$TemplateID)
	if ((!$FilterString) -and (!$TemplateID))
	{
		return Get-ThyTemplates | %{ThySecretTemplateConstructor $_}
	}
	if ($FilterString -and $TemplateID)
	{
		write-warning "Both FilterString and TemplateID search were specified.`r`nTemplateID has higher priority, so only returning results from TemplateID."
		return Get-ThyTemplates -TemplateID $TemplateID | %{ThySecretTemplateConstructor $_}
	}
	if ($TemplateID)
	{
		return Get-ThyTemplates -TemplateID $TemplateID | %{ThySecretTemplateConstructor $_}
	}
	if ($FilterString)
	{
		return Get-ThyTemplates -FilterString $FilterString | %{ThySecretTemplateConstructor $_}
	}
	
}



function Submit-CompleteSecretTemplate
{param($TemplateObject)
	if (!$TemplateObject.CustomPSTemplate)
	{
		throw "Use a working Constructor function to generate a valid template."
	}
	Renew-ThyAuthToken
	$Object = $ThycoticService.AddSecret($ThyAuth,[int]$TemplateObject.Id,$TemplateObject.SecretName,$TemplateObject.Fields.Id,$TemplateObject.Fields.FieldValue,$TemplateObject.TargetFolder)
	Parse-ThycoticErrorObject $Object
}

function Get-ThySecurePassword
{param($secretFieldID,[switch]$AsSecureString)
	Renew-ThyAuthToken
	$Object = $ThycoticService.GeneratePassword($ThyAuth,$secretFieldID)
	Parse-ThycoticErrorObject $Object
	if ($AsSecureString)
	{
		return (ConvertTo-Securestring -String $Object.GeneratedPassword -AsPlainText -Force)
	}
	else
	{
		return $Object.GeneratedPassword
	}
	
}

function New-ThySecretObject
{param($CompletedTemplateObject,$TemplateName,[int]$TemplateID,[switch]$EmitTemplateObject)
	if (!$CompletedTemplateObject)
	{
		if ($TemplateID)
		{
			$Template = Get-ThyTemplates -TemplateID $TemplateID
		}
		else
		{
			$Template = Get-ThyTemplates -FilterString $TemplateName
			if ($Template.count -gt 1)
			{
				throw "Ambiguous template selection. Only one template can be assembled at a time."
			}
		}
		if (!$Template)
		{
			throw "No Template found by that ID or search string."
		}
		if (!$EmitTemplateObject)
		{
			write-warning "Template object is not complete.`r`nReturn completed object to New-Secret with FieldValues defined and verified.`r`nUse the switch -EmitTemplateObject to get a template of the type you requested."
		}
		if ($EmitTemplateObject)
		{
			return TemplateConstructor -TemplateObject $Template
		}
		
	}
	else
	{
		$Template = $CompletedTemplateObject
		if (($Template|gm)[0].TypeName -eq "Thycotic.SecretTemplate")
		{
			if (($Template.fields[0] | gm | ?{$_.name -eq "FieldValue"}).MemberType -ne "NoteProperty")
			{
				throw "Template Fields require the extended NoteProperty named FieldValue to exist. Try processing with TemplateConstructor."
			}
		}
		else
		{
			throw "Template Object is not of type Thycotic.SecretTemplate"
		}
	}
	
	
	
}

#TemplateConstructor
#
#Adds noteproperty of fieldvalue to object.
#this is super handy when attempting to create a new secret object.
#
#
function TemplateConstructor
{param($TemplateObject)
	
	$TemplateObject | Add-Member -MemberType NoteProperty -Name TargetFolder -value "" -force
	$TemplateObject | Add-Member -MemberType NoteProperty -Name SecretName -value "" -force
	$TemplateObject | Add-Member -MemberType NoteProperty -Name CustomPSTemplate -value $true -force
	$TemplateObject.Fields | Add-Member -MemberType NoteProperty -Name FieldValue -value "" -force
	$TemplateObject.Fields | Add-Member -MemberType NoteProperty -Name Verified -value $false -force
	return $TemplateObject
}

function Get-ThyTemplates
{param($FilterString,[int]$TemplateID)
	Renew-ThyAuthToken
	$Object = $ThycoticService.GetSecretTemplates($ThyAuth)
	Parse-ThycoticErrorObject $Object
	if ((!$FilterString) -and (!$TemplateID))
	{
		return $Object.SecretTemplates
	}
	if ($TemplateID -and $FilterString)
	{
		write-warning "Both FilterString and TemplateID search were specified.`r`nTemplateID has higher priority, so only returning results from TemplateID."
		return $Object.SecretTemplates | ?{$_.ID -eq $TemplateID}
	}
	if ($TemplateID)
	{
		return $Object.SecretTemplates | ?{$_.ID -eq $TemplateID}
	}
	if ($FilterString)
	{
		return $Object.SecretTemplates | ?{$_.Name -match $FilterString}
	}
}


function Get-ThyFolderTree
{
	[System.Collections.ArrayList]$folders = @()
	$folders.add([pscustomobject]@{"Name" = "root";"Id" = (0);"ParentId" = $null}) > null
	foreach ($Folder in (Search-ThyFolders))
	{
		if ($folder.ParentFolderId -eq (-1))
		{$folder.ParentFolderId = 0}
		if ($folder.Id -eq (-1))
		{$folder.Id = 0}
		$folders.add([pscustomobject]@{"Name" = $folder.Name;"Id" = [int]$folder.Id;"ParentId" = [int]$folder.ParentFolderId}) > null
	}
	$folders | Sort-Object -Property Parent
	#Get-Child -InputObject ($folders | Sort-Object -Property Parent) -id -1
}



function Get-MyADGroupMember ($GroupName) {
     (Get-ADGroupMember -Identity $GroupName).samAccountName
}


function Get-ThyFolder
{param($folderId)
	Renew-ThyAuthToken
	$Object = $ThycoticService.FolderExtendedGet($ThyAuth,$folderId)
	Parse-ThycoticErrorObject $Object
	return $Object.Folder
}


function Get-ThySecretTemplateFields
{param($FilterString,[int]$TemplateID)
	
}

function Get-ThySecretsByFolder
{param([int]$FolderID = $null,$FolderName,$SearchString,$IncludeSubfolders = $true)
	Renew-ThyAuthToken
	$Object = $ThycoticService.SearchSecretsByFolder($ThyAuth,$SearchString,$FolderID,$IncludeSubfolders,$false,$false)
	Parse-ThycoticErrorObject $Object
	return $Object.SecretSummaries
}


function Parse-ThycoticErrorObject
{param($Object)
	#simplistic way to emit errors "properly". I would like to figure out how to take an object piped to this function, emit errors, then 
	#re-emit the object again for further processing.
	foreach ($Message in $Object.Errors)
	{
		write-error $Message
	}
}

function Renew-ThyAuthToken
{
	$ErrorActionPreference = "stop"
	try
	{
		$Object = $ThycoticService.GetTokenIsValid($ThyAuth)
		Parse-ThycoticErrorObject $Object
	}
	catch
	{
		write-warning "Renewing Authentication Token"
		Get-ThyAuthToken > $null
	}
}

function Search-ThyFolders
{param($SearchString)
	Renew-ThyAuthToken
	$Object = $ThycoticService.SearchFolders($ThyAuth,$SearchString)
	Parse-ThycoticErrorObject $Object
	return $Object.Folders
}


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

## Resolve-Error
## 
# from http://blogs.msdn.com/b/powershell/archive/2006/12/07/resolve-error.aspx
# 
#

function Resolve-Error($ErrorRecord=$Error[0])
{
    $ErrorRecord | fl * -f | Out-Default
    $ErrorRecord.InvocationInfo | fl * -f | Out-Default

    $Exception = $ErrorRecord.Exception
    for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
    {
        "*$i* " * 15
        $Exception | fl * -f | Out-Default
    }
}

function Read-HostUnmasked
{param($Prompt)
	[Console]::Out.Write(($Prompt + ": "))
	[system.console]::ReadLine()
}

function Read-HostMasked([string]$prompt="Password") {
  $password = Read-Host -AsSecureString $prompt;  
  $BSTR = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR($password);
  $password = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($BSTR);
  [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR);
  return $password;
}

Function Get-FileName($initialDirectory)
{   
 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
 Out-Null

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.filter = "All files (*.*)| *.*"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
}

function isURIWeb
{param($address) 
    $uri = $address -as [System.URI] 
    $uri.AbsoluteURI -ne $null -and $uri.Scheme -match '[http|https]' 
} 
