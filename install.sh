#!/bin/bash

# jq is needed by the settings.json filter and the status line
if ! command -v jq &> /dev/null; then
    echo "jq not found, installing..."
    if command -v brew &> /dev/null; then
        brew install jq
    else
        sudo apt install -y jq
    fi
else
    echo "jq is already installed. Skipping..."
fi

# Strip machine-local keys (autoMode, survey state) from settings.json on commit.
# required=true makes git refuse to commit if the filter is ever missing.
cd "$(dirname "$0")"
git config filter.claude-settings.clean "jq 'del(.autoMode, .feedbackSurveyState)'"
git config filter.claude-settings.smudge cat
git config filter.claude-settings.required true

echo "Setup completed successfully!"
