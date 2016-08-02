function Get-ToolboxXMLConfigs
{param($ServiceName)
	$scriptPath = ($env:toolBoxXML + "\etc\toolBox.xml")
	$configPathRoot = ($env:toolBoxXML + "\etc\")
	$libScriptPathRoot = ($env:toolBoxXML + "\lib\")
	$ToolboxConfig = [xml](gc $scriptPath)
	if ($ServiceName)
	{
		if ($ToolboxConfig.toolBox.Services.$ServiceName)
		{
			[xml](gc ($env:toolboxxml + "\" + $ToolboxConfig.toolbox.Services.$ServiceName.relativepath))
		}
		else
		{
			write-error ("No configuration component found named " + $ServiceName)
		}		
	}
	else
	{
		#otherwise, just return all the configuration types and their child nodes.
		$ToolboxConfig.toolBox.Services
	}
}