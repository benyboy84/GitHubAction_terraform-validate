#!/bin/bash

echo "Terraform Validate | INFO     | Checking if Terraform files in $GITHUB_REPOSITORY are syntactically valid and internally consistent."

# Optional inputs

# Validate input path.
if [[ -n "$INPUT_PATH" ]]; then
    if [[ ! -d "$INPUT_PATH" ]]; then
        echo "Terraform Validate | ERROR    | Path does not exist: \"$INPUT_PATH\"."
        exit 1
    else
        cd "$INPUT_PATH"
    fi
fi

# Set workspace
TF_WORKSPACE="$INPUT_WORKSPACE"

# Detect terraform version
VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | grep 'Terraform v' | sed 's/Terraform v//')
if [[ -z $VERSION  ]]; then
    echo "Terraform Validate | ERROR    | Terraform not detected."
    exit 1
else
    echo "Terraform Validate | INFO     | Using terraform version $VERSION."
fi

# Initialize working directory containing Terraform configuration files.
INIT=$(terraform init -input=false -backend=false 2>&1)
if [[ ${?} -ne 0 ]]; then
    echo "Terraform Validate | ERROR    | Working directory not initialized."
    exit 1
fi

# Gather the output of `terraform validate`.
OUTPUT=$(terraform validate -no-color ${*} 2>&1)
EXITCODE=${?}

# Exit Code: 0
# Meaning: Terraform successfully validated.
# Actions: Exit.
if [[ $EXITCODE -eq 0 ]]; then
    echo "Terraform Validate | INFO     | Terraform files in $GITHUB_REPOSITORY are syntactically valid and internally consistent."
fi

# Exit Code: 1
# Meaning: Terraform validate failed or malformed Terraform CLI command.
# Actions: Build PR comment.
if [[ $EXITCODE -eq 1 ]]; then
    echo "Terraform Validate | ERROR    | Terraform validate failed or malformed Terraform CLI command."

     PR_COMMENT="### ${GITHUB_WORKFLOW} - Terraform validate Failed
<details><summary>Show Output</summary>
<p>
$OUTPUT
</p>
</details>"
fi

# Add comment if the action is call from a pull request.
#if [[ "$GITHUB_EVENT_NAME" != "push" && "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" && "$GITHUB_EVENT_NAME" != "pull_request_review_comment" && "$GITHUB_EVENT_NAME" != "pull_request_target" && "$GITHUB_EVENT_NAME" != "pull_request_review" ]]; then
if [[ "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" ]]; then
    echo "Terraform Format | WARNING  | $GITHUB_EVENT_NAME event does not relate to a pull request."
    echo "Terraform Format | INFO     | Terraform validate output"
    echo -e "$OUTPUT"
else
    if [[ -z GITHUB_TOKEN ]]; then
        echo "Terraform Validate | WARNING  | GITHUB_TOKEN not defined. Pull request is not possible without a GitHub token."
    else
        # Look for an existing validate PR comment and delete.
        echo "Terraform Validate | INFO     | Looking for an existing validate PR comment."
        ACCEPT_HEADER="Accept: application/vnd.github.v3+json"
        AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
        CONTENT_HEADER="Content-Type: application/json"
        if [[ "$GITHUB_EVENT_NAME" == "issue_comment" ]]; then
            PR_COMMENTS_URL=$(jq -r ".issue.comments_url" "$GITHUB_EVENT_PATH")
        else
            PR_COMMENTS_URL=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
        fi
        PR_COMMENT_URI=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")
        PR_COMMENT_ID=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq '.[] | select(.body|test ("### '"${GITHUB_WORKFLOW}"' - Terraform validate Failed")) | .id')
        if [ "$PR_COMMENT_ID" ]; then
            echo "Terraform Validate | INFO     | Found existing validate PR comment: $PR_COMMENT_ID. Deleting."
            PR_COMMENT_URL="$PR_COMMENT_URI/$PR_COMMENT_ID"
            {
                curl -sS -X DELETE -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URL" > /dev/null
            } ||
            {
                echo "Terraform Validate | ERROR    | Unable to delete existing validate failure comment in PR."
            }
        else
            echo "Terraform Validate | INFO     | No existing validate PR comment found."
        fi
        if [[ $EXITCODE -ne 0 ]]; then
            # Add validate failure comment to PR.
            PR_PAYLOAD=$(echo '{}' | jq --arg body "$PR_COMMENT" '.body = $body')
            echo "Terraform Validate | INFO     | Adding validate failure comment to PR."
            {
                curl -sS -X POST -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$PR_PAYLOAD" -L "$PR_COMMENTS_URL" > /dev/null
            } ||
            {
                echo "Terraform Validate | ERROR    | Unable to add validate failure comment in PR."
            }
        fi
    fi
fi
exit $EXITCODE