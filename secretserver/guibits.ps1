function Select-ThyTemplate
{
	$List = Get-ThyTemplates | Sort-Object -Property ID | %{$_.ID.ToString() + ":" + $_.Name.ToString()}
	$TemplateID = (New-SelectBox -BoxText "Thycotic Secret Template List" -List $List -yscale ($list.count * 10) | %{$_.split(":")})
	if (!$TemplateID)
	{
		write-error "No template selected."
	}
	else
	{
		[pscustomobject]@{"Name"=$TemplateID[1];"ID"=[int]$TemplateID[0]}
	}
}

function New-ThySecret
{
	try
	{
		$Template = (Select-ThyTemplate)
	}
	catch
	{
		"Unrecognized template selected."
		break
	}
	("You selected the " + $Template.Name + " template.")
	$ReadyToSubmit = Complete-InteractiveTemplate (New-ThySecretObject -TemplateID $Template.ID -EmitTemplateObject)
	"Review secret configuration. Password fields are not shown."
	""
	$ReadyToSubmit.Fields | ?{$_.IsPassword -ne $True} | Format-Table
	""
	$confirmation = Read-Host "Create Secret? [y/n]"
	while($confirmation -ne "y")
	{
		if ($confirmation -eq 'n') {return}
		$confirmation = Read-Host "Create Secret? [y/n]"
	}
	"Making secret."
	Submit-CompleteSecretTemplate $ReadyToSubmit
}

function New-DomainADAccount
{param($Template)
	#giant monsterous function that makes domain user accounts work.
	$ADAccountProperties = [pscustomobject]@{"DisplayName"="";"Email"="";"FirstName"="";"LastName"="";"Office"="";"Phone"=""}
	function PrivMakeUser
	{param($ADAccountProperties)
		foreach ($Property in ($ADAccountProperties | gm | ?{$_.MemberType -eq "NoteProperty"}).Name)
		{
			$ADAccountProperties.$Property = Read-Host -Prompt $Property
		}
		$ADAccountProperties | Add-Member -MemberType NoteProperty -Name "OU" -Value (Choose-ADOrganizationalUnit).DistinguishedName
		$ADAccountProperties | Add-Member -MemberType NoteProperty -Name "Name" -Value ($accountobject.fields | ?{$_.displayname -eq "Username"}).fieldvalue
		$ADAccountProperties | Add-Member -MemberType NoteProperty -Name "Password" -Value (ConvertTo-SecureString -String ($accountobject.fields | ?{$_.displayname -eq "password"}).fieldvalue -AsPlainText -Force)
	}
	
	#call object constructure, and use the active directory account template type.
	$AccountObject = Complete-InteractiveTemplate (New-ThySecretObject -TemplateName "Active Directory Account" -EmitTemplateObject)
	#submit the constructor to create the secret
	Submit-CompleteSecretTemplate $AccountObject
	#validate the secret
	try
	{
		$NewSecret = Get-ThySecret -SecretID (Get-ThySecretsByFolder -FolderID $AccountObject.TargetFolder | ?{$_.SecretName -eq $AccountObject.SecretName}).SecretId
		if (!$NewSecret)
		{
			write-error ("Could not locate secret with name " + $AccountObject.SecretName)
		}
		PrivMakeUser $ADAccountProperties
		New-QADUser -ParentContainer $ADAccountProperties.OU -Name $ADAccountProperties.Name -DisplayName $ADAccountProperties.DisplayName -UserPassword $ADAccountProperties.Password -Email $ADAccountProperties.Email -FirstName $ADAccountProperties.FirstName -LastName $ADAccountProperties.LastName -Office $ADAccountProperties.Office -PhoneNumber $ADAccountProperties.Phone
	}
	catch
	{
		write-error $error[0]
		#you are not going to space today. https://xkcd.com/1133/
		throw "Secret could not be verified. Manually verify SecretServer entry. Corresponding Active Directory object will not be created."
	}
	#get AD target for creation.
	#(Get-ACL "AD:$((Get-ADUser abockelie).distinguishedname)").access
	
	
}



function Complete-InteractiveTemplate
{param($TemplateObject)
	[Console]::Out.Write("`r`n`r`n`r`n`r`n`r`n`r`n`r`n")
	[Console]::Out.Write("--Thycotic Secret Server Interactive Secret Generator--`r`n")
	[Console]::Out.Write("Use selection dialog to choose target folder.`r`n")
	$ThycoticServerTargetFolder = Get-ThyFolderTreeDialog
	("You selected the " + $ThycoticServerTargetFolder.Name + " folder.")
	$TemplateObject.TargetFolder = ($ThycoticServerTargetFolder).Id
	
	$i=1
	write-progress  -activity "Thycotic Interactive Template Form" -status ("Checking Template State - " + $i) -percentcomplete (($i/$TemplateObject.Fields.Count)*100)
	if (!$TemplateObject.CustomPSTemplate)
	{
		throw "Use a working Constructor function to generate a valid template."
	}
	
	$TemplateObject.SecretName = Read-HostUnmasked -Prompt "SecretName"
	foreach ($Field in $TemplateObject.Fields)
	{
		write-progress -activity "Thycotic Interactive Template Form" -status ("Template field: " + $Field.DisplayName + " - Step " + $i + " of " + $TemplateObject.Fields.Count) -percentcomplete (($i/$TemplateObject.Fields.Count)*100)
		if ($Field.IsFile -eq $true)
		{
			write-warning ("Use the file selection dialog box to find content for field: " + $Field.DisplayName)
			$Field.FieldValue = Get-FileName
			
		}
		else
		{
			if ($Field.IsPassword -eq $true)
			{
				[Console]::Out.Write("Press [Enter] to generate secure string.`r`n")
				$Field.FieldValue = Read-HostMasked -prompt $Field.DisplayName
				if ($Field.FieldValue -eq "")
				{
					$Field.FieldValue = Get-ThySecurePassword -secretFieldID $Field.Id
				}
			}
			else
			{
				if ($Field.IsUrl -eq $true)
				{
					
					$URL = Read-HostUnmasked -Prompt ($Field.DisplayName)
					if ((isURIWeb $URL) -eq $false)
					{
						write-warning ("URI validation failed. Enter URL a second time to verify.`r`nYou typed: " + $URL)
						$URL = Read-HostUnmasked -Prompt ($Field.DisplayName)
					}
					$Field.FieldValue = $URL
				}
				else
				{
					$Field.FieldValue = Read-HostUnmasked -Prompt ($Field.DisplayName)
				}
				
			}
		}
		$Field.Verified = $true
		$i++
	}
	return $TemplateObject
}





function Get-ThyFolderTreeDialog
{
#generate a TreeView given a set of parent-child relationship keys.
#
#the input format should be a flat list with parent child references
#below this line is an example dataset that should parse correctly (csv-ish format)
#
#Name,ParentId,Id
#root,null,0
#Fruit,0,1
#Vegetables,0,2
#Apple,1,3
#Pear,1,4
#Carrot,2,5
#Broccoli,2,6
#IDislikeBroccoli,6,7
#
#The ID is a unique key for the given dataset. No two items should ever have the same ID
#The ParentID could be repeated multiple times. Each item contains a parent, up to and including the root.
#The input list needs to be sorted incrementally by their own ID. Other sorting orders will make the tree crawl slow.


# Region Node traversal recursion function
#
	function DoNodes
	{param($list,$Id,$parentNode,$Depth=0)

	# $list is the flat list of child-parent relational items to process, sorted incrementally by unique ID
	# $depth is used to remember the recursion depth. Might be good to break(); on some sort of recursion that gets too deep.
	# $Id is the lowest starting parent node ID. You sorted your flat list smallest to largest, so pick the one at the top of the list.
	# $parentnode on startup of this recursion should be the top node of your tree form, if it was like System.Windows.Forms.TreeNode it would be super handy.
	#
	# as you can see, each call of this recursion function iterates over every item in the list. Large sets of data will slow down.
	# to "bootstrap" this recusion function, start by pointing it at the root you'd like to process in the dataset, with the $parentNode parameter.
	# from there it will walk the tree.
	#
	# it is simplistic, and doesn't understand cyclic associations. If you'd like to loop forever, be my guest.
	# might be a good idea to somehow get a count of objects then break(); after some sort of max counter.
		foreach ($item in $list)
		{
			
			if ($item.ParentID -eq $Id)
			{
				#this section is commented out. Used to 
				#$indent = $Depth.tostring() * $Depth
				#"{0}{1}" -f $indent,$Node.Name
				
				#generate a new childnode object when we match an object to it's parent in the loop
				$childNode = New-Object System.Windows.Forms.TreeNode
				
				#name the childnode
				$childNode.text = $item.Name
				$childNode.name = $item.Name
				$childNode.tag = $item.Id
				#take the just called node and attempt to add the newly generated child node to it.
				[void]$parentNode.Nodes.Add($childNode)
				
				#now recurse until no more items are found. Once the last item in the list is processed,
				#the next parent node in the list is walked to the end
				#this will continue until the list is fully walked.
				DoNodes -Id $item.Id -list $list -Depth $($Depth+1) -parentNode $childNode
				
				
			}
		}

	}


	#Region Load assemblies

	# load forms
	# load drawing
	[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
	[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")


	# Region Form Creation
	
	#calculate the y scale for this big hot mess.
	$yScale = (Get-ThyFolderTree).count * 10
	# make a form
	# text the form
	# size the form
	$Form = New-Object System.Windows.Forms.Form
	$Form.Text = "ThuperDuperThecretFolderths"
	$Form.Size = New-Object System.Drawing.Size(300, $yScale)


	# Region OK button instantiate
	$OKButton = New-Object System.Windows.Forms.Button
	$OKButton.Location = New-Object System.Drawing.Point(75,($yScale - 80))
	$OKButton.Size = New-Object System.Drawing.Size(75,23)
	$OKButton.Text = "OK"
	$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
	$Form.AcceptButton = $OKButton
	$Form.Controls.Add($OKButton)


	# Region Cancel button instantiate
	$CancelButton = New-Object System.Windows.Forms.Button
	$CancelButton.Location = New-Object System.Drawing.Point(150,($yScale - 80))
	$CancelButton.Size = New-Object System.Drawing.Size(75,23)
	$CancelButton.Text = "Cancel"
	$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
	$Form.CancelButton = $CancelButton
	$Form.Controls.Add($CancelButton)


	# Region Treeview Object instantiate

	# create Treeview-Object
	# start location of TreeView control relative to form
	# size the treeview
	# add the treeview to the form
	$TreeView = New-Object System.Windows.Forms.TreeView
	$TreeView.Location = New-Object System.Drawing.Point(10, 40)
	$TreeView.Size = New-Object System.Drawing.Size(260, 20)
	$TreeView.Height = ($yScale - 160)
	$Form.Controls.Add($TreeView)


	# Region TreeView object population

	# generate the node root object
	# text the root node object
	# name the root node object
	# add the node to the treeview.
	$parentNode = New-Object System.Windows.Forms.TreeNode
	$parentNode.text = "Thycotic"
	$parentNode.name = "Thycotic"
	[void]$TreeView.Nodes.Add($parentNode)


	# from this point forward, you take the children of any nodes and add them to other children.
	# the true root of the treeview is the treeview control itself
	# anything added to treeview should be a child.

	$list = Get-ThyFolderTree | Sort-Object -Property Id
	DoNodes -list $list -id 0 -parentNode $parentNode

	$form.Topmost = $True
	$result = $Form.ShowDialog()

	if ($result -eq [System.Windows.Forms.DialogResult]::OK)
		{
			if ($TreeView.SelectedNode.Tag -eq $null)
			{
				$Selection = [PSCustomObject]@{"PermissionSettings"=$null;"Settings"=$null;"Id"=-1;"Name"="Thycotic";"ParentFolderId"=$null}
			}
			else
			{
				$Selection = (Get-ThyFolder -folderId $TreeView.SelectedNode.Tag)
			}
			
		}
	if (!$Selection)
	{throw "No Folder Selected"}
	else
	{return $Selection}
	if (gci null){remove-item null} #I am lazy. somewhere this thing writes a file called null. fix it.
}