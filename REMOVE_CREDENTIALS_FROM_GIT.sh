#!/bin/bash
#
# Remove terraform.tfvars from git history
# This script removes the credentials file from ALL git commits
#
# WARNING: This rewrites git history. After running this:
# - Everyone needs to re-clone the repository
# - Any existing branches/PRs need to be rebased
# - GitHub will need to be force-pushed (use with caution in teams)

set -e

PROJECT_ROOT=$(pwd)
BACKUP_DIR="${PROJECT_ROOT}/.git/history-backup-$(date +%s)"

echo "🔐 Git History Credential Removal Script"
echo "========================================"
echo ""
echo "This will PERMANENTLY remove terraform/terraform.tfvars from git history."
echo ""
echo "⚠️  WARNING:"
echo "   - This rewrites git history"
echo "   - All collaborators must re-clone after this"
echo "   - Existing branches/PRs may break"
echo ""
read -p "Type 'REMOVE_CREDENTIALS' to continue: " confirm

if [ "$confirm" != "REMOVE_CREDENTIALS" ]; then
    echo "❌ Cancelled"
    exit 1
fi

echo ""
echo "✓ Creating backup of .git directory: $BACKUP_DIR"
cp -r "$PROJECT_ROOT/.git" "$BACKUP_DIR"
echo "✓ Backup created (keep safe in case of issues!)"
echo ""

echo "🔄 Removing terraform/terraform.tfvars from all commits..."
git filter-branch --tree-filter 'rm -f terraform/terraform.tfvars' -- --all

echo ""
echo "✓ File removed from history"
echo ""

echo "🧹 Cleaning up git cache..."
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo ""
echo "✅ Git history cleaned!"
echo ""
echo "📋 Next steps:"
echo "1. Force-push to remote (CAREFUL with teams!):"
echo "   git push origin --force --all"
echo "   git push origin --force --tags"
echo ""
echo "2. Notify team to re-clone the repository"
echo ""
echo "3. Verify the file was removed:"
echo "   git log --all --full-history -- terraform/terraform.tfvars"
echo "   (Should return nothing)"
echo ""
echo "4. Verify terraform.tfvars is NOT in current directory:"
echo "   ls -la terraform/terraform.tfvars (should NOT exist)"
