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