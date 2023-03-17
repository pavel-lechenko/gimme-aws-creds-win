$Global:ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$PythonDownloadUrl = 'https://www.python.org/ftp/python/3.9.13/python-3.9.13-embed-amd64.zip'
$PipDownloadUrl = 'https://bootstrap.pypa.io/get-pip.py'

try {

  if ($PSVersionTable.Platform -eq 'Unix') {
    throw 'This script can run on Windows only. Sorry :('
  }

  if (Get-Variable -Name psISE -ErrorAction:SilentlyContinue) {
    $ThisScriptPath = $psise.CurrentFile.FullPath
  }
  else {
    $ThisScriptPath = $script:MyInvocation.MyCommand.Path
  }
  $HomeDirectory = Split-Path (Split-Path $ThisScriptPath -Parent) -Parent

  Set-Location $HomeDirectory

  $PythonInstallDirectory = [System.IO.Directory]::CreateDirectory("$HomeDirectory\python").FullName
  $PythonDownloadTempFilename = [System.IO.Path]::GetTempFileName() + '.zip'

  Write-Host "Downloading Python 3.9 from $PythonDownloadUrl"
  Invoke-WebRequest -Uri $PythonDownloadUrl -OutFile $PythonDownloadTempFilename -UseBasicParsing
  Write-Host "Installing Python 3.9 to $PythonInstallDirectory"
  Expand-Archive -Path $PythonDownloadTempFilename -DestinationPath $PythonInstallDirectory -Force

  @"
python39.zip
.
Lib
..
"$HomeDirectory"
import site
"@ | Out-File "$PythonInstallDirectory\python39._pth" -Encoding ascii -Force

  Write-Host "Downloading pip from $PipDownloadUrl"
  $PipDownloadTempFilename = [System.IO.Path]::GetTempFileName() + '.py'
  Invoke-WebRequest -Uri $PipDownloadUrl -OutFile $PipDownloadTempFilename -UseBasicParsing

  $env:PYTHONUSERBASE = $PythonInstallDirectory
  $env:Path = "$PythonInstallDirectory\Scripts;$PythonInstallDirectory;$env:Path"

  Write-Host 'Installing pip'
  & "$PythonInstallDirectory\python.exe" $PipDownloadTempFilename
  if ($LASTEXITCODE -ne 0) {
    throw "Failed with exit code $LASTEXITCODE"
  }
  Write-Host 'Installing requirements for gimme-aws-creds'
  & "$PythonInstallDirectory\Scripts\pip.exe" install -r requirements.txt
  if ($LASTEXITCODE -ne 0) {
    throw "Failed with exit code $LASTEXITCODE"
  }
  Write-Host
  Write-Host 'gimme-aws-creds installed successfully. Now please run `.\bin\Set-GimmeAwsCredsProfile.ps1` to configure it.'
}
catch {
  if ($_.Exception.WasThrownFromThrowStatement) {
    $Message = 'ERROR: ' + $_.Exception.Message
  }
  else {
    $Message = 'ERROR: ' + $_.Exception.Message + "`nStackTrace: " + $_.ScriptStackTrace
  }
  $fc = [System.Console]::ForegroundColor
  $bc = [System.Console]::BackgroundColor
  $nl = [System.Console]::Error.NewLine
  [System.Console]::Error.NewLine = "`n"
  [System.Console]::ForegroundColor = [System.ConsoleColor]::Red
  [System.Console]::BackgroundColor = [System.ConsoleColor]::Black
  [System.Console]::Error.WriteLine($Message)
  [System.Console]::BackgroundColor = $bc
  [System.Console]::ForegroundColor = $fc
  [System.Console]::Error.NewLine = $nl
}
finally {
  if (Test-Path $PythonDownloadTempFilename) {
    Remove-Item $PythonDownloadTempFilename -Force
  }
  if (Test-Path $PipDownloadTempFilename) {
    Remove-Item $PipDownloadTempFilename -Force
  }
}
