#!/bin/bash

install_dependencies() {
    sudo apt update && sudo apt install software-properties-common -y 
	sudo apt-get install expect -y
	sudo add-apt-repository ppa:deadsnakes/ppa
	sudo apt update
	sudo apt install python3.11 python3.11-venv python3.11-dev -y
    sudo apt -y install pipx
    sudo pipx ensurepath
    sudo pipx install poetry --force
	python3.11 --version
	# curl -sSL https://install.python-poetry.org | python3 -
    # suto apt install python3-poetry -y
	
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
    # 기존 값 로드
    if [ -f ~/.vanawallet ]; then
        source ~/.vanawallet
    fi
    
    # 기본값 설정
    VANA_WALLET_NAME=${VANA_WALLET_NAME:-"default"}
    VANA_HOTKEY_NAME=${VANA_HOTKEY_NAME:-"default"}
    VANA_WALLET_PASSWORD=${VANA_WALLET_PASSWORD:-"your_default_password"}
    
    # 입력 받기
    if [ -z "$VANA_VALIDATOR_NAME" ]; then
        read -p "Enter Validator Name: " VANA_VALIDATOR_NAME
    fi
    
    if [ -z "$VANA_VALIDATOR_EMAIL" ]; then
        read -p "Enter Validator Email: " VANA_VALIDATOR_EMAIL
    fi
    
    VANA_KEY_EXPIRY=${VANA_KEY_EXPIRY:-"0"}
    
    # 설정 업데이트
    update_vanawallet
}

download() {
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
    echo "Download completed successfully"
}

setup_wallet() {
    while true; do
        echo "========== WALLET SETUP MENU =========="
        echo "1. Create New Wallet"
        echo "2. Import Existing Wallet"
        echo "3. Delete Wallet"
        echo "4. Back to Main Menu"
        echo "====================================="
        
        read -p "Enter choice (1-4): " wallet_choice

        case $wallet_choice in
            1)
                create_wallet
                ;;
            2)
                import_wallet
                ;;
            3)
                delete_wallet
                ;;
            4)
                return
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
    done
}

create_new_wallet() {
    cd "$HOME/vana-dlp-chatgpt"
    
    # Create new wallet
    TEMP_MNEMONIC=$(mktemp)
    VANA_WALLET_NAME="default"
    VANA_HOTKEY_NAME="default"
    expect << EOF | tee "$TEMP_MNEMONIC"
    spawn ./vanacli wallet create
    expect "Enter wallet name"
    send "default\r"
    expect "Enter hotkey name"
    send "default\r"
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
    
    echo "New wallet created successfully"
}

import_wallet() {
    cd "$HOME/vana-dlp-chatgpt"
    
    # Prompt for mnemonics and password
    echo "Please enter your wallet information:"
    read -p "Enter coldkey mnemonic (12 words): " VANA_COLDKEY_MNEMONIC
    read -p "Enter hotkey mnemonic (12 words): " VANA_HOTKEY_MNEMONIC
    read -s -p "Enter wallet password: " VANA_WALLET_PASSWORD
    echo
    
    # Default wallet names
    VANA_WALLET_NAME="default"
    VANA_HOTKEY_NAME="default"
    
    # Clean up mnemonics (remove extra spaces and special characters)
    VANA_COLDKEY_MNEMONIC=$(echo "$VANA_COLDKEY_MNEMONIC" | tr -d '"' | xargs)
    VANA_HOTKEY_MNEMONIC=$(echo "$VANA_HOTKEY_MNEMONIC" | tr -d '"' | xargs)
    
    # Remove existing wallet directory if it exists
    rm -rf "$HOME/.vana/wallets/default"
    
    # Create wallet directory
    mkdir -p "$HOME/.vana/wallets/default/hotkeys"
    
    echo "Importing coldkey..."
    # Regenerate coldkey with cleaned mnemonic
    expect << EOF
    spawn ./vanacli w regen_coldkey --mnemonic $VANA_COLDKEY_MNEMONIC
    expect "Enter wallet name"
    send "$VANA_WALLET_NAME\r"
    expect "Specify password for key encryption:"
    send "$VANA_WALLET_PASSWORD\r"
    expect "Retype your password:"
    send "$VANA_WALLET_PASSWORD\r"
    expect eof
EOF
    
    echo "Importing hotkey..."
    # Regenerate hotkey with cleaned mnemonic
    expect << EOF
    spawn ./vanacli w regen_hotkey --mnemonic $VANA_HOTKEY_MNEMONIC
    expect "Enter wallet name"
    send "$VANA_WALLET_NAME\r"
    expect "Enter hotkey name"
    send "$VANA_HOTKEY_NAME\r"
    expect eof
EOF
    
    # Save configuration to .vanawallet
    cat > ~/.vanawallet << EOL
# Wallet Configuration
export VANA_WALLET_NAME="${VANA_WALLET_NAME}"
export VANA_HOTKEY_NAME="${VANA_HOTKEY_NAME}"
export VANA_WALLET_PASSWORD="${VANA_WALLET_PASSWORD}"

# Mnemonics (Keep secure!)
export VANA_COLDKEY_MNEMONIC="${VANA_COLDKEY_MNEMONIC}"
export VANA_HOTKEY_MNEMONIC="${VANA_HOTKEY_MNEMONIC}"
EOL
    
    # Set appropriate permissions
    chmod 600 ~/.vanawallet
    
    # Source the new configuration
    source ~/.vanawallet
    
    echo "Wallet imported successfully!"
    echo "Wallet configuration saved to ~/.vanawallet"
    echo "IMPORTANT: Please ensure your mnemonics are stored securely!"
}

delete_wallet() {
    read -p "Enter wallet name to delete (default: default): " wallet_name
    wallet_name=${wallet_name:-"default"}  # 입력이 없으면 "default" 사용
    rm -rf "$HOME/.vana/wallets/$wallet_name"
    echo "Wallet '$wallet_name' deleted successfully"
}

setup_dlp_smart_contracts() {
    set_env
    cd "$HOME/vana-dlp-chatgpt"
    
    # Load existing environment variables
    source ~/.vanawallet 2>/dev/null || true
    
    # Check validator info variables
    if [ -z "$VANA_VALIDATOR_NAME" ]; then
        read -p "Enter your name: " VANA_VALIDATOR_NAME
    fi

    if [ -z "$VANA_VALIDATOR_EMAIL" ]; then
        read -p "Enter your email: " VANA_VALIDATOR_EMAIL
    fi

    if [ -z "$VANA_KEY_EXPIRY" ]; then
        read -p "Enter key expiration in days: " VANA_KEY_EXPIRY
    fi

    # Check wallet variables
    if [ -z "$VANA_COLDKEY_ADDRESS" ] || [ -z "$VANA_COLDKEY_PRIVATE_KEY" ]; then
        echo "Wallet information not found. Please run 'export wallet' first to generate keys."
        read -p "Would you like to continue with manual input? (y/n): " continue_input
        if [[ $continue_input == "y" ]]; then
            read -p "Enter wallet address (0x...): " VANA_COLDKEY_ADDRESS
            read -p "Enter wallet private key (0x...): " VANA_COLDKEY_PRIVATE_KEY
        else
            return 1
        fi
    fi

    # Check DLP variables
    if [ -z "$VANA_DLP_NAME" ]; then
        read -p "Enter DLP_NAME: " VANA_DLP_NAME
    fi

    if [ -z "$VANA_DLP_TOKEN_NAME" ]; then
        read -p "Enter DLP_TOKEN_NAME: " VANA_DLP_TOKEN_NAME
    fi

    if [ -z "$VANA_DLP_TOKEN_SYMBOL" ]; then
        read -p "Enter DLP_TOKEN_SYMBOL: " VANA_DLP_TOKEN_SYMBOL
    fi

    # Update .vanawallet file
    if [ -f ~/.vanawallet ]; then
        # Remove existing entries
        sed -i "/VANA_VALIDATOR_NAME/d" ~/.vanawallet
        sed -i "/VANA_VALIDATOR_EMAIL/d" ~/.vanawallet
        sed -i "/VANA_KEY_EXPIRY/d" ~/.vanawallet
        sed -i "/VANA_DLP_NAME/d" ~/.vanawallet
        sed -i "/VANA_DLP_TOKEN_NAME/d" ~/.vanawallet
        sed -i "/VANA_DLP_TOKEN_SYMBOL/d" ~/.vanawallet
        
        # Add/update entries
        echo "export VANA_VALIDATOR_NAME=\"${VANA_VALIDATOR_NAME}\"" >> ~/.vanawallet
        echo "export VANA_VALIDATOR_EMAIL=\"${VANA_VALIDATOR_EMAIL}\"" >> ~/.vanawallet
        echo "export VANA_KEY_EXPIRY=\"${VANA_KEY_EXPIRY}\"" >> ~/.vanawallet
        echo "export VANA_DLP_NAME=\"${VANA_DLP_NAME}\"" >> ~/.vanawallet
        echo "export VANA_DLP_TOKEN_NAME=\"${VANA_DLP_TOKEN_NAME}\"" >> ~/.vanawallet
        echo "export VANA_DLP_TOKEN_SYMBOL=\"${VANA_DLP_TOKEN_SYMBOL}\"" >> ~/.vanawallet
        
        # Add wallet info if manually entered
        if [[ $continue_input == "y" ]]; then
            sed -i "/VANA_COLDKEY_ADDRESS/d" ~/.vanawallet
            sed -i "/VANA_COLDKEY_PRIVATE_KEY/d" ~/.vanawallet
            echo "export VANA_COLDKEY_ADDRESS=\"${VANA_COLDKEY_ADDRESS}\"" >> ~/.vanawallet
            echo "export VANA_COLDKEY_PRIVATE_KEY=\"${VANA_COLDKEY_PRIVATE_KEY}\"" >> ~/.vanawallet
        fi
    else
        # Create new .vanawallet file
        cat > ~/.vanawallet << EOL
export VANA_VALIDATOR_NAME="${VANA_VALIDATOR_NAME}"
export VANA_VALIDATOR_EMAIL="${VANA_VALIDATOR_EMAIL}"
export VANA_KEY_EXPIRY="${VANA_KEY_EXPIRY}"
export VANA_DLP_NAME="${VANA_DLP_NAME}"
export VANA_DLP_TOKEN_NAME="${VANA_DLP_TOKEN_NAME}"
export VANA_DLP_TOKEN_SYMBOL="${VANA_DLP_TOKEN_SYMBOL}"
EOL
        # Add wallet info if manually entered
        if [[ $continue_input == "y" ]]; then
            echo "export VANA_COLDKEY_ADDRESS=\"${VANA_COLDKEY_ADDRESS}\"" >> ~/.vanawallet
            echo "export VANA_COLDKEY_PRIVATE_KEY=\"${VANA_COLDKEY_PRIVATE_KEY}\"" >> ~/.vanawallet
        fi
    fi

    # Ensure .vanawallet is sourced
    if ! grep -q "source ~/.vanawallet" ~/.profile; then
        echo 'source ~/.vanawallet' >> ~/.profile
    fi
    source ~/.vanawallet

    # Continue with keygen.sh
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

    # Setup smart contracts
    cd $HOME
    rm -rf vana-dlp-smart-contracts
    git clone https://github.com/Josephtran102/vana-dlp-smart-contracts
    cd "$HOME/vana-dlp-smart-contracts"
    npm install -g yarn
    yarn --version
    yarn install
    cp .env.example .env
    
    # Update .env file with stored values
    sed -i "s/^DEPLOYER_PRIVATE_KEY=0xef.*/DEPLOYER_PRIVATE_KEY=${VANA_COLDKEY_PRIVATE_KEY}/" .env
    sed -i "s/^OWNER_ADDRESS=0x7B.*/OWNER_ADDRESS=${VANA_COLDKEY_ADDRESS}/" .env
    sed -i "s/^DLP_NAME=J.*/DLP_NAME=${VANA_DLP_NAME}/" .env
    sed -i "s/^DLP_TOKEN_NAME=J.*/DLP_TOKEN_NAME=${VANA_DLP_TOKEN_NAME}/" .env
    sed -i "s/^DLP_TOKEN_SYMBOL=J.*/DLP_TOKEN_SYMBOL=${VANA_DLP_TOKEN_SYMBOL}/" .env
    
    # Deploy contracts and capture output
    echo "Deploying contracts..."
    DEPLOY_OUTPUT=$(npx hardhat deploy --network moksha --tags DLPDeploy)
    
    # Extract contract addresses using grep and awk
    VANA_DLP_TOKEN_MOKSHA_CONTRACT=$(echo "$DEPLOY_OUTPUT" | grep "DataLiquidityPoolToken deployed at:" | awk '{print $NF}' | head -n 1)
    VANA_DLP_MOKSHA_CONTRACT=$(echo "$DEPLOY_OUTPUT" | grep "DataLiquidityPool \"[^\"]*\" deployed at:" | awk '{print $NF}' | head -n 1)
    
    # Verify if addresses were found
    if [ ! -z "$VANA_DLP_TOKEN_MOKSHA_CONTRACT" ] && [ ! -z "$VANA_DLP_MOKSHA_CONTRACT" ]; then
        echo "Successfully deployed contracts:"
        echo "VANA_DLP_TOKEN_MOKSHA_CONTRACT: $VANA_DLP_TOKEN_MOKSHA_CONTRACT"
        echo "VANA_DLP_MOKSHA_CONTRACT: $VANA_DLP_MOKSHA_CONTRACT"
        
        # Update .vanawallet with new contract addresses
        if [ -f ~/.vanawallet ]; then
            # Remove existing contract addresses if they exist
            sed -i '/VANA_DLP_TOKEN_MOKSHA_CONTRACT/d' ~/.vanawallet
            sed -i '/VANA_DLP_MOKSHA_CONTRACT/d' ~/.vanawallet
            
            # Add new contract addresses
            echo "export VANA_DLP_TOKEN_MOKSHA_CONTRACT=\"${VANA_DLP_TOKEN_MOKSHA_CONTRACT}\"" >> ~/.vanawallet
            echo "export VANA_DLP_MOKSHA_CONTRACT=\"${VANA_DLP_MOKSHA_CONTRACT}\"" >> ~/.vanawallet
        else
            # Create new .vanawallet file with contract addresses
            cat > ~/.vanawallet << EOL
export VANA_DLP_TOKEN_MOKSHA_CONTRACT="${VANA_DLP_TOKEN_MOKSHA_CONTRACT}"
export VANA_DLP_MOKSHA_CONTRACT="${VANA_DLP_MOKSHA_CONTRACT}"
EOL
        fi
        
        source ~/.vanawallet
        echo "Contract addresses have been saved to ~/.vanawallet"
    else
        echo "Failed to capture contract addresses from deployment output"
        return 1
    fi
}

verifyF() {
    set_env
    cd "$HOME/vana-dlp-smart-contracts"
    
    # Load environment variables from .vanawallet
    source ~/.vanawallet 2>/dev/null || true
    
    # Check if contract addresses exist
    if [ -z "$VANA_DLP_TOKEN_MOKSHA_CONTRACT" ] || [ -z "$VANA_DLP_MOKSHA_CONTRACT" ]; then
        echo "Contract addresses not found in .vanawallet"
        echo "Please run option 3 first to deploy contracts, or enter addresses manually"
        read -p "Would you like to enter addresses manually? (y/n): " manual_input
        if [[ $manual_input == "y" ]]; then
            read -p "DLP_TOKEN_MOKSHA_CONTRACT: " VANA_DLP_TOKEN_MOKSHA_CONTRACT
            read -p "DLP_MOKSHA_CONTRACT: " VANA_DLP_MOKSHA_CONTRACT
            
            # Save to .vanawallet
            if [ -f ~/.vanawallet ]; then
                sed -i '/VANA_DLP_TOKEN_MOKSHA_CONTRACT/d' ~/.vanawallet
                sed -i '/VANA_DLP_MOKSHA_CONTRACT/d' ~/.vanawallet
            fi
            echo "export VANA_DLP_TOKEN_MOKSHA_CONTRACT=\"${VANA_DLP_TOKEN_MOKSHA_CONTRACT}\"" >> ~/.vanawallet
            echo "export VANA_DLP_MOKSHA_CONTRACT=\"${VANA_DLP_MOKSHA_CONTRACT}\"" >> ~/.vanawallet
            source ~/.vanawallet
        else
            echo "Verification cancelled"
            return 1
        fi
    fi
    
    # Check if DLP token information exists
    if [ -z "$VANA_DLP_TOKEN_NAME" ] || [ -z "$VANA_DLP_TOKEN_SYMBOL" ]; then
        echo "DLP token information not found in .vanawallet"
        read -p "Enter DLP_TOKEN_NAME: " VANA_DLP_TOKEN_NAME
        read -p "Enter DLP_TOKEN_SYMBOL: " VANA_DLP_TOKEN_SYMBOL
        
        # Save to .vanawallet
        if [ -f ~/.vanawallet ]; then
            sed -i '/VANA_DLP_TOKEN_NAME/d' ~/.vanawallet
            sed -i '/VANA_DLP_TOKEN_SYMBOL/d' ~/.vanawallet
        fi
        echo "export VANA_DLP_TOKEN_NAME=\"${VANA_DLP_TOKEN_NAME}\"" >> ~/.vanawallet
        echo "export VANA_DLP_TOKEN_SYMBOL=\"${VANA_DLP_TOKEN_SYMBOL}\"" >> ~/.vanawallet
        source ~/.vanawallet
    fi
    
    echo "Verifying contracts..."
    echo "Pool Contract: $VANA_DLP_MOKSHA_CONTRACT"
    echo "Token Contract: $VANA_DLP_TOKEN_MOKSHA_CONTRACT"
    echo "Token Name: $VANA_DLP_TOKEN_NAME"
    echo "Token Symbol: $VANA_DLP_TOKEN_SYMBOL"
    
    # Get public IP address
    ip_address=$(curl -s ifconfig.me)
    
    # Verify contracts
    echo "Verifying Pool Contract..."
    npx hardhat verify --network moksha ${VANA_DLP_MOKSHA_CONTRACT}
    
    echo "Verifying Token Contract..."
    npx hardhat verify --network moksha ${VANA_DLP_TOKEN_MOKSHA_CONTRACT} "${VANA_DLP_TOKEN_NAME}" "${VANA_DLP_TOKEN_SYMBOL}" "${ip_address}"
}




run() {
    set_env
    cd "$HOME/vana-dlp-chatgpt"
    public_key=$(cat /root/vana-dlp-chatgpt/public_key_base64.asc)

    # Load environment variables from .vanawallet
    source ~/.vanawallet 2>/dev/null || true
    
    # Check if wallet configuration exists
    if [ -z "$VANA_WALLET_NAME" ] || [ -z "$VANA_HOTKEY_NAME" ] || [ -z "$VANA_WALLET_PASSWORD" ]; then
        echo "Wallet configuration not found in .vanawallet"
        echo "Please run option 1 first to set up wallet configuration"
        return 1
    fi
    
    # Check if contract addresses exist
    if [ -z "$VANA_DLP_TOKEN_MOKSHA_CONTRACT" ] || [ -z "$VANA_DLP_MOKSHA_CONTRACT" ]; then
        echo "Contract addresses not found in .vanawallet"
        echo "Please run option 3 first to deploy contracts, or enter addresses manually"
        read -p "Would you like to enter addresses manually? (y/n): " manual_input
        if [[ $manual_input == "y" ]]; then
            read -p "DLP_TOKEN_MOKSHA_CONTRACT: " VANA_DLP_TOKEN_MOKSHA_CONTRACT
            read -p "DLP_MOKSHA_CONTRACT: " VANA_DLP_MOKSHA_CONTRACT
            
            # Save to .vanawallet
            if [ -f ~/.vanawallet ]; then
                sed -i '/VANA_DLP_TOKEN_MOKSHA_CONTRACT/d' ~/.vanawallet
                sed -i '/VANA_DLP_MOKSHA_CONTRACT/d' ~/.vanawallet
            fi
            echo "export VANA_DLP_TOKEN_MOKSHA_CONTRACT=\"${VANA_DLP_TOKEN_MOKSHA_CONTRACT}\"" >> ~/.vanawallet
            echo "export VANA_DLP_MOKSHA_CONTRACT=\"${VANA_DLP_MOKSHA_CONTRACT}\"" >> ~/.vanawallet
            source ~/.vanawallet
        else
            echo "Run cancelled"
            return 1
        fi
    fi
    
    # Check if OpenAI API key exists
    if [ -z "$OPENAI_API_KEY" ]; then
        read -p "Enter OpenAI API Key: " OPENAI_API_KEY
        
        # Save to .vanawallet
        if [ -f ~/.vanawallet ]; then
            sed -i '/OPENAI_API_KEY/d' ~/.vanawallet
        fi
        echo "export OPENAI_API_KEY=\"${OPENAI_API_KEY}\"" >> ~/.vanawallet
        source ~/.vanawallet
    fi
    
    # Create .env file with necessary variables
    cat <<EOF > .env
OD_CHAIN_NETWORK=moksha
OD_CHAIN_NETWORK_ENDPOINT=https://rpc.moksha.vana.org
OPENAI_API_KEY="${OPENAI_API_KEY}"
DLP_MOKSHA_CONTRACT=${VANA_DLP_MOKSHA_CONTRACT}
DLP_TOKEN_MOKSHA_CONTRACT=${VANA_DLP_TOKEN_MOKSHA_CONTRACT}
PRIVATE_FILE_ENCRYPTION_PUBLIC_KEY_BASE64="${public_key}"
EOF
    
    # Register validator using expect
    expect << EOF
    spawn ./vanacli dlp register_validator --stake_amount 10
    expect "Enter wallet name"
    send "${VANA_WALLET_NAME}\r"
    expect "Enter hotkey name"
    send "${VANA_HOTKEY_NAME}\r"
    expect "Enter password to unlock key:"
    send "${VANA_WALLET_PASSWORD}\r"
    expect eof
EOF
    
    # Use VANA_HOTKEY_ADDRESS from .vanawallet
    echo "Using hotkey address: ${VANA_HOTKEY_ADDRESS}"
    
    # Approve validator using expect
    expect << EOF
    spawn ./vanacli dlp approve_validator --validator_address=${VANA_HOTKEY_ADDRESS}
    expect "Enter wallet name"
    send "${VANA_WALLET_NAME}\r"
    expect "Enter password to unlock key:"
    send "${VANA_WALLET_PASSWORD}\r"
    expect eof
EOF
    
    # Run the validator node
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



create_wallet() {
    cd "$HOME/vana-dlp-chatgpt"
    
    # Create temporary file for mnemonic capture
    TEMP_MNEMONIC=$(mktemp)
    
    # Default wallet settings
    VANA_WALLET_NAME="default"
    VANA_HOTKEY_NAME="default"
    
    # Prompt for wallet password if not set
    if [ -z "$VANA_WALLET_PASSWORD" ]; then
        read -s -p "Enter wallet password: " VANA_WALLET_PASSWORD
        echo
    fi
    
    # Create new wallet and capture output
    expect << EOF | tee "$TEMP_MNEMONIC"
    spawn ./vanacli wallet create
    expect "Enter wallet name"
    send "${VANA_WALLET_NAME}\r"
    expect "Enter hotkey name"
    send "${VANA_HOTKEY_NAME}\r"
    expect "Your coldkey mnemonic phrase:"
    expect -re {│\s+([\w\s]+)\s+│}
    set coldkey_mnemonic \$expect_out(1,string)
    expect "Specify password for key encryption:"
    send "${VANA_WALLET_PASSWORD}\r"
    expect "Retype your password:"
    send "${VANA_WALLET_PASSWORD}\r"
    expect "Your hotkey mnemonic phrase:"
    expect -re {│\s+([\w\s]+)\s+│}
    set hotkey_mnemonic \$expect_out(1,string)
    expect eof
EOF
    
    # Extract mnemonics from temporary file
    VANA_COLDKEY_MNEMONIC=$(grep -A 2 "Your coldkey mnemonic phrase:" "$TEMP_MNEMONIC" | tail -n 1 | sed 's/│//g' | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | xargs)
    VANA_HOTKEY_MNEMONIC=$(grep -A 2 "Your hotkey mnemonic phrase:" "$TEMP_MNEMONIC" | tail -n 1 | sed 's/│//g' | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | xargs)
    
    # Clean up temporary file
    rm "$TEMP_MNEMONIC"
    
    # Save wallet configuration to .vanawallet
    cat > ~/.vanawallet << EOL
# Wallet Configuration
export VANA_WALLET_NAME="${VANA_WALLET_NAME}"
export VANA_HOTKEY_NAME="${VANA_HOTKEY_NAME}"
export VANA_WALLET_PASSWORD="${VANA_WALLET_PASSWORD}"

# Mnemonics (Keep secure!)
export VANA_COLDKEY_MNEMONIC="${VANA_COLDKEY_MNEMONIC}"
export VANA_HOTKEY_MNEMONIC="${VANA_HOTKEY_MNEMONIC}"
EOL
    
    # Set appropriate permissions
    chmod 600 ~/.vanawallet
    
    # Source the new configuration
    source ~/.vanawallet
    
    echo "Wallet created successfully!"
    echo "Wallet configuration saved to ~/.vanawallet"
    echo "IMPORTANT: Please backup your mnemonics and keep them secure!"
    echo "Coldkey mnemonic: $VANA_COLDKEY_MNEMONIC"
    echo "Hotkey mnemonic: $VANA_HOTKEY_MNEMONIC"
}
export_private_key() {
    set_env
    cd "$HOME/vana-dlp-chatgpt"
    
    # Install web3 if not installed
    if ! python3 -c "import web3" 2>/dev/null; then
        echo "Installing web3 package..."
        pip3 install web3
    fi
    
    # Create temporary Python script for address generation
    cat > /tmp/generate_eth_address.py << 'EOL'
from web3 import Web3
import sys

def get_address_from_private_key(private_key):
    private_key = private_key.replace("0x", "")
    w3 = Web3()
    try:
        account = w3.eth.account.from_key(private_key)
        return account.address
    except Exception as e:
        print(f"Error: {str(e)}")
        return None

if len(sys.argv) > 1:
    private_key = sys.argv[1]
    address = get_address_from_private_key(private_key)
    if address:
        print(address)
EOL
    
    # Load wallet configuration
    source ~/.vanawallet 2>/dev/null || true
    
    # Use default values if not set
    WALLET_NAME=${VANA_WALLET_NAME:-"default"}
    HOTKEY_NAME=${VANA_HOTKEY_NAME:-"default"}
    WALLET_PASSWORD=${VANA_WALLET_PASSWORD}
    
    echo "Exporting keys for wallet: $WALLET_NAME"
    
    # Export coldkey using expect
    echo "Exporting coldkey..."
    TEMP_COLDKEY=$(mktemp)
    expect -c "
        spawn ./vanacli wallet export_private_key --wallet.name \"$WALLET_NAME\" --key.type coldkey
        expect \"Enter key type\"
        send \"coldkey\r\"
        expect \"Do you understand the risks?\"
        send \"yes\r\"
        expect \"Enter your coldkey password:\"
        send \"$WALLET_PASSWORD\r\"
        expect eof
    " | tee "$TEMP_COLDKEY"

    # 개선된 private key 추출 방법
    COLDKEY_PRIVATE_KEY=$(grep -oP '0x[a-fA-F0-9]{64}' "$TEMP_COLDKEY" | head -n 1)
    echo "COLDKEY_PRIVATE_KEY: $COLDKEY_PRIVATE_KEY"
    rm "$TEMP_COLDKEY"

    if [ ! -z "$COLDKEY_PRIVATE_KEY" ]; then
        echo "Generating coldkey address..."
        COLDKEY_ADDRESS=$(python3 /tmp/generate_eth_address.py "$COLDKEY_PRIVATE_KEY")
        echo "Coldkey Address: $COLDKEY_ADDRESS"
    else 
        echo "Failed to extract coldkey private key"
    fi

    # Export hotkey using expect
    echo "Exporting hotkey..."
    TEMP_HOTKEY=$(mktemp)
    expect -c "
        spawn ./vanacli wallet export_private_key --wallet.name \"$HOTKEY_NAME\" --key.type hotkey
        expect \"Enter key type\"
        send \"hotkey\r\"
        expect \"Do you understand the risks?\"
        send \"yes\r\"
        expect \"Enter your hotkey password:\"
        send \"$WALLET_PASSWORD\r\"
        expect eof
    " | tee "$TEMP_HOTKEY"

    # 개선된 private key 추출 방법
    HOTKEY_PRIVATE_KEY=$(grep -oP '0x[a-fA-F0-9]{64}' "$TEMP_HOTKEY" | head -n 1)
    echo "HOTKEY_PRIVATE_KEY: $HOTKEY_PRIVATE_KEY"
    rm "$TEMP_HOTKEY"

    if [ ! -z "$HOTKEY_PRIVATE_KEY" ]; then
        echo "Generating hotkey address..."
        HOTKEY_ADDRESS=$(python3 /tmp/generate_eth_address.py "$HOTKEY_PRIVATE_KEY")
        echo "Hotkey Address: $HOTKEY_ADDRESS"
    else 
        echo "Failed to extract hotkey private key"
    fi
    
    # Clean up temporary Python script
    rm /tmp/generate_eth_address.py
    
    # Save private keys and addresses to .vanawallet if they were successfully exported
    if [ ! -z "$COLDKEY_PRIVATE_KEY" ] && [ ! -z "$HOTKEY_PRIVATE_KEY" ]; then
        # Remove existing entries if they exist
        sed -i '/VANA_COLDKEY_PRIVATE_KEY/d' ~/.vanawallet
        sed -i '/VANA_HOTKEY_PRIVATE_KEY/d' ~/.vanawallet
        sed -i '/VANA_COLDKEY_ADDRESS/d' ~/.vanawallet
        sed -i '/VANA_HOTKEY_ADDRESS/d' ~/.vanawallet
        
        # Add new private keys and addresses
        echo "export VANA_COLDKEY_PRIVATE_KEY=\"${COLDKEY_PRIVATE_KEY}\"" >> ~/.vanawallet
        echo "export VANA_HOTKEY_PRIVATE_KEY=\"${HOTKEY_PRIVATE_KEY}\"" >> ~/.vanawallet
        echo "export VANA_COLDKEY_ADDRESS=\"${COLDKEY_ADDRESS}\"" >> ~/.vanawallet
        echo "export VANA_HOTKEY_ADDRESS=\"${HOTKEY_ADDRESS}\"" >> ~/.vanawallet
        
        echo "Private keys and addresses have been saved to ~/.vanawallet"
    else
        echo "Failed to export one or both private keys"
    fi
}
main_menu() {
    while true; do
        echo "========== VANA VALIDATOR MENU =========="
        echo "1. Download"
        echo "2. Setup Wallet"
        echo "3. Export"
        echo "4. Setup DLP Smart Contracts"
        echo "5. Verify"
        echo "6. Run"
        echo "7. Service"
        echo "8. Log"
        echo "9. Exit"
        echo "========================================"
        
        read -p "Enter choice (1-8): " choice

        case $choice in
            1)
                download
                ;;
            2)
                setup_wallet
                ;;
            3)
                export_private_key
                ;;
            4)
                setup_dlp_smart_contracts
                ;;
            5)
                verifyF
                ;;
            6)
                run
                ;;
            7 ) 
                service
                ;;
            8)
                log
                ;;
            9)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                ;;
        esac
        
        echo -e "\nPress Enter to continue..."
        read
        clear
    done
}

echo "Preparing to launch main menu..."
main_menu

