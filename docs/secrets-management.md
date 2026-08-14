# Secrets management

The `kubernetes/*/secret.yml` and `kubernetes/*/mongo-secret.yml` files in this
repo are **dev-only placeholders** (`changeme` values) for the local kind lab.
They must never hold real credentials.

## Production options

Pick one and apply it consistently; do not commit plaintext secrets:

### 1. Sealed Secrets (recommended for GitOps)

Encrypt secrets client-side with the cluster's public key, then commit only the
encrypted `SealedSecret` objects. The controller decrypts them in-cluster.

```sh
# install controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/controller.yaml

# seal a dev secret; output goes to git instead of the plaintext file
kubeseal --format yaml --namespace app1 \
  < kubernetes/app1-taskmanager/secret.yml \
  > kubernetes/app1-taskmanager/sealed-secret.yml
```

### 2. SOPS + age (no in-cluster component)

Encrypt the value files in place; decrypt happens in the deploy pipeline.

```sh
sops --encrypt --age "$(cat keys/age.pub)" \
  kubernetes/app1-taskmanager/secret.yml
# pipeline:
#   sops --decrypt kubernetes/app1-taskmanager/secret.yml | kubectl apply -f -
```

### 3. Vault

Store values in Vault and inject via the Vault Agent Injector sidecar, or fetch
into the deploy job with a short-lived token.

## App config after this change

`main.py` and `server.js` now **fail at startup** if `SECRET_KEY` /
`DATABASE_PASSWORD` / `JWT_SECRET` are unset, so a forgotten injection is loud
(container CrashLoopBackOff) instead of silently running with a guessable key.