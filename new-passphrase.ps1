function New-PassPhrase
{param([switch]$IncludeSecureString)
	$rand = new-object System.Random
	$conjunction = "the","my","we","our","and","but","+"
	$punctuation = "~","!","@","#","%","*","&"
	$words = import-csv  $env:toolBoxXML + "\etc\dict.csv"
	$word1 = (Get-Culture).TextInfo.ToTitleCase(($words[$rand.Next(0,$words.Count)]).Word)
	$con = (Get-Culture).TextInfo.ToTitleCase($conjunction[$rand.Next(0,$conjunction.Count)])
	$word2 = (Get-Culture).TextInfo.ToTitleCase(($words[$rand.Next(0,$words.Count)]).Word)
	$punc = ($punctuation[$rand.Next(0,$punctuation.Count)])
	$pwd = $word1 + $con + $word2 + $rand.Next(0,100).tostring() + $punc
	[pscustomobject]@{"PlainText"=$pwd;"SecureStringObject"=(ConvertTo-SecureString -String $pwd -AsPlainText -Force)}
}
