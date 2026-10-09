# Agent Governance for Microsoft Copilot Studio

Custom Dataverse plug-in governance for Microsoft Copilot Studio environments.

This repository contains a reusable governance approach for controlling agent creation in Microsoft Power Platform / Copilot Studio.

## Goal

Two governance modes are supported.

### Personal Developer Environments

Normal Copilot Studio agents remain allowed.

GitHub Copilot Harness agents are blocked during creation when the Dataverse `bot` record contains:

```text
recognizer.$kind = CLICopilotRecognizer
```

### Default Environment

All new Copilot Studio agent creation is blocked by preventing `Create` operations on the Dataverse `bot` table.

---

## Architecture

The implementation uses one signed Dataverse plug-in assembly with two plug-in classes:

```text
AgentGovernance.dll
├── Plugins.BlockCopilotHarnessAgents
└── Plugins.BlockAllAgentCreation
```

Both rules are registered on:

```text
Message:          Create
Primary Entity:   bot
Stage:            PreValidation
Execution Mode:   Synchronous
Isolation Mode:   Sandbox
```

The deployment is split into three solutions:

```text
AgentGovernanceCore
├── AgentGovernance.dll
├── Plugins.BlockCopilotHarnessAgents
└── Plugins.BlockAllAgentCreation

AgentGovernancePersonalDev
└── Step: Block GitHub Copilot Harness - Create bot

AgentGovernanceDefault
└── Step: Block All Agent Creation - Create bot
```

This separation allows the same assembly to be reused while different environments receive different governance behavior.

---

## Repository Structure

```text
AgentGovernance/
├── src/
│   └── AgentGovernance/
│       ├── DefaultAgentBlock.cs
│       └── AgentGovernance.csproj
├── solutions/
│   ├── AgentGovernanceCore_managed.zip
│   ├── AgentGovernancePersonalDev_managed.zip
│   └── AgentGovernanceDefault_managed.zip
├── scripts/
│   └── deploy-agent-governance.ps1
└── README.md
```

---

## Prerequisites

The target environment must have Dataverse and Copilot Studio available.

Required tooling for scripted deployment:

- Microsoft Power Platform CLI (`pac`)
- Power Platform administrator account
- Permission to self-elevate in target environments
- Managed solution ZIP files
- Access to the target Power Platform tenant

Check Power Platform CLI:

```powershell
pac --version
```

Check access to an environment:

```powershell
pac env who --environment "<ENVIRONMENT-ID-OR-URL>"
```

---

## Deployment Model

### Personal Developer Environment

Import:

```text
1. AgentGovernanceCore_managed.zip
2. AgentGovernancePersonalDev_managed.zip
```

Expected behavior:

| Action | Result |
|---|---|
| Create normal Copilot Studio agent | Allowed |
| Create GitHub Copilot Harness agent | Blocked |

### Default Environment

Import:

```text
1. AgentGovernanceCore_managed.zip
2. AgentGovernanceDefault_managed.zip
```

Expected behavior:

| Action | Result |
|---|---|
| Create normal Copilot Studio agent | Blocked |
| Create GitHub Copilot Harness agent | Blocked |
| Create any new `bot` record through Copilot Studio | Blocked |

---

## Automated Deployment

Use the included PowerShell script:

```text
scripts/deploy-agent-governance.ps1
```

### Deploy to Personal Developer Environments

```powershell
.\scripts\deploy-agent-governance.ps1 `
    -Mode PersonalDev `
    -Environment @(
        "<ENVIRONMENT-ID-1>",
        "<ENVIRONMENT-ID-2>"
    )
```

### Deploy to Default Environment

```powershell
.\scripts\deploy-agent-governance.ps1 `
    -Mode Default `
    -Environment "<DEFAULT-ENVIRONMENT-ID>"
```

### Deployment Process

The script performs the following steps:

1. Checks that `pac` is installed.
2. Validates the required managed solution ZIP files.
3. Verifies access to the target environment.
4. Self-elevates the current administrator.
5. Imports `AgentGovernanceCore`.
6. Imports the environment-specific governance solution.
7. Activates included plug-in steps.
8. Continues with the next environment if one deployment fails.
9. Prints a deployment summary.

---

## Administrator Self-Elevation

New Personal Developer Environments may contain the administrator account without a Dataverse security role.

This can result in errors such as:

```text
The user has not been assigned any roles.
They need a role with the prvImportCustomization privilege.
```

For administrators with the required Power Platform tenant role, use:

```powershell
pac admin self-elevate `
    --environment "<ENVIRONMENT-ID>"
```

After self-elevation, the current administrator receives the required Dataverse administrative permissions.

A short delay before importing solutions can be useful:

```powershell
Start-Sleep -Seconds 10
```

Do not use `pac admin assign-user` as a workaround when the current account itself has no Dataverse security role, because the assignment operation can require Dataverse privileges that the account does not yet have.

---

## Manual Deployment Through Power Apps

For a small number of environments, deployment can be performed manually.

### Personal Developer Environment

1. Open `https://make.powerapps.com`
2. Select the target Personal Developer Environment.
3. Open **Solutions**.
4. Select **Import solution**.
5. Import:

```text
AgentGovernanceCore_managed.zip
```

6. Then import:

```text
AgentGovernancePersonalDev_managed.zip
```

7. Ensure included plug-in steps are enabled.
8. Complete the import.

Expected result:

```text
Normal Copilot Studio agents        Allowed
GitHub Copilot Harness agents       Blocked
```

### Default Environment

1. Open `https://make.powerapps.com`
2. Select the Default Environment.
3. Open **Solutions**.
4. Import:

```text
AgentGovernanceCore_managed.zip
```

5. Then import:

```text
AgentGovernanceDefault_managed.zip
```

6. Enable the included plug-in step.
7. Complete the import.

Expected result:

```text
All new agent creation              Blocked
```

---

## New Personal Developer Environments

When new users receive Personal Developer Environments, governance must also be deployed to those environments.

For every new Personal Developer Environment:

```text
1. Self-elevate the administrator
2. Import AgentGovernanceCore_managed.zip
3. Import AgentGovernancePersonalDev_managed.zip
4. Activate plug-in steps
5. Test normal agent creation
6. Test GitHub Copilot Harness creation
```

The automated deployment script is recommended when several new environments must be configured.

---

## Plug-in Behavior

### Plugins.BlockCopilotHarnessAgents

Runs only for:

```text
Message: Create
Table:   bot
```

The plug-in reads the `configuration` attribute of the Dataverse `bot` record.

The operation is blocked when the configuration contains:

```text
"$kind": "CLICopilotRecognizer"
```

Example user-facing error:

```text
GitHub Copilot Harness agents cannot be created in this environment.
```

Normal Copilot Studio agent creation continues to work.

---

### Plugins.BlockAllAgentCreation

Runs only for:

```text
Message: Create
Table:   bot
```

Every matching create operation is rejected.

Example user-facing error:

```text
Agent creation is not allowed in the Default environment.
Please use your Personal Developer Environment or the designated Copilot Studio Development environment.
```

This message should be adapted if the customer's environment model uses different terminology.

---

## Source Code

Example implementation:

```csharp
using Microsoft.Xrm.Sdk;
using System;
using System.Text.RegularExpressions;

namespace Plugins
{
    public class BlockCopilotHarnessAgents : IPlugin
    {
        private const string BotTableName = "bot";
        private const string ConfigurationColumnName = "configuration";

        public void Execute(IServiceProvider serviceProvider)
        {
            IPluginExecutionContext context =
                (IPluginExecutionContext)serviceProvider.GetService(
                    typeof(IPluginExecutionContext));

            ITracingService tracing =
                (ITracingService)serviceProvider.GetService(
                    typeof(ITracingService));

            if (!context.MessageName.Equals(
                    "Create",
                    StringComparison.OrdinalIgnoreCase) ||
                !context.PrimaryEntityName.Equals(
                    BotTableName,
                    StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            if (!context.InputParameters.Contains("Target"))
            {
                return;
            }

            Entity target = context.InputParameters["Target"] as Entity;

            if (target == null)
            {
                return;
            }

            string configuration =
                target.GetAttributeValue<string>(ConfigurationColumnName);

            if (string.IsNullOrWhiteSpace(configuration))
            {
                return;
            }

            bool isGitHubHarness = Regex.IsMatch(
                configuration,
                "\"\\$kind\"\\s*:\\s*\"CLICopilotRecognizer\"",
                RegexOptions.IgnoreCase
            );

            if (!isGitHubHarness)
            {
                return;
            }

            tracing.Trace("GitHub Copilot Harness agent detected.");

            throw new InvalidPluginExecutionException(
                "GitHub Copilot Harness agents cannot be created in this environment."
            );
        }
    }

    public class BlockAllAgentCreation : IPlugin
    {
        private const string BotTableName = "bot";

        public void Execute(IServiceProvider serviceProvider)
        {
            IPluginExecutionContext context =
                (IPluginExecutionContext)serviceProvider.GetService(
                    typeof(IPluginExecutionContext));

            ITracingService tracing =
                (ITracingService)serviceProvider.GetService(
                    typeof(ITracingService));

            if (!context.MessageName.Equals(
                    "Create",
                    StringComparison.OrdinalIgnoreCase) ||
                !context.PrimaryEntityName.Equals(
                    BotTableName,
                    StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            tracing.Trace(
                "Agent creation blocked by AgentGovernance."
            );

            throw new InvalidPluginExecutionException(
                "Agent creation is not allowed in the Default environment. Please use your Personal Developer Environment or the designated Copilot Studio Development environment."
            );
        }
    }
}
```

---

## Plug-in Registration

The relevant Dataverse plug-in steps are:

### Personal Developer

```text
Class:
Plugins.BlockCopilotHarnessAgents

Message:
Create

Primary Entity:
bot

Stage:
PreValidation

Mode:
Synchronous

Isolation:
Sandbox
```

### Default Environment

```text
Class:
Plugins.BlockAllAgentCreation

Message:
Create

Primary Entity:
bot

Stage:
PreValidation

Mode:
Synchronous

Isolation:
Sandbox
```

---

## Solution Structure

### AgentGovernanceCore

Contains:

```text
AgentGovernance.dll

Plugins.BlockCopilotHarnessAgents
Plugins.BlockAllAgentCreation
```

This solution contains the reusable plug-in assembly.

### AgentGovernancePersonalDev

Contains:

```text
SDK Message Processing Step

AgentGovernance - Block GitHub Copilot Harness - Create bot
```

### AgentGovernanceDefault

Contains:

```text
SDK Message Processing Step

AgentGovernance - Block All Agent Creation - Create bot
```

---

## Import Order

The order is important.

### Personal Developer Environments

```text
AgentGovernanceCore
        ↓
AgentGovernancePersonalDev
```

### Default Environment

```text
AgentGovernanceCore
        ↓
AgentGovernanceDefault
```

The environment-specific solution depends on the plug-in assembly contained in `AgentGovernanceCore`.

---

## Updating the Plug-in

When the plug-in code changes:

1. Update the source code.
2. Increment the assembly version where appropriate.
3. Rebuild the strongly signed `AgentGovernance.dll`.
4. Update the plug-in assembly in the development environment.
5. Verify both plug-in types.
6. Verify both plug-in steps.
7. Update solution versions.
8. Export new managed versions of:

```text
AgentGovernanceCore
AgentGovernancePersonalDev
AgentGovernanceDefault
```

9. Commit source-code changes.
10. Publish updated solution artifacts.
11. Deploy the updated solutions to target environments.

---

## Testing

### Personal Developer Environment

Test both scenarios.

#### Normal Copilot Studio Agent

Create a normal Copilot Studio agent.

Expected result:

```text
Creation succeeds.
```

#### GitHub Copilot Harness Agent

Attempt to create a GitHub Copilot Harness agent.

Expected result:

```text
GitHub Copilot Harness agents cannot be created in this environment.
```

---

### Default Environment

Attempt to create any new Copilot Studio agent.

Expected result:

```text
Agent creation is not allowed in the Default environment.
```

No new agent should be created.

---

## Security

Do not commit private signing material.

Never commit:

```text
*.pfx
*.snk
private keys
client secrets
access tokens
tenant credentials
environment credentials
```

The compiled signed DLL and managed solution ZIPs can be distributed without exposing the private signing key.

For production use, keep the signing key in an approved secured build environment or secret-management solution.

---

## Recommended .gitignore

```gitignore
# Signing keys
*.pfx
*.snk
*.key
*.pem

# Build output
bin/
obj/

# Visual Studio
.vs/
*.user
*.suo

# VS Code
.vscode/

# Secrets
.env
.env.*
*.secret
secrets.*

# Temporary files
*.tmp
*.log
```

---

## Multi-Client Use

The governance implementation is intended to be reusable across Microsoft Power Platform tenants.

The plug-in itself does not depend on:

- Tenant IDs
- Environment IDs
- User IDs
- Customer-specific Dataverse URLs
- Customer-specific administrator accounts

Before deploying to another customer, verify:

- Copilot Studio uses the Dataverse `bot` table.
- GitHub Copilot Harness agents still use `CLICopilotRecognizer`.
- The customer wants the same Personal Developer governance behavior.
- The customer wants agent creation blocked in the Default Environment.
- Error messages match the customer's terminology.
- Solution publisher and prefixes are customer-independent.
- The deployment account has sufficient Power Platform administration rights.

Avoid storing customer-specific environment IDs directly in the reusable repository.

Environment IDs should instead be supplied during deployment.

---

## Suggested Customer Deployment Structure

```text
Customer Tenant
│
├── Default Environment
│   ├── AgentGovernanceCore
│   └── AgentGovernanceDefault
│
├── Personal Developer Environment 1
│   ├── AgentGovernanceCore
│   └── AgentGovernancePersonalDev
│
├── Personal Developer Environment 2
│   ├── AgentGovernanceCore
│   └── AgentGovernancePersonalDev
│
└── Personal Developer Environment N
    ├── AgentGovernanceCore
    └── AgentGovernancePersonalDev
```

---

## Important Limitation

This is a custom Dataverse governance control.

It is not a Microsoft tenant setting specifically named:

```text
Disable GitHub Copilot Harness
```

The governance control works by synchronously rejecting the Dataverse `bot` creation operation.

Changes by Microsoft to any of the following should therefore be regression-tested:

- Copilot Studio persistence model
- Dataverse `bot` table behavior
- GitHub Copilot Harness configuration
- `CLICopilotRecognizer`
- Agent creation pipeline

After major Copilot Studio platform updates, test the governance controls in a non-production environment before relying on them for enforcement.

---

## Summary

```text
PERSONAL DEVELOPER ENVIRONMENT

Normal Copilot Studio Agent
        ↓
Allowed

GitHub Copilot Harness Agent
        ↓
Dataverse Create bot
        ↓
CLICopilotRecognizer detected
        ↓
Blocked


DEFAULT ENVIRONMENT

Any Agent
        ↓
Dataverse Create bot
        ↓
BlockAllAgentCreation
        ↓
Blocked
```

The result is a reusable governance layer that keeps Personal Developer Environments usable while preventing unwanted GitHub Copilot Harness agents and prevents agent creation entirely in the Default Environment.