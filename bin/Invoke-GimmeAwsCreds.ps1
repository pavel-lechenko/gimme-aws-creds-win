[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [String]
  $AWSProfile = $env:AWS_PROFILE
)

$Global:ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

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
  $PythonDir = [System.IO.Path]::GetFullPath("$HomeDirectory\python")
  $TokenFilePath = "$HOME\.aws\tokens\$AWSProfile.json.token"

  if (-not (Test-Path "$PythonDir\Scripts\pip.exe")) {
    throw 'gimme-aws-creds not properly installed. Please run `.\bin\Install-GimmeAwsCreds.ps1` to install it.'
  }

  if (Test-Path $TokenFilePath) {
    try {
      $TokenData = Get-Content $TokenFilePath | ConvertFrom-Json
      if ([bool]$TokenData.credentials.expiration) {
        if ([datetime]$TokenData.credentials.expiration -le [datetime]::Now.AddSeconds(-15)) {
          # Cached token expires in 15 seconds
          Remove-Item $TokenFilePath -Force | Out-Null
        }
      }
      else {
        # Cached token is not parsed successfully
        Remove-Item $TokenFilePath -Force | Out-Null
      }
    }
    catch {
      # Cached token is not parsed successfully
      Remove-Item $TokenFilePath -Force | Out-Null
    }
  }

  if (-not (Test-Path $TokenFilePath)) {
    [System.IO.Directory]::CreateDirectory((Split-Path $TokenFilePath -Parent)) | Out-Null

    if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
      # We are running "as Administrator"

      $env:PYTHONUSERBASE = $PythonDir
      $env:Path = "$PythonDir\Scripts;$PythonDir;$env:Path"

      try {
        $OutputGimmeAwsCreds = (& "$PythonDir\python.exe" bin\gimme-aws-creds --profile $AWSProfile --output json)
        if ($LASTEXITCODE -eq 0) {
          if (($OutputGimmeAwsCredsParsed = $OutputGimmeAwsCreds | ConvertFrom-Json) -and ($OutputGimmeAwsCredsParsed -is [Array])) {
            $i = 0
            $PromptMessage = "Please choose desired role:`n" +
          (($OutputGimmeAwsCredsParsed | ForEach-Object { '[' + ($i++) + '] ' + $_.role.name }) -join "`n") + "`n"
            do {
              $RoleId = Read-Host -Prompt $PromptMessage
            }
            until ( ($RoleId -match '^\d+$') -and ([int]$RoleId -lt $OutputGimmeAwsCredsParsed.Count)  )
            $OutputGimmeAwsCreds = $OutputGimmeAwsCredsParsed[$RoleId] | ConvertTo-Json -Depth 10 -Compress
          }
          $OutputGimmeAwsCreds | Out-File $TokenFilePath -Force -Encoding ascii
        }
        else {
          throw ("Error happened while running 'gimme-aws-creds --profile $AWSProfile': " + $OutputGimmeAwsCreds)
        }
      }
      catch {
        throw ("Error happened while running 'gimme-aws-creds --profile $AWSProfile': " + $OutputGimmeAwsCreds)
      }

    }
    else {
      # We are not running "as Administrator" - so relaunch as administrator and wait
      $RunParams = @{
        FilePath     = (Get-Command $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' })).Source
        Verb         = 'RunAs'
        ArgumentList = @(
          # '-NoExit' # For debug
          '-NoProfile'
          '-ExecutionPolicy'
          'Bypass'
          '-Command'
          $ThisScriptPath
          $AWSProfile
        )
      }
      Start-Process @RunParams -Wait
    }
  }
  if (Test-Path $TokenFilePath) {
    if (($TokenData = (Get-Content $TokenFilePath | ConvertFrom-Json)) -and
      [bool]$TokenData.credentials.expiration -and ([datetime]$TokenData.credentials.expiration -gt [datetime]::UtcNow)) {

      if (Test-Path Env:\AWS_DATA_PATH) {
        # We are running under AWS CLI
        @{
          Version         = 1
          AccessKeyId     = $TokenData.credentials.aws_access_key_id
          SecretAccessKey = $TokenData.credentials.aws_secret_access_key
          SessionToken    = $TokenData.credentials.aws_session_token
          Expiration      = $TokenData.credentials.expiration
        } | ConvertTo-Json
      }
      else {
        # We are running as a script
        $env:AWS_ACCESS_KEY_ID = $TokenData.credentials.aws_access_key_id
        $env:AWS_SECRET_ACCESS_KEY = $TokenData.credentials.aws_secret_access_key
        $env:AWS_SESSION_TOKEN = $TokenData.credentials.aws_session_token
      }
    }
  }

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
  Read-Host 'Press <ENTER> to continue' | Out-Null
}
