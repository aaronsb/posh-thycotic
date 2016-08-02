function install-toolbox
{
	param($computer)
	$config = [xml](gc ($env:toolBoxXML + "\toolbox.xml"))
	#probably do some sort of git pull thinger in here to install the whole shebang on another computer.
	#yep, I haven't written that yet.
}