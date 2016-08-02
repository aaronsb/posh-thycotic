function New-SelectBox
{Param($BoxText,[array]$List,[int]$yscale=0,[switch]$MultiSelect)
	
	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Drawing

	$form = New-Object System.Windows.Forms.Form 
	$form.Text = $BoxText
	$form.Size = New-Object System.Drawing.Size(300,(200+$yscale)) 
	$form.StartPosition = "CenterScreen"

	$OKButton = New-Object System.Windows.Forms.Button
	$OKButton.Location = New-Object System.Drawing.Point(75,(120+$yscale))
	$OKButton.Size = New-Object System.Drawing.Size(75,23)
	$OKButton.Text = "OK"
	$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
	$form.AcceptButton = $OKButton
	$form.Controls.Add($OKButton)

	$CancelButton = New-Object System.Windows.Forms.Button
	$CancelButton.Location = New-Object System.Drawing.Point(150,(120+$yscale))
	$CancelButton.Size = New-Object System.Drawing.Size(75,23)
	$CancelButton.Text = "Cancel"
	$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
	$form.CancelButton = $CancelButton
	$form.Controls.Add($CancelButton)

	$label = New-Object System.Windows.Forms.Label
	$label.Location = New-Object System.Drawing.Point(10,20) 
	$label.Size = New-Object System.Drawing.Size(280,20) 
	$label.Text = ($BoxText + ":")
	$form.Controls.Add($label) 

	$listBox = New-Object System.Windows.Forms.ListBox 
	$listBox.Location = New-Object System.Drawing.Point(10,40) 
	$listBox.Size = New-Object System.Drawing.Size(260,20) 
	$listBox.Height = (80 + $yscale)
	
	if ($MultiSelect)
	{
		$listBox.SelectionMode = "MultiExtended"
	}
	
	foreach ($Item in $List)
	{
		[void] $listBox.Items.Add($Item)
	}

	$form.Controls.Add($listBox) 

	$form.Topmost = $True

	$result = $form.ShowDialog()

	if ($result -eq [System.Windows.Forms.DialogResult]::OK)
	{
		$x = $listBox.SelectedItems
		return $x
	}
}
