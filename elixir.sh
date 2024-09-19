#!/bin/bash
SCRIPT_PATH="$HOME/ElixirV3.sh"

function ensure_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo "[*]I can't install the docker, so I install it."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce
        echo "Docker installed"
    else
        echo "Docker installed"
    fi
}


function install_validator_node() {
    ensure_docker_installed

    read -p "Node IP : " ip_address
    read -p "Node Name: " validator_name
    read -p "wallet_address: " beneficiary_address
    read -p "private_key: " private_key

    cat <<EOF > validator.env
ENV=testnet-3

STRATEGY_EXECUTOR_IP_ADDRESS=${ip_address}
STRATEGY_EXECUTOR_DISPLAY_NAME=${validator_name}
STRATEGY_EXECUTOR_BENEFICIARY=${beneficiary_address}
SIGNER_PRIVATE_KEY=${private_key}
EOF

    echo "[+] Setting validator.env"

    docker pull elixirprotocol/validator:v3


	docker run -it -d \
	--env-file validator.env \
	--name elixir \
	elixirprotocol/validator:v3

}


function view_docker_logs() {
    docker logs -f elixir
}

function display_main_menu() {
    clear
    echo "===================== Elixir V3 Bob ========================="
    echo "1. Install Elixir V3"
    echo "2. Log Docker"
    read -p "Choice 1-2 : " OPTION

    case $OPTION in
    1) install_validator_node ;;
    2) view_docker_logs ;;
    *) echo "invaild choice." ;;
    esac
}

display_main_menu
