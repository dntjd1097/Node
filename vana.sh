#!/bin/bash

install_dependencies() {
    sudo apt update && sudo apt install software-properties-common -y 
	sudo apt-get install expect -y
	sudo add-apt-repository ppa:deadsnakes/ppa
	sudo apt update
	sudo apt install python3.11 python3.11-venv python3.11-dev -y
	python3.11 --version
	curl -sSL https://install.python-poetry.org | python3 -
	poetry --version
	
	# PATH 설정이 없을 경우에만 추가
	if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' $HOME/.bashrc; then
		echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc
	fi
	source $HOME/.bashrc
	poetry --version
	
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

	# NVM 설정이 없을 경우에만 추가
	if ! grep -q 'export NVM_DIR="$HOME/.nvm"' $HOME/.bashrc; then
		echo 'export NVM_DIR="$HOME/.nvm"' >> $HOME/.bashrc
		echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> $HOME/.bashrc
		echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> $HOME/.bashrc
	fi

	source $HOME/.bashrc
	nvm install --lts
	node -v
	npm -v
    echo "Dependencies installed."
}
set_env(){
	source $HOME/.bashrc
}

create_wallet_config() {
    # 기본값 설정
    WALLET_NAME=${VANA_WALLET_NAME:-"default"}
    HOTKEY_NAME=${VANA_HOTKEY_NAME:-"default"}
    WALLET_PASSWORD=${VANA_WALLET_PASSWORD:-"your_default_password"}
    # keygen.sh를 위한 추가 기본값
    VALIDATOR_NAME=${VANA_VALIDATOR_NAME:-"Vana DLP Validator"}
    VALIDATOR_EMAIL=${VANA_VALIDATOR_EMAIL:-"validator@example.com"}
    VALIDATOR_KEY_EXPIRY=${VANA_KEY_EXPIRY:-"0"}
    
    # .walletaccount 파일에 저장
    if [ ! -f ~/.walletaccount ]; then
        cat > ~/.walletaccount << EOL
export VANA_WALLET_NAME="${WALLET_NAME}"
export VANA_HOTKEY_NAME="${HOTKEY_NAME}"
export VANA_WALLET_PASSWORD="${WALLET_PASSWORD}"
export VANA_VALIDATOR_NAME="${VALIDATOR_NAME}"
export VANA_VALIDATOR_EMAIL="${VALIDATOR_EMAIL}"
export VANA_KEY_EXPIRY="${VALIDATOR_KEY_EXPIRY}"
EOL
        if ! grep -q "source ~/.walletaccount" ~/.profile; then
            echo 'source ~/.walletaccount' >> ~/.profile
        fi
        source ~/.walletaccount
    fi
}

download_and_setup() {
    cd $HOME
    apt install jq -y
    apt install git -y
    apt install python3-pip -y
    install_dependencies
    git clone https://github.com/vana-com/vana-dlp-chatgpt.git
    TARGET_DIR="$HOME/vana-dlp-chatgpt"
    cd "$TARGET_DIR"
    poetry install
    pip install vana -y
    
    create_wallet_config
    
    # 자동으로 입력 제공
    expect << EOF
    spawn ./vanacli wallet create --wallet.name $VANA_WALLET_NAME --wallet.hotkey $VANA_HOTKEY_NAME
    expect "Specify password for key encryption:"
    send "$VANA_WALLET_PASSWORD\r"
	expect "Retype your password:"
	send "$VANA_WALLET_PASSWORD\r"
    expect eof
EOF
}


export_private_key() {
	set_env
    cd "$HOME/vana-dlp-chatgpt"
    ./vanacli wallet export_private_key
}

setup_dlp_smart_contracts(){
	set_env
    cd "$HOME/vana-dlp-chatgpt"
	
	# expect를 사용하여 keygen.sh 실행 시 환경변수에서 값을 가져와 사용
	expect << EOF
    spawn ./keygen.sh
    expect "Enter your name"
    send "${VANA_VALIDATOR_NAME}\r"
    expect "Enter your email"
    send "${VANA_VALIDATOR_EMAIL}\r"
    expect "Enter key expiration in days"
    send "${VANA_KEY_EXPIRY}\r"
    expect eof
EOF
	
	cd $HOME
	rm -rf vana-dlp-smart-contracts
	git clone https://github.com/Josephtran102/vana-dlp-smart-contracts
	cd "$HOME/vana-dlp-smart-contracts"
	npm install -g yarn
	yarn --version
	yarn install
	cp .env.example .env
	cd "$HOME/vana-dlp-smart-contracts"
	echo "+++++++++++++++++"
	
	# Check if environment variables exist, if not prompt for input
	WALLET_ADDRESS=${VANA_WALLET_ADDRESS:-$(read -p "wallet address (0x...): " addr && echo $addr)}
	PRIVATE_KEY=${VANA_PRIVATE_KEY:-$(read -p "wallet private key (0x...): " key && echo $key)}
	DLP_NAME=${VANA_DLP_NAME:-$(read -p "DLP_NAME: " name && echo $name)}
	DLP_TOKEN_NAME=${VANA_DLP_TOKEN_NAME:-$(read -p "DLP_TOKEN_NAME: " token_name && echo $token_name)}
	DLP_TOKEN_SYMBOL=${VANA_DLP_TOKEN_SYMBOL:-$(read -p "DLP_TOKEN_SYMBOL: " symbol && echo $symbol)}
	
	# Save to ~/.walletaccount if not already saved
	if [ ! -f ~/.walletaccount ]; then
		cat > ~/.walletaccount << EOL
export VANA_WALLET_ADDRESS="${WALLET_ADDRESS}"
export VANA_PRIVATE_KEY="${PRIVATE_KEY}"
export VANA_DLP_NAME="${DLP_NAME}"
export VANA_DLP_TOKEN_NAME="${DLP_TOKEN_NAME}"
export VANA_DLP_TOKEN_SYMBOL="${DLP_TOKEN_SYMBOL}"
EOL
		# Add source line to .profile if not already there
		if ! grep -q "source ~/.walletaccount" ~/.profile; then
			echo 'source ~/.walletaccount' >> ~/.profile
		fi
		source ~/.walletaccount
	fi
	
	sed -i "s/^DEPLOYER_PRIVATE_KEY=0xef.*/DEPLOYER_PRIVATE_KEY=${PRIVATE_KEY}/" .env
	sed -i "s/^OWNER_ADDRESS=0x7B.*/OWNER_ADDRESS=${WALLET_ADDRESS}/" .env
	sed -i "s/^DLP_NAME=J.*/DLP_NAME=${DLP_NAME}/" .env
	sed -i "s/^DLP_TOKEN_NAME=J.*/DLP_TOKEN_NAME=${DLP_TOKEN_NAME}/" .env
	sed -i "s/^DLP_TOKEN_SYMBOL=J.*/DLP_TOKEN_SYMBOL=${DLP_TOKEN_SYMBOL}/" .env
	npx hardhat deploy --network moksha --tags DLPDeploy
}

verifyF() {
	set_env
	cd "$HOME/vana-dlp-smart-contracts"
	read -p "DLP_TOKEN_MOKSHA_CONTRACT: " token_contract
	read -p "DLP_MOKSHA_CONTRACT: " pool_contract
	npx hardhat verify --network moksha ${pool_contract}
	npx hardhat verify --network moksha ${token_contract} "${DLP_TOKEN_NAME}" ${DLP_TOKEN_SYMBOL} ${ip_address}
}




run(){
	set_env
	cd "$HOME/vana-dlp-chatgpt"
	public_key=$(cat /root/vana-dlp-chatgpt/public_key_base64.asc)
	
	# Check if environment variables exist, if not prompt for input
	TOKEN_CONTRACT=${VANA_TOKEN_CONTRACT:-$(read -p "DLP_TOKEN_MOKSHA_CONTRACT: " token && echo $token)}
	POOL_CONTRACT=${VANA_POOL_CONTRACT:-$(read -p "DLP_MOKSHA_CONTRACT: " pool && echo $pool)}
	API_KEY=${OPENAI_API_KEY:-$(read -p "OPENAI_API_KEY: " api && echo $api)}
	
	# Save to ~/.walletaccount if not already saved
	if [ ! -f ~/.walletaccount ]; then
		cat > ~/.walletaccount << EOL
export VANA_TOKEN_CONTRACT="${TOKEN_CONTRACT}"
export VANA_POOL_CONTRACT="${POOL_CONTRACT}"
export OPENAI_API_KEY="${API_KEY}"
EOL
		if ! grep -q "source ~/.walletaccount" ~/.profile; then
			echo 'source ~/.walletaccount' >> ~/.profile
		fi
		source ~/.walletaccount
	fi
	
	cat <<EOF > .env
# The network to use, currently Vana Moksha testnet
OD_CHAIN_NETWORK=moksha
OD_CHAIN_NETWORK_ENDPOINT=https://rpc.moksha.vana.org

# Optional: OpenAI API key for additional data quality check
OPENAI_API_KEY="${api}"

# Optional: Your own DLP smart contract address once deployed to the network, useful for local testing

DLP_MOKSHA_CONTRACT=${pool_contract}
# Optional: Your own DLP token contract address once deployed to the network, useful for local testing

DLP_TOKEN_MOKSHA_CONTRACT=${token_contract}

# The private key for the DLP, follow "Generate validator encryption keys" section in the README
PRIVATE_FILE_ENCRYPTION_PUBLIC_KEY_BASE64="${public_key}"
EOF
	
	./vanacli dlp register_validator --stake_amount 10
	read -p "Hot key Address: " hot_address
	./vanacli dlp approve_validator --validator_address=${hot_address}
	poetry run python -m chatgpt.nodes.validator
}

service(){
		cat <<EOF > /etc/systemd/system/vana.service
[Unit]
Description=Vana Validator Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/vana-dlp-chatgpt
ExecStart=/root/.local/bin/poetry run python -m chatgpt.nodes.validator
Restart=on-failure
RestartSec=10
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/root/vana-dlp-chatgpt/myenv/bin
Environment=PYTHONPATH=/root/vana-dlp-chatgpt

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload && \
sudo systemctl enable vana.service && \
sudo systemctl restart vana.service && \
sudo systemctl status vana.service
}

log(){
	sudo journalctl -u vana.service -f
}


main_menu() {
    while true; do
        echo "1. Install"
        echo "2. export wallet"
        echo "3. setup dlp smart contracts"
        echo "4. verify"
		echo "5. run"
        echo "6. service"
		echo "7. log"
		echo "8. exit"

        read -p "Enter choice (1-5): " choice

        case $choice in
            1)
                download_and_setup
                ;;
            2)
                export_private_key
                ;;
            3)
                setup_dlp_smart_contracts
                ;;
            4)
                verifyF
                ;;
			5)
				run
				;;
            6)
                service
                ;;
			7)
				log
				;;
			8)
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
