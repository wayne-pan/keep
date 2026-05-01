#!/usr/bin/env bash
# safety-guard.sh — warns on destructive commands before execution.
# Installed as PreToolUse hook for Bash tool in settings.json.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Strip heredoc content to avoid false positives on env dump patterns
CMD_STRIPPED=$(echo "$CMD" | sed '/<<.*$/,/^\s*[A-Z]\{1,20\}$/d' 2>/dev/null || echo "$CMD")

# Destructive patterns to block
DESTRUCTIVE_PATTERNS=(
  # Filesystem
  "rm -rf /"
  "rm -rf /*"
  "rm -rf ~"
  "rm -rf ~/*"
  "dd if="
  "mkfs."
  "> /dev/sd"
  "chmod -R 777 /"
  "chown -R"
  ":(){:|:&};:"
  # Git
  "git push --force"
  "git push -f "
  "git reset --hard"
  "git clean -f"
  # SQL
  "DROP TABLE"
  "DROP DATABASE"
  "TRUNCATE TABLE"
  "DELETE FROM"

  # ── AWS (aws cli) ──
  "aws s3 rb s3://"
  "aws s3 rm s3:// --recursive"
  "aws s3api delete-bucket"
  "aws ec2 terminate-instances"
  "aws ec2 stop-instances"
  "aws rds delete-db-instance"
  "aws rds stop-db-instance"
  "aws lambda delete-function"
  "aws iam delete-user"
  "aws iam delete-role"
  "aws iam delete-policy"
  "aws iam detach-role-policy"
  "aws cloudformation delete-stack"
  "aws eks delete-cluster"
  "aws ecs delete-cluster"
  "aws ecs delete-service"
  "aws ec2 delete-security-group"
  "aws ec2 delete-vpc"
  "aws ec2 delete-subnet"
  "aws ec2 delete-internet-gateway"
  "aws ec2 revoke-security-group-ingress"
  "aws ec2 revoke-security-group-egress"
  "aws dynamodb delete-table"
  "aws sns delete-topic"
  "aws sqs delete-queue"
  "aws secretsmanager delete-secret"
  "aws kms schedule-key-deletion"
  "aws kms disable-key"
  "aws cloudfront delete-distribution"
  "aws route53 delete-hosted-zone"
  "aws elasticache delete-replication-group"
  "aws elasticache delete-cache-cluster"
  "aws elbv2 delete-load-balancer"
  "aws autoscaling delete-auto-scaling-group"
  "aws ssm delete-parameter --name"

  # ── Aliyun / Alibaba Cloud (aliyun cli) ──
  "aliyun ecs DeleteInstance"
  "aliyun ecs StopInstance"
  "aliyun ecs DeleteSecurityGroup"
  "aliyun ecs DeleteVpc"
  "aliyun ecs DeleteVSwitch"
  "aliyun ecs DeleteRoute"
  "aliyun rds DeleteDBInstance"
  "aliyun rds StopDBInstance"
  "aliyun oss rm oss://"
  "aliyun oss rm -r oss://"
  "aliyun oss del-bucket"
  "aliyun slb DeleteLoadBalancer"
  "aliyun cs DELETE"
  "aliyun kms ScheduleKeyDeletion"
  "aliyun kms DeleteKey"
  "aliyun ram DeleteUser"
  "aliyun ram DeleteRole"
  "aliyun ram DeletePolicy"
  "aliyun ram DetachPolicyFromUser"
  "aliyun ram DetachPolicyFromRole"
  "aliyun nas DeleteFileSystem"
  "aliyun nas DeleteMountTarget"
  "aliyun redis DeleteInstance"
  "aliyun dcdn DeleteDcdnIpaDomain"
  "aliyun dns DeleteDomain"
  "aliyun kms DeleteSecret"
  "aliyun slb DeleteServerCertificate"
  "aliyun ecs RevokeSecurityGroup"
  "aliyun ecs DeleteDisk"
  "aliyun ecs DeleteSnapshot"

  # ── GCP (gcloud) ──
  "gcloud compute instances delete"
  "gcloud compute instances stop"
  "gcloud compute firewall-rules delete"
  "gcloud compute networks delete"
  "gcloud compute subnets delete"
  "gcloud compute routers delete"
  "gcloud sql instances delete"
  "gcloud sql databases delete"
  "gcloud storage rm --recursive gs://"
  "gcloud storage buckets delete gs://"
  "gcloud iam service-accounts delete"
  "gcloud projects delete"
  "gcloud container clusters delete"
  "gcloud pubsub topics delete"
  "gcloud pubsub subscriptions delete"
  "gcloud functions delete"
  "gcloud run services delete"
  "gcloud kms keyring delete"
  "gcloud kms keys destroy"
  "gcloud dns managed-zones delete"
  "gcloud redis instances delete"
  "gcloud bigtable instances delete"
  "gcloud dataproc clusters delete"
  "gcloud compute disks delete"
  "gcloud compute snapshots delete"
  "gcloud compute target-pools delete"
  "gcloud compute backend-services delete"
  "gcloud app versions delete"
  "gcloud deployment-manager deployments delete"
  "gcloud source repos delete"
  "gcloud builds triggers delete"

  # ── Azure (az) ──
  "az vm delete"
  "az vm deallocate"
  "az group delete"
  "az storage account delete"
  "az storage blob delete-batch"
  "az storage container delete"
  "az sql server delete"
  "az sql db delete"
  "az functionapp delete"
  "az aks delete"
  "az acr delete"
  "az network vnet delete"
  "az network nsg delete"
  "az keyvault delete"
  "az keyvault secret delete"
  "az cosmosdb delete"
  "az redis delete"
  "az servicebus namespace delete"
  "az monitor app-insights component delete"

  # ── Terraform ──
  "terraform destroy"

  # ── Docker / Kubernetes ──
  "docker rm -f"
  "docker volume rm"
  "docker network rm"
  "kubectl delete namespace"
  "kubectl delete --all"
  "kubectl delete deployment"
  "kubectl delete service"
  "kubectl delete pv"
  "kubectl delete pvc"
  "kubectl delete clusterrole"
  "kubectl delete clusterrolebinding"
  "helm uninstall"
  "helm delete"
)

# Secret leak patterns to block (env dumps, credential reads, cloud creds)
SECRET_PATTERNS=(
  "printenv"
  "declare -xp"
  "export -p"
  "cat .env"
  "cat \"\$HOME/.env"
  "cat ~/.env"
  "curl -v"
  "cat .ssh/id_rsa"
  "cat .ssh/id_ed25519"
  "cat ~/.ssh/id_rsa"
  "cat ~/.ssh/id_ed25519"
  "cat \"\$HOME/.ssh/id_rsa"
  "cat \"\$HOME/.ssh/id_ed25519"
  # AWS credentials
  "cat ~/.aws/credentials"
  "cat .aws/credentials"
  "aws configure get"
  "cat \"\$HOME/.aws/credentials"
  # GCP credentials
  "cat ~/.config/gcloud/credentials.db"
  "gcloud auth print-access-token"
  "gcloud auth application-default print-access-token"
  # Aliyun credentials
  "cat ~/.aliyun/config.json"
  "cat .aliyun/config.json"
  # Azure credentials
  "cat ~/.azure/accessTokens.json"
  "cat ~/.azure/azureProfile.json"
  "az account get-access-token"
  # Cloud keys/secrets in env
  "AWS_SECRET_ACCESS_KEY"
  "AWS_ACCESS_KEY_ID"
  "AZURE_CLIENT_SECRET"
  "GOOGLE_APPLICATION_CREDENTIALS"
  "ALIBABA_CLOUD_ACCESS_KEY_SECRET"
)

for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
  if echo "$CMD" | grep -Fqi "$pattern"; then
    jq -n --arg cmd "$CMD" --arg pattern "$pattern" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("SAFETY: Blocked destructive command matching [" + $pattern + "]. Command: " + $cmd)
      }
    }'
    exit 0
  fi
done

# Block secret leak commands (use stripped version to skip heredocs)
for pattern in "${SECRET_PATTERNS[@]}"; do
  if echo "$CMD_STRIPPED" | grep -Fqi "$pattern"; then
    # Skip false positives for .env.example and similar safe files
    if echo "$CMD_STRIPPED" | grep -Fqi ".env.example"; then
      continue
    fi
    jq -n --arg cmd "$CMD" --arg pattern "$pattern" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("SECRETS: Blocked command that may leak secrets [" + $pattern + "]. Command: " + $cmd)
      }
    }'
    # Set cooperative stop event for sprint coordination
    SESSION_ID=$(cat .sprint/SESSION_ID 2>/dev/null || echo "default")
    echo "CRITICAL: secret leak blocked" > "/tmp/keep-stop-${SESSION_ID}" 2>/dev/null
    exit 0
  fi
done

# Warn patterns (allow but add warning)
WARN_PATTERNS=(
  "rm -rf"
  "git push --force"
  "git push -f"
  "git checkout -- ."
  "git restore ."
  "npm publish"
  "docker system prune"
  "pip uninstall"
  # Cloud: potentially costly/dangerous read-write ops
  "aws s3 cp"
  "aws s3 sync"
  "aws s3 rm s3://"
  "aws ec2 run-instances"
  "aws rds create-db-instance"
  "aws lambda update-function-code"
  "aws lambda invoke"
  "aws ssm send-command"
  "aws cloudformation deploy"
  "gcloud compute instances create"
  "gcloud sql instances create"
  "gcloud storage cp"
  "gcloud functions deploy"
  "gcloud run deploy"
  "gcloud app deploy"
  "gcloud deployment-manager deployments create"
  "az vm create"
  "az group create"
  "az acr build"
  "az webapp deploy"
  "aliyun ecs CreateInstance"
  "aliyun ecs StartInstance"
  "aliyun oss cp"
  "aliyun oss sync"
  # Terraform
  "terraform apply"
  "terraform taint"
  "terraform import"
  # K8s
  "kubectl apply"
  "kubectl rollout restart"
  "kubectl scale"
  "helm install"
  "helm upgrade"
)

for pattern in "${WARN_PATTERNS[@]}"; do
  if echo "$CMD" | grep -Fqi "$pattern"; then
    # Pass through but with a note — let Claude Code's native permission handle it
    echo "[safety] WARNING: Potentially destructive command detected. Please confirm." >&2
    exit 0
  fi
done

# ── TIER-2 Annotation (advisory, non-blocking) ──
# Annotates write/deploy commands as Tier-2 for Claude's awareness.
# Does NOT block — safety-guard.sh enforcement is the actual guard.
TIER2_PATTERNS=(
  "git commit" "git push" "git merge" "git rebase" "git checkout -b"
  "npm install" "pip install" "apt-get install" "brew install"
  "docker push" "kubectl apply" "terraform apply"
  "npm publish" "docker deploy"
)
for pattern in "${TIER2_PATTERNS[@]}"; do
  if echo "$CMD" | grep -Fqi "$pattern"; then
    echo "[safety-tier] TIER-2: command requires permission — $pattern" >&2
    break
  fi
done

# Unwrapped external content detection
# Warn if heredoc/command contains external-looking content without nonce markers
if echo "$CMD" | grep -qiE '(curl|wget|fetch|WebFetch|webReader)' && \
   ! echo "$CMD" | grep -q 'BEGIN EXTERNAL'; then
  echo "[safety] NOTE: External content should be nonce-wrapped. Use: nonce-wrap" >&2
fi

# Safe — pass through
exit 0
