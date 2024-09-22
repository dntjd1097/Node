#!/bin/bash

install_dependencies() {
    for cmd in git make; do
        if ! command -v $cmd &> /dev/null; then
            echo "$cmd is not installed, installing..."

            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                sudo apt update && sudo apt install -y $cmd
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                brew install $cmd
            else
                echo "Unsupported OS, please install $cmd manually."
                exit 1
            fi
        fi
    done
    echo "Dependencies installed."
}

check_go_version() {
    if command -v go >/dev/null 2>&1; then
        CURRENT_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        MINIMUM_GO_VERSION="1.22.2"

        if [ "$(printf '%s\n' "$MINIMUM_GO_VERSION" "$CURRENT_GO_VERSION" | sort -V | head -n1)" = "$MINIMUM_GO_VERSION" ]; then
            echo "Go version is sufficient: $CURRENT_GO_VERSION"
        else
            echo "Current Go version ($CURRENT_GO_VERSION) is lower than required, installing the latest Go."
            install_go
        fi
    else
        echo "Go not detected, installing Go."
        install_go
    fi
}

install_go() {
    wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    source ~/.bashrc
    echo "Go installed, version: $(go version)"
}

download_and_setup() {
    apt install jq -y
	check_go_version
	install_dependencies
    wget https://github.com/hemilabs/heminetwork/releases/download/v0.4.3/heminetwork_v0.4.3_linux_amd64.tar.gz -O heminetwork_v0.4.3_linux_amd64.tar.gz

    TARGET_DIR="$HOME/heminetwork"
    mkdir -p "$TARGET_DIR"

    tar -xvf heminetwork_v0.4.3_linux_amd64.tar.gz -C "$TARGET_DIR"

    mv "$TARGET_DIR/heminetwork_v0.4.3_linux_amd64/"* "$TARGET_DIR/"
    rmdir "$TARGET_DIR/heminetwork_v0.4.3_linux_amd64"

    cd "$TARGET_DIR"
    ./keygen -secp256k1 -json -net="testnet" > ~/popm-address.json

    if [[ ! -f ~/popm-address.json ]]; then
        echo "Address file not found, please generate it first."
        exit 1
    fi

    cd "$HOME/heminetwork"
    cat ~/popm-address.json
}

view_wallet() {
    cd "$HOME/heminetwork"
    cat ~/popm-address.json
}

run_miner() {
    cd "$HOME/heminetwork"
    cat ~/popm-address.json

    POPM_BTC_PRIVKEY=$(jq -r '.private_key' ~/popm-address.json)
    read -p "Enter sats/vB value: " POPM_STATIC_FEE

    export POPM_BTC_PRIVKEY=$POPM_BTC_PRIVKEY
    export POPM_STATIC_FEE=$POPM_STATIC_FEE
    export POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public
    nohup ./popmd > popmd.log 2>&1 &
}

restart_miner(){
    pkill popmd
    cd "$HOME/heminetwork"
    cat ~/popm-address.json

    POPM_BTC_PRIVKEY=$(jq -r '.private_key' ~/popm-address.json)
    read -p "Enter sats/vB value: " POPM_STATIC_FEE

    export POPM_BTC_PRIVKEY=$POPM_BTC_PRIVKEY
    export POPM_STATIC_FEE=$POPM_STATIC_FEE
    export POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public
    nohup ./popmd > popmd.log 2>&1 &
}

view_logs() {
    cd "$HOME/heminetwork"
    tail -f popmd.log
}


main_menu() {
    while true; do
        echo "1. Install"
        echo "2. View wallet"
        echo "3. run miner"
        echo "4. View logs"
	echo "5. restart miner"
        echo "6. Exit"

        read -p "Enter choice (1-5): " choice

        case $choice in
            1)
                download_and_setup
                ;;
            2)
                view_wallet
                ;;
            3)
                run_miner
                ;;
            4)
                view_logs
                ;;
	    5)
     		restart_miner
       		;;
            6)
                echo "Exiting script."
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}

echo "Preparing to launch main menu..."
main_menu
