#!/bin/bash

# exit on failure
set -e

# move to location of this script
base_dir="$( dirname "${BASH_SOURCE[0]}" )"
cd "$base_dir"

# auto-confirm opam prompts unless operating under cygwin
os=$(uname -s)
opam_exec="opam --yes"
if [ "${os:0:6}" == "CYGWIN" ]
then
   opam_exec="opam"
fi

# install project dependencies
$opam_exec install ./dometyl.opam --deps-only --with-doc

# install opam dev depenencies
$opam_exec install \
    merlin ocp-indent ocaml-lsp-server ocamlformat ocamlformat-rpc

# build dometyl
dune build
