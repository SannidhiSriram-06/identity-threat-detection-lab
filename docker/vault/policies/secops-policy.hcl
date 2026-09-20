# SecOps Policy for Just-In-Time AWS Credentials
path "aws/creds/secops-jit-role" {
  capabilities = ["read"]
}

# Allow token lookup & renewal
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
