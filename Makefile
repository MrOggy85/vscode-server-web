build: install_additional_packages.sh
	docker build -t vscode-serve-web:local .

install_additional_packages.sh:
	cp install_additional_packages.sh.example install_additional_packages.sh
	chmod +x install_additional_packages.sh
