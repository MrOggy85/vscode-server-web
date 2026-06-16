init: install_additional_packages.sh allowed-domains.txt

install_additional_packages.sh:
	cp install_additional_packages.sh.example install_additional_packages.sh
	chmod +x install_additional_packages.sh

allowed-domains.txt:
	cp allowed-domains.txt.example allowed-domains.txt
