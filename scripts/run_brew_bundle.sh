#!/bin/bash

EXTRA_CASKS=${1:-false}
MAS_APPS=${2:-false}

export HOMEBREW_EXTRA_CASKS=$EXTRA_CASKS
export HOMEBREW_MAS_APPS=$MAS_APPS

cd && brew bundle
