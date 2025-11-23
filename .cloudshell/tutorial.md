# GpuBudget GCP Setup

Welcome to the GpuBudget automatic setup!

## Quick Start

Run this command in the terminal to complete setup:

```bash
gpubudget
```

**That's it!** The script will:
- ✓ Detect your GCP projects with GPU instances
- ✓ Create a monitoring service account
- ✓ Register credentials with GpuBudget automatically

## What happens next?

The setup script will:

1. Fetch your authentication token securely
2. Scan your GCP projects for GPU instances
3. Create a service account with viewer permissions
4. Send credentials back to GpuBudget

## Need help?

If you see any errors, please check:
- Your token hasn't expired (valid for 1 hour)
- You have the necessary permissions in your GCP project
- Your internet connection is stable

Visit [GpuBudget Support](https://gpubudget.com/support) for assistance.
