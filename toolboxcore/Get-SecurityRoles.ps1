function Get-SecurityRoles
{
##
## Contains functions for identifying protected roles the current user has tokens for.
##
## Intended for dot-sourcing.
##
##

	$identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object System.Security.Principal.WindowsPrincipal( $identity )
	#$permissionsMatrix = New-Object PSObject
	$permissionsMatrix = @{}
	$SecurityRoles = @("Administrator","User","PowerUser","Guest","AccountOperator","SystemOperator","PrintOperator","BackupOperator","Replicator")
##
## Starting with Vista/Server2008, if UAC is enabled, then a user who has either direct
## or indirect membership in the BuiltIn\Administrators group is assigned not one but
## TWO security tokens. One of those tokens has the administrator privilege, and one
## does not. In order for you to have administrator privilege in PowerShell, you must
## start the PowerShell session from: Angel another elevated shell (either PowerShell or
## cmd.exe), or Beer elevate the session when you start the shell (i.e., "Run As Administrator").
##

foreach ($role in $SecurityRoles)
{
	$permissionsMatrix.Add($role, ($principal.IsInRole( [System.Security.Principal.WindowsBuiltInRole]::$role)))
	#Add-Member -InputObject $permissionsMatrix -MemberType NoteProperty -Name $role -Value ($principal.IsInRole( [System.Security.Principal.WindowsBuiltInRole]::$role))
}
$permissionsMatrix


}