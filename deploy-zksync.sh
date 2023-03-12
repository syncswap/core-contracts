#!/usr/bin/env bash

function bashcolor {
    if [ $2 ]; then
        echo -e "\e[$1;$2m"
    else
        echo -e "\e[$1m"
    fi
}

function bashcolorend {
    echo -e "\e[m"
}

skippedCompile=0

if [[ "$1" != "--skipCompile" ]]; then
    # Compile zkSync artifacts.
    echo "  "
    echo "  //////////////////////////////////////////////////"
    echo "  $(bashcolor 1 32)(1/2) Running$(bashcolorend) - Compile zkSync artifacts"
    echo "  //////////////////////////////////////////////////"
    echo "  "

    if [ -d "./artifacts-zk" ]; then
        rm -rf ./artifacts-zk
    fi
    if [ -d "./cache-zk" ]; then
        rm -rf ./cache-zk
    fi

    yarn hardhat compile --network zkTestnet
  else
    skippedCompile=1
    echo "  "
    echo "  //////////////////////////////////////////////////"
    echo "  $(bashcolor 1 32)(1/2) Skipped$(bashcolorend) - Compile zkSync artifacts"
    echo "  //////////////////////////////////////////////////"
    echo "  "
fi

if [[ ! -d "./artifacts-zk" || ! -d "./cache-zk" ]]; then
    echo "  "
    echo "  //////////////////////////////////////////////////"
    echo "  $(bashcolor 1 33)(1/2) Aborted$(bashcolorend) - Compile zkSync artifacts"
    echo "  Not found zkSync artifacts, please compile it first."
    echo "  //////////////////////////////////////////////////"
    echo "  "
    exit 1
fi

# Deploy into zkSync
# yarn hardhat deploy-zksync --script {name}.ts
echo "  "
echo "  //////////////////////////////////////////////////"
echo "  $(bashcolor 1 32)(2/2) Running$(bashcolorend) - Deploy zkSync artifacts"
echo "  //////////////////////////////////////////////////"

script=""
if [[ "$skippedCompile" == 0 && "$1" ]]; then
    script=$1
  else
    if [[ "$skippedCompile" == 1 && "$2" ]]; then
      script=$2
    fi
fi

if [[ ! -z "$script" ]]; then
    echo "  Use deploy script: $script"
    echo "  "
    yarn hardhat deploy-zksync --script "$script".ts --network zkTestnet
  else
    echo "  Use all deploy scripts."
    echo "  "
    yarn hardhat deploy-zksync --network zkTestnet
fi

echo "  "
echo "  //////////////////////////////////////////////////"
echo "  $(bashcolor 1 32)(2/2) Success$(bashcolorend) - zkSync artifacts deployed successfully."
echo "  //////////////////////////////////////////////////"
echo "  "