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
    
    # VALIDATOR_NAME과 VALIDATOR_EMAIL을 처음 실행할 때 입력받기
    if [ -z "$VANA_VALIDATOR_NAME" ]; then
        read -p "Enter Validator Name: " VALIDATOR_NAME
    else
        VALIDATOR_NAME=$VANA_VALIDATOR_NAME
    fi

    if [ -z "$VANA_VALIDATOR_EMAIL" ]; then
        read -p "Enter Validator Email: " VALIDATOR_EMAIL
    else
        VALIDATOR_EMAIL=$VANA_VALIDATOR_EMAIL
    fi

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
    
    # wallet 설정
    VANA_WALLET_NAME="default"
    VANA_HOTKEY_NAME="default"
    
    # 기존 .walletaccount 파일에서 설정 로드
    source ~/.walletaccount 2>/dev/null || true
    
    # password가 없거나 비어있는 경우에만 입력 받기
    if [ -z "$VANA_WALLET_PASSWORD" ]; then
        echo -n "Enter wallet password: "
        read -s VANA_WALLET_PASSWORD
        echo  # 줄바꿈을 위해
        
        # password만 업데이트
        if [ -f ~/.walletaccount ]; then
            # password 라인만 추가/수정
            sed -i "/VANA_WALLET_PASSWORD/d" ~/.walletaccount
            echo "export VANA_WALLET_PASSWORD=\"${VANA_WALLET_PASSWORD}\"" >> ~/.walletaccount
        else
            # 파일이 없는 경우 새로 생성
            cat > ~/.walletaccount << EOL
export VANA_WALLET_NAME="${VANA_WALLET_NAME}"
export VANA_HOTKEY_NAME="${VANA_HOTKEY_NAME}"
export VANA_WALLET_PASSWORD="${VANA_WALLET_PASSWORD}"
EOL
        fi
        
        if ! grep -q "source ~/.walletaccount" ~/.profile; then
            echo 'source ~/.walletaccount' >> ~/.profile
        fi
        source ~/.walletaccount
    else
        echo "Wallet password already exists. Skipping password setup."
    fi
    
    # .vana/wallets/{WALLET_NAME} 디렉토리가 없는 경우에만 wallet 생성
    WALLET_DIR="$HOME/.vana/wallets/$VANA_WALLET_NAME"
    if [ ! -d "$WALLET_DIR" ]; then
        # 니모닉을 저장할 임시 파일
        TEMP_MNEMONIC=$(mktemp)
        
        expect << EOF | tee "$TEMP_MNEMONIC"
        spawn ./vanacli wallet create --wallet.name $VANA_WALLET_NAME --wallet.hotkey $VANA_HOTKEY_NAME
        expect "Your coldkey mnemonic phrase:"
        expect -re {│\s+([\w\s]+)\s+│}
        set coldkey_mnemonic \$expect_out(1,string)
        expect "Specify password for key encryption:"
        send "$VANA_WALLET_PASSWORD\r"
        expect "Retype your password:"
        send "$VANA_WALLET_PASSWORD\r"
        expect "Your hotkey mnemonic phrase:"
        expect -re {│\s+([\w\s]+)\s+│}
        set hotkey_mnemonic \$expect_out(1,string)
        expect eof
EOF
        
        # 니모닉 추출 및 저장 (ANSI 코드 제거)
        COLDKEY_MNEMONIC=$(grep -A 2 "Your coldkey mnemonic phrase:" "$TEMP_MNEMONIC" | tail -n 1 | sed 's/│//g' | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | xargs)
        HOTKEY_MNEMONIC=$(grep -A 2 "Your hotkey mnemonic phrase:" "$TEMP_MNEMONIC" | tail -n 1 | sed 's/│//g' | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | xargs)
        
        # .mnemonic 파일에 저장
        cat > ~/.mnemonic << EOL
COLDKEY_MNEMONIC="$COLDKEY_MNEMONIC"
HOTKEY_MNEMONIC="$HOTKEY_MNEMONIC"
EOL
        
        # 임시 파일 삭제
        rm "$TEMP_MNEMONIC"
        
        echo "Mnemonic phrases have been saved to ~/.mnemonic"
    else
        echo "Wallet directory already exists. Skipping wallet creation."
    fi
}


export_private_key() {
    set_env
    cd "$HOME/vana-dlp-chatgpt"
    
    # Load wallet configuration
    source ~/.walletaccount 2>/dev/null || true
    
    # Use default values if not set
    WALLET_NAME=${VANA_WALLET_NAME:-"default"}
    HOTKEY_NAME=${VANA_HOTKEY_NAME:-"default"}
    WALLET_PASSWORD=${VANA_WALLET_PASSWORD}
    
    echo "Exporting keys for wallet: $WALLET_NAME"
    
    # Export coldkey using expect
    echo "Exporting coldkey..."
    TEMP_COLDKEY=$(mktemp)
    expect << EOF | tee "$TEMP_COLDKEY"
    spawn ./vanacli wallet export_private_key --wallet.name "$WALLET_NAME" --key.type coldkey
    expect "Enter key type"
    send "coldkey\r"
    expect "Do you understand the risks?"
    send "yes\r"
    expect "Enter your coldkey password:"
    send "$WALLET_PASSWORD\r"
    expect eof
EOF
    COLDKEY_PRIVATE_KEY=$(grep -oP '0x[a-fA-F0-9]{64}' "$TEMP_COLDKEY" | head -n 1)
    rm "$TEMP_COLDKEY"

    # Export hotkey using expect
    echo "Exporting hotkey..."
    TEMP_HOTKEY=$(mktemp)
    expect << EOF | tee "$TEMP_HOTKEY"
    spawn ./vanacli wallet export_private_key --wallet.name "$HOTKEY_NAME" --key.type hotkey
    expect "Enter key type"
    send "hotkey\r"
    expect "Do you understand the risks?"
    send "yes\r"
    expect "Enter your hotkey password:"
    send "$WALLET_PASSWORD\r"
    expect eof
EOF
    HOTKEY_PRIVATE_KEY=$(grep -oP '0x[a-fA-F0-9]{64}' "$TEMP_HOTKEY" | head -n 1)
    rm "$TEMP_HOTKEY"
    
    # Save private keys to .walletaccount if they were successfully exported
    if [ ! -z "$COLDKEY_PRIVATE_KEY" ] && [ ! -z "$HOTKEY_PRIVATE_KEY" ]; then
        # Remove existing private key entries if they exist
        sed -i '/VANA_COLDKEY_PRIVATE_KEY/d' ~/.walletaccount
        sed -i '/VANA_HOTKEY_PRIVATE_KEY/d' ~/.walletaccount
        
        # Add new private keys
        echo "export VANA_COLDKEY_PRIVATE_KEY=\"${COLDKEY_PRIVATE_KEY}\"" >> ~/.walletaccount
        echo "export VANA_HOTKEY_PRIVATE_KEY=\"${HOTKEY_PRIVATE_KEY}\"" >> ~/.walletaccount
        
        echo "Private keys have been saved to ~/.walletaccount"
    else
        echo "Failed to export one or both private keys"
    fi
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
    
    # API_KEY 입력 받기
    if [ -z "$OPENAI_API_KEY" ]; then
        read -p "Enter OpenAI API Key: " API_KEY
    else
        API_KEY=$OPENAI_API_KEY
    fi
    
    # Save to ~/.walletaccount
    if [ -f ~/.walletaccount ]; then
        # Remove existing entries if they exist
        sed -i '/VANA_TOKEN_CONTRACT/d' ~/.walletaccount
        sed -i '/VANA_POOL_CONTRACT/d' ~/.walletaccount
        sed -i '/OPENAI_API_KEY/d' ~/.walletaccount
        
        # Add new entries
        echo "export VANA_TOKEN_CONTRACT=\"${TOKEN_CONTRACT}\"" >> ~/.walletaccount
        echo "export VANA_POOL_CONTRACT=\"${POOL_CONTRACT}\"" >> ~/.walletaccount
        echo "export OPENAI_API_KEY=\"${API_KEY}\"" >> ~/.walletaccount
    else
        cat > ~/.walletaccount << EOL
export VANA_TOKEN_CONTRACT="${TOKEN_CONTRACT}"
export VANA_POOL_CONTRACT="${POOL_CONTRACT}"
export OPENAI_API_KEY="${API_KEY}"
EOL
    fi

    if ! grep -q "source ~/.walletaccount" ~/.profile; then
        echo 'source ~/.walletaccount' >> ~/.profile
    fi
    source ~/.walletaccount
    
    cat <<EOF > .env
# The network to use, currently Vana Moksha testnet
OD_CHAIN_NETWORK=moksha
OD_CHAIN_NETWORK_ENDPOINT=https://rpc.moksha.vana.org

# Optional: OpenAI API key for additional data quality check
OPENAI_API_KEY="${API_KEY}"

# Optional: Your own DLP smart contract address once deployed to the network, useful for local testing
DLP_MOKSHA_CONTRACT=${POOL_CONTRACT}

# Optional: Your own DLP token contract address once deployed to the network, useful for local testing
DLP_TOKEN_MOKSHA_CONTRACT=${TOKEN_CONTRACT}

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
