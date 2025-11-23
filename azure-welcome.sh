#!/bin/bash
# Azure Cloud Shell Welcome Script
# Add this to your ~/.bashrc to auto-display on shell start

# Only show once per session
if [ -z "$GPUBUDGET_WELCOME_SHOWN" ]; then
    export GPUBUDGET_WELCOME_SHOWN=1

    # Check if we're in the azure repo directory
    if [ -f "./azure-cloudshell.sh" ]; then
        cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║          🚀 GpuBudget Azure Auto-Setup                        ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

To complete setup, run:

    ./setup-azure.sh

The script will automatically:
  ✓ Deploy Azure managed identity
  ✓ Assign required permissions
  ✓ Register with GpuBudget

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
    fi
fi
