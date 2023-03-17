[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [String]
  $AWSProfile = $env:AWS_PROFILE
)

$Global:ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function ConvertFrom-Ini {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Object]
    $InputObject,
    [Switch]
    $AsHashtable
  )
  begin {
    $CommentLineHeader = '# '
    $EmptySection = ' '
    $ErrorActionPreference = 'Stop'
    $OutputHT = @{
      $EmptySection = @{}
    }
    $CurrentSection = $OutputHT[$EmptySection]
    $LineNum = 0
  }
  process {
    try {
            ($InputObject.ToString() -split "[\r\n]+").ForEach( {
          $line = $_
          switch -Regex ($line) {
            '^\s*$' {
              # Skip empty lines
              Break
            }
            '^(\s+)?[;#]' {
              $CurrentSection["$CommentLineHeader{0:000000}" -f $LineNum] = $line
              Break
            }
            '^(\s+)?\[(?<Section>.*)\](\s+)?$' {
              $Section = $Matches.Section.Trim()
              if ($Section -notin $OutputHT.Keys) {
                $OutputHT[$Section] = @{}
              }
              $CurrentSection = $OutputHT[$Section]
              Break
            }
            '^(?<Name>.*)\=(?<Value>.*)$' {
              $k = $Matches.Name.Trim()
              $v = $Matches.Value.Trim()
              if ($CurrentSection) {
                $CurrentSection[$k] = $v
              }
              Break
            }
            default {
              'Unexpected line: {0}' -f $_ | Write-Warning
            }
          }
          $LineNum++
        })
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
  end {
    if ($AsHashtable) {
      [hashtable]$OutputHT
    }
    else {
      [PSCustomObject]$OutputHT
    }
  }
}

function ConvertTo-Ini {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [psobject]
    $InputObject
  )
  begin {
    $CommentLineHeader = '# '
    $EmptySection = ' '
    $ErrorActionPreference = 'Stop'
    $OutputSB = [System.Text.StringBuilder]::new()
  }
  process {
    try {
      if ($InputObject) {

                ([pscustomobject]$InputObject).PSObject.Properties.Where( {
            $_.MemberType -eq 'NoteProperty'
          }) | Sort-Object -Property Name | ForEach-Object {
          if ($_.Name.ToString() -ne $EmptySection) {
            if ($OutputSB.Length -gt 0) {
              [void]$OutputSB.AppendLine()
            }
            [void]$OutputSB.AppendLine("[$($_.Name)]")
          }
                    ([pscustomobject]$_.Value).PSObject.Properties.Where( {
              $_.MemberType -eq 'NoteProperty'
            }) | Sort-Object -Property Name | ForEach-Object {
            if ($_.Name.ToString().StartsWith($CommentLineHeader)) {
              [void]$OutputSB.AppendLine($_.Value)
            }
            else {
              if ($_.Value.ToString()) {
                [void]$OutputSB.AppendLine('{0} = {1}' -f @($_.Name, $_.Value.ToString()))
              }
            }
          }
        }
      }
    }
    catch {
      $PSCmdlet.ThrowTerminatingError($_)
    }
  }
  end {
    $OutputSB.ToString()
  }
}

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
  if (Test-Path "$PythonDir\Scripts\pip.exe") {

    $env:PYTHONUSERBASE = $PythonDir
    $env:Path = "$PythonDir\Scripts;$PythonDir;$env:Path"

    Write-Host "Configuring gimme-aws-creds profile '$AWSProfile'"
    & "$PythonDir\python.exe" bin\gimme-aws-creds --profile $AWSProfile --configure

    if ($LASTEXITCODE -eq 0) {

      # Clean-up profiles - remove empty values
      $GACConfigFile = [System.IO.Path]::Combine($HOME, '.okta_aws_login_config')
      if (Test-Path $GACConfigFile) {
        $GACConfig = Get-Content $GACConfigFile -Raw | ConvertFrom-Ini -AsHashtable
        if ($GACConfig[$AWSProfile] -is [hashtable]) {
          $GACConfig | ConvertTo-Ini | Out-File $GACConfigFile -Encoding ascii -Force
        }
        else {
          throw "Profile $AWSProfile not found in config file '$GACConfigFile'. Maybe something wrong with installation?"
        }
      }
      else {
        throw "gimme-aws-creds config file '$GACConfigFile' not found. Maybe something wrong with installation?"
      }

      $AWSCfgFile = [System.IO.FileInfo]([System.IO.Path]::Combine($HOME, '.aws', 'config'))

      if (-not (Test-Path $AWSCfgFile.Directory.FullName -PathType Container)) {
        New-Item $AWSCfgFile.Directory.FullName -ItemType Directory -Force | Out-Null
      }
      $awscfg = if (Test-Path $AWSCfgFile.FullName) { Get-Content $AWSCfgFile.FullName -Raw | ConvertFrom-Ini -AsHashtable }
      else { @{} }
      $PSInterpreter = if ($PSVersionTable.PSEdition -eq 'Core') { (Get-Command pwsh).Source }
      else { (Get-Command powershell).Source }

      $AWSProfileSectionName = if ($AWSProfile -eq 'default') { 'default' }
      else { "profile $AWSProfile" }

      if (!($awscfg.ContainsKey($AWSProfileSectionName))) {
        $awscfg[$AWSProfileSectionName] = @{}
      }

      $awscfg[$AWSProfileSectionName]['credential_process'] = "$PSInterpreter -ExecutionPolicy Bypass -NoLogo -NonInteractive -Command `"& '$HomeDirectory\bin\Invoke-GimmeAwsCreds.ps1' -AWSProfile $AWSProfile`""
      $awscfg | ConvertTo-Ini | Out-File $AWSCfgFile.FullName -Encoding ascii -Force
      Write-Host "`nAWS cli configured. You can run i.e. ``aws sts get-caller-identity --profile $AWSProfile`` or using environment variable ```$env:AWS_PROFILE='$AWSProfile'; aws sts get-caller-identity`` to verify the credentials"
    }
    else {
      throw "Failed with exit code $LASTEXITCODE"
    }
  }
  else {
    throw 'gimme-aws-creds not properly installed. Please run `.\bin\Install-GimmeAwsCreds.ps1` to install it.'
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
}
