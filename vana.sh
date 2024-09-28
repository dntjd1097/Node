#!/bin/bash

install_dependencies() {
    sudo apt update && sudo apt install software-properties-common -y 
	sudo add-apt-repository ppa:deadsnakes/ppa
	sudo apt update
	sudo apt install python3.11 python3.11-venv python3.11-dev -y
	python3.11 --version
	curl -sSL https://install.python-poetry.org | python3 -
	echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bash_profile
	source $HOME/.bash_profile
	poetry --version
	echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc
	source $HOME/.bashrc
	poetry --version
	
	
	
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
	# NVM 설정을 .bash_profile에 추가
	echo 'export NVM_DIR="$HOME/.nvm"' >> $HOME/.bash_profile
	echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> $HOME/.bash_profile
	echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> $HOME/.bash_profile

	# NVM 설정을 .bashrc에도 추가
	echo 'export NVM_DIR="$HOME/.nvm"' >> $HOME/.bashrc
	echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> $HOME/.bashrc
	echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> $HOME/.bashrc

	# 설정 파일을 적용 (로그인 쉘)
	source $HOME/.bash_profile
	source $HOME/.bashrc

	nvm install --lts
	node -v
	npm -v
    echo "Dependencies installed."
}
set_env(){
	source $HOME/.bash_profile
	source $HOME/.bashrc
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
	./vanacli wallet create --wallet.name default --wallet.hotkey default
}

export_private_key() {
	set_env
    cd "$HOME/vana-dlp-chatgpt"
    ./vanacli wallet export_private_key
}

setup_dlp_smart_contracts(){
	set_env
    cd "$HOME/vana-dlp-chatgpt"
	./keygen.sh
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
	read -p "enter"
	read -p "wallet address (0x...): " ip_address
    read -p "wallet private key (0x...): " private_key
    read -p "DLP_NAME: " DLP_NAME
    read -p "DLP_TOKEN_NAME: " DLP_TOKEN_NAME
	read -p "DLP_TOKEN_SYMBOL: " DLP_TOKEN_SYMBOL
	
	sed -i "s/^DEPLOYER_PRIVATE_KEY=0xef.*/DEPLOYER_PRIVATE_KEY=${private_key}/" .env
	sed -i "s/^OWNER_ADDRESS=0x7B.*/OWNER_ADDRESS=${ip_address}/" .env
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
	read -p "DLP_TOKEN_MOKSHA_CONTRACT: " token_contract
    read -p "DLP_MOKSHA_CONTRACT: " pool_contract
	read -p "OPENAI_API_KEY: " api
	
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
sudo systemctl start vana.service && \
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
