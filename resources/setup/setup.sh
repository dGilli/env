#!/usr/bin/env bash

repo="https://github.com/dGilli/env"
projects="$HOME"/Projects/

cmd_exists() {
    command -v "$1" &> /dev/null
}

if [ "Darwin" == "$(uname -s)" ]; then
    if ! cmd_exists brew; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    install_git() { brew install git; }
else
    sudo apt -y update
    install_git() { sudo apt -y install git; }
fi

if ! cmd_exists git; then
    install_git
fi

if [ ! -d "$projects" ]; then
    mkdir "$projects"
fi

git clone "$repo" "$projects"env

pushd "$projects" || exit
./run "$@"
popd || exit

