#!/bin/bash

# Initialize and update each submodule
git submodule update --init --recursive

# Loop through each submodule
git submodule foreach 'git checkout master; git pull origin master'
