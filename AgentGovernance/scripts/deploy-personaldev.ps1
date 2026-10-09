<#
.SYNOPSIS
Deploys Agent Governance managed solutions to one or more Power Platform environments.

.DESCRIPTION
PersonalDev:
  Imports AgentGovernanceCore + AgentGovernancePersonalDev.

Default:
  Imports AgentGovernanceCore + AgentGovernanceDefault.

The script optionally self-elevates the currently authenticated Power Platform
administrator before importing the solutions.

.EXAMPLE
.\deploy-agent-governance.ps1 `
    -Mode PersonalDev `
    -Environment @(
        "11111111-1111-1111-1111-111111111111",
        "22222222-2222-2222-2222-222222222222"
    )

.EXAMPLE
.\deploy-agent-governance.ps1 `
    -Mode Default `
    -Environment "https://org12345678.crm4.dynamics.com"

.EXAMPLE
.\deploy-agent-governance.ps1 `
    -Mode PersonalDev `
    -Environment "11111111-1111-1111-1111-111111111111" `
    -SkipSelfElevate
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("PersonalDev", "Default")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string[]]$Environment,

    [string]$SolutionDirectory = (
        Join-Path (Split-Path $PSScriptRoot -Parent) "solutions"
    ),

    [switch]$SkipSelfElevate,

    [int]$SelfElevateWaitSeconds = 10
)

$ErrorActionPreference = "Stop"

$coreZip = Join-Path $SolutionDirectory "AgentGovernanceCore_managed.zip"

switch ($Mode) {
    "PersonalDev" {
        $featureZip = Join-Path $SolutionDirectory "AgentGovernancePersonalDev_managed.zip"
        $featureName = "AgentGovernancePersonalDev"
    }

    "Default" {
        $featureZip = Join-Path $SolutionDirectory "AgentGovernanceDefault_managed.zip"
        $featureName = "AgentGovernanceDefault"
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Pac {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & pac @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "pac failed with exit code $LASTEXITCODE. Command: pac $($Arguments -join ' ')"
    }
}

if (-not (Test-CommandExists -Name "pac")) {
    throw "Microsoft Power Platform CLI (pac) was not found in PATH."
}

if (-not (Test-Path -LiteralPath $coreZip)) {
    throw "Core solution ZIP not found: $coreZip"
}

if (-not (Test-Path -LiteralPath $featureZip)) {
    throw "$featureName solution ZIP not found: $featureZip"
}

Write-Host ""
Write-Host "Agent Governance Deployment"
Write-Host "Mode:               $Mode"
Write-Host "Core solution:      $coreZip"
Write-Host "Feature solution:   $featureZip"
Write-Host "Target environments: $($Environment.Count)"
Write-Host ""

$results = @()

foreach ($target in $Environment) {
    $adminResult = if ($SkipSelfElevate) { "SKIPPED" } else { "PENDING" }
    $coreResult = "PENDING"
    $featureResult = "PENDING"
    $errorMessage = $null

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "Environment: $target"
    Write-Host "Mode:        $Mode"
    Write-Host "============================================================"

    try {
        Write-Host "[0/3] Checking environment access..."

        Invoke-Pac -Arguments @(
            "env",
            "who",
            "--environment",
            $target
        )

        if (-not $SkipSelfElevate) {
            Write-Host "[1/3] Self-elevating current administrator..."

            Invoke-Pac -Arguments @(
                "admin",
                "self-elevate",
                "--environment",
                $target
            )

            $adminResult = "OK"

            if ($SelfElevateWaitSeconds -gt 0) {
                Write-Host "Waiting $SelfElevateWaitSeconds seconds for Dataverse role propagation..."
                Start-Sleep -Seconds $SelfElevateWaitSeconds
            }
        }
        else {
            Write-Host "[1/3] Self-elevation skipped."
        }

        Write-Host "[2/3] Importing AgentGovernanceCore..."

        Invoke-Pac -Arguments @(
            "solution",
            "import",
            "--environment",
            $target,
            "--path",
            $coreZip,
            "--publish-changes"
        )

        $coreResult = "OK"

        Write-Host "[3/3] Importing $featureName and activating plug-in steps..."

        Invoke-Pac -Arguments @(
            "solution",
            "import",
            "--environment",
            $target,
            "--path",
            $featureZip,
            "--publish-changes",
            "--activate-plugins"
        )

        $featureResult = "OK"

        Write-Host ""
        Write-Host "SUCCESS: Agent Governance deployed to $target"
    }
    catch {
        $errorMessage = $_.Exception.Message

        if ($adminResult -eq "PENDING") {
            $adminResult = "FAILED"
            $coreResult = "SKIPPED"
            $featureResult = "SKIPPED"
        }
        elseif ($coreResult -eq "PENDING") {
            $coreResult = "FAILED"
            $featureResult = "SKIPPED"
        }
        elseif ($featureResult -eq "PENDING") {
            $featureResult = "FAILED"
        }

        Write-Host ""
        Write-Host "FAILED: $target"
        Write-Host $errorMessage
    }

    $results += [PSCustomObject]@{
        Environment = $target
        Mode        = $Mode
        Admin       = $adminResult
        Core        = $coreResult
        Feature     = $featureResult
        Error       = $errorMessage
    }
}

Write-Host ""
Write-Host "================ DEPLOYMENT SUMMARY ================"

$results |
    Format-Table Environment, Mode, Admin, Core, Feature -AutoSize

$failed = @($results | Where-Object {
    $_.Core -eq "FAILED" -or
    $_.Feature -eq "FAILED" -or
    $_.Admin -eq "FAILED"
})

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed deployments: $($failed.Count)"

    $failed |
        Select-Object Environment, Error |
        Format-List

    exit 1
}

Write-Host ""
Write-Host "All deployments completed successfully."
exit 0
