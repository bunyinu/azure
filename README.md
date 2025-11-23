# 🚀 GpuBudget Azure Auto-Setup

Welcome! You're one command away from connecting your Azure account to GpuBudget.

## Quick Setup

Run this command to complete the setup:

```bash
./setup-azure.sh
```

## What This Does

The setup script will automatically:

✅ Deploy an Azure managed identity to your subscription
✅ Assign the required permissions (Reader, Cost Management Reader)
✅ Register your Azure account with GpuBudget
✅ Enable GPU instance monitoring

## Requirements

- Azure subscription with active GPU instances
- Permissions to create managed identities
- Permissions to assign roles

## Manual Steps (If Needed)

If you prefer to run the setup manually:

1. **Make scripts executable:**
   ```bash
   chmod +x azure-cloudshell.sh
   ```

2. **Get your TOKEN_ID** from the Cloud Shell URL (after `#TOKEN_ID=`)

3. **Fetch your token:**
   ```bash
   curl -s "https://api.gpubudget.com/cloud-accounts/token/YOUR_TOKEN_ID"
   ```

4. **Run the setup:**
   ```bash
   export AUTH_TOKEN="your_token_here"
   export BACKEND_URL="https://api.gpubudget.com"
   ./azure-cloudshell.sh --auto-run true
   ```

## Need Help?

Visit [GpuBudget Support](https://gpubudget.com/support) or contact support@gpubudget.com

---

*Powered by GpuBudget - GPU Instance Management Made Simple*
