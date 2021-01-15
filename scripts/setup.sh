#! /bin/bash
set -euo pipefail

info() {
  printf "\r\033[00;35m$1\033[0m\n"
}

success() {
  printf "\r\033[00;32m$1\033[0m\n"
}

fail() {
  printf "\r\033[0;31m$1\033[0m\n"
}

divider() {
  printf "\r\033[0;1m========================================================================\033[0m\n"
}

pause_for_confirmation() {
  read -rsp $'Press any key to continue (ctrl-c to quit):\n' -n1 key
}

# Set up an interrupt handler so we can exit gracefully
interrupt_count=0
interrupt_handler() {
  ((interrupt_count += 1))

  echo ""
  if [[ $interrupt_count -eq 1 ]]; then
    fail "Really quit? Hit ctrl-c again to confirm."
  else
    echo "Goodbye!"
    exit
  fi
}
trap interrupt_handler SIGINT SIGTERM

# This setup script does all the magic.

# Check for required tools
declare -a req_tools=("terraform" "sed" "curl" "jq")
for tool in "${req_tools[@]}"; do
  if ! command -v "$tool" > /dev/null; then
    fail "It looks like '${tool}' is not installed; please install it and run this setup script again."
    exit 1
  fi
done

# Set up some variables we'll need
HOST="${1:-app.terraform.io}"
MAIN_TF=$(dirname ${BASH_SOURCE[0]})/../main.tf

# Check that we've already authenticated via Terraform in the static credentials
# file.  Note that if you configure your token via a credentials helper or any
# other method besides the static file, this script will not take that in to
# account - but we do this to avoid embedding a Go binary in this simple script
# and you hopefully do not need this Getting Started project if you're using one
# already!
CREDENTIALS_FILE="$HOME/.terraform.d/credentials.tfrc.json"
TOKEN=$(jq -j --arg h "$HOST" '.credentials[$h].token' $CREDENTIALS_FILE)
if [[ ! -f $CREDENTIALS_FILE || $TOKEN == null ]]; then
  fail "We couldn't find a token in the Terraform credentials file at $CREDENTIALS_FILE."
  fail "Please run 'terraform login', then run this setup script again."
  exit 1
fi

# Check that this is your first time running this script. If not, we'll reset
# all local state and restart from scratch!
if [[ $(git diff --stat) != '' ]]; then
  echo "It looks like you've run this script before! Before continuing, we'll need to
  reset everything to its original state, including any changes you've made to main.tf."
  echo
  pause_for_confirmation

  git checkout HEAD main.tf
  rm -rf .terraform
  rm -f *.lock.hcl
fi

echo
printf "\r\033[00;35;1m
--------------------------------------------------------------------------
                                         -
Welcome to Terraform Cloud               -----                           -
                                         ---------                      --
                                         ---------  -                -----
                                          ---------  ------        -------
                                            -------  ---------  ----------
                                               ----  ---------- ----------
                                                 --  ---------- ----------
                                                  -  ---------- -------
                                                     ---  ----- ---
                                                     --------   -
                                                     ----------
                                                     ----------
                                                      ---------
                                                          -----
                                                              -

-------------------------------------------------------------------------\033[0m"
echo
echo
echo "Terraform Cloud offers secure, easy-to-use remote state management and allows
you to run Terraform remotely in a controlled environment. Terraform Cloud runs
can be performed on demand or triggered automatically by various events."
echo
info "This script will set up everything you need to get started. You'll be
applying some example infrastructure - for free - in less than a minute."
echo
info "First, we'll do some setup and configure Terraform to use Terraform Cloud."
echo
pause_for_confirmation

# Create a Terraform Cloud organization
echo
echo "Creating an organization and workspace..."
sleep 1
setup() {
  curl https://$HOST/api/getting-started/setup \
    --request POST \
    --silent \
    --header "Content-Type: application/vnd.api+json" \
    --header "Authorization: Bearer $TOKEN" \
    --header "User-Agent: tfc-getting-started" \
    --data @- << REQUEST_BODY
{
	"workflow": "remote-operations"
}
REQUEST_BODY
}

response=$(setup)

if [[ $(echo $response | jq -r '.errors') != null ]]; then
  fail "An unknown error occurred: ${response}"
  exit 1
fi

api_error=$(echo $response | jq -r '.error')
if [[ $api_error != null ]]; then
  fail "\n${api_error}"
  exit 1
fi

# TODO: If there's an active trial, we should just retrieve that and configure
# it instead (especially if it has no state yet)
info=$(echo $response | jq -r '.info')
if [[ $info != null ]]; then
  info "\n${info}"
  exit 0
fi

organization_name=$(echo $response | jq -r '.data."organization-name"')
workspace_name=$(echo $response | jq -r '.data."workspace-name"')

echo
echo "Writing remote backend configuration to main.tf..."
sleep 1

# We don't sed -i because MacOS's sed has problems with it.
TEMP=$(mktemp)
cat $MAIN_TF |
  # add config for the hostname if necessary
  if [[ "$HOST" != "app.terraform.io" ]]; then sed "5a\\
\    hostname = \"$HOST\"
    "; else cat; fi |
  # replace the organization and workspace names
  sed "s/{{ORGANIZATION_NAME}}/${organization_name}/" |
  sed "s/{{WORKSPACE_NAME}}/${workspace_name}/" \
    > $TEMP
mv $TEMP $MAIN_TF

echo
divider
echo
success "Ready to go; the example configuration is set up to use Terraform Cloud!"
echo
echo "An example workspace named '${workspace_name}' was created for you."
echo "You can view this workspace in the Terraform Cloud UI here:"
echo "https://$HOST/app/${organization_name}/workspaces/${workspace_name}"
echo
info "Next, we'll run 'terraform init' to initialize the backend and providers:"
echo
echo "$ terraform init"
echo
pause_for_confirmation

echo
terraform init
echo
divider
echo
info "Now it’s time for 'terraform plan', to see what changes Terraform will perform:"
echo
echo "$ terraform plan"
echo
pause_for_confirmation

echo
terraform plan
echo
divider
echo
success "The plan is complete!"
echo
echo "This plan was initiated from your local machine, but executed within
Terraform Cloud!"
echo
echo "Terraform Cloud runs Terraform on disposable virtual machines in
its own cloud infrastructure. This 'remote execution' helps provide consistency
and visibility for critical provisioning operations. It also enables notifications,
version control integration, and powerful features like Sentinel policy enforcement
and cost estimation (shown in the output above)."
echo
info "To actually make changes, we'll run 'terraform apply'. We'll also auto-approve
the result, since this is an example:"
echo
echo "$ terraform apply -auto-approve"
echo
pause_for_confirmation

echo
terraform apply -auto-approve

echo
divider
echo
success "You did it! You just provisioned infrastructure with Terraform Cloud!"
echo
info "The organization we created here has a 30-day free trial of the Team &
Governance tier features. After the trial ends, you'll be moved to the Free tier."
echo
echo "You now have:"
echo
echo "  * Workspaces for organizing your infrastructure. Terraform Cloud manages"
echo "    infrastructure collections with workspaces instead of directories. You"
echo "    can view your workspace here:"
echo "    https://$HOST/app/$organization_name/workspaces/$workspace_name"
echo "  * Remote state management, with the ability to share outputs across"
echo "    workspaces. We've set up state management for you in your current"
echo "    workspace, and you can reference state from other workspaces using"
echo "    the 'terraform_remote_state' data source."
echo "  * Much more!"
echo
info "To see the mock infrastructure you just provisioned and continue exploring
Terraform Cloud, visit:
https://$HOST/fake-web-services"
echo
exit 0
