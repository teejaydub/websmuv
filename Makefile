configDir = $(shell pwd)/../conf

ifeq ("$(wildcard $(configDir)/hostname.txt)", "")
hostname = localhost
else
hostname = $(shell cat $(configDir)/hostname.txt)
endif

ifeq ("$(wildcard $(configDir)/tld.txt)", "")
tld = example.com
else
tld = $(shell cat $(configDir)/tld.txt)
endif

all: depends config


###########################################################################
# Setup within the dev or server environment.

depends:
	sudo apt install curl
	# UV, only if not already installed
	uv --version || curl -LsSf https://astral.sh/uv/install.sh | sh

# Creates default config files if they don't already exist, in ../config.
config: config-dir config-pem config-hostname config-email config-instance config-instance-type config-maintenance config-diskalert config-nginx

config-dir:
	mkdir -p $(configDir)

config-pem:
ifeq ("$(wildcard $(configDir)/.gitignore)", "")
	echo "server.pem" > $(configDir)/.gitignore
endif
ifneq ("$(wildcard $(configDir)/server.pem)", "")
	chmod go-rw $(configDir)/server.pem
endif

config-tld:
ifeq ("$(wildcard $(configDir)/tld.txt)", "")
	echo $(tld) > $(configDir)/tld.txt
endif

config-hostname:
ifeq ("$(wildcard $(configDir)/hostname.txt)", "")
	echo $(hostname) > $(configDir)/hostname.txt
endif

config-email:
ifeq ("$(wildcard $(configDir)/email.txt)", "")
	echo service@$(tld) > $(configDir)/email.txt
endif

config-instance:
ifeq ("$(wildcard $(configDir)/instance.txt)", "")
	echo "(i-something)" > $(configDir)/instance.txt
endif

config-instance-type:
ifeq ("$(wildcard $(configDir)/instance-type.txt)", "")
	echo t3.micro > $(configDir)/instance-type.txt
endif

config-maintenance:
ifeq ("$(wildcard $(configDir)/maintenance.html)", "")
	cp default/maintenance.html $(configDir)/
endif

config-diskalert:
ifeq ("$(wildcard $(configDir)/diskalert.conf)", "")
	cp default/diskalert.conf $(configDir)/
endif

config-nginx:
ifeq ("$(wildcard $(configDir)/nginx-app.conf)", "")
	cp default/nginx-app.conf $(configDir)/
endif


###########################################################################
# Connecting to the server

ssh:
	ssh ubuntu@$(shell cat $(configDir)/hostname.txt) -i $(configDir)/server.pem


###########################################################################
# First-time server setup.
# OK to run again - won't cause harm to existing configuration.

install: config nginx-install nginx-start

nginx-install:
	sudo apt install nginx

	sudo ufw allow http
	sudo ufw allow https

	# Generate unique Diffie-Helman parameters.
	sudo mkdir -p /etc/pki/nginx/
	sudo openssl dhparam -out /etc/pki/nginx/dhparams.pem 2048

	make nginx-configure

# Create and enable the app site with the current configuration.
nginx-configure:
ifeq ("$(hostname)", "localhost")
	uv run python -m template hostname=$(hostname) tld=$(tld) configDir=$(configDir) < conf/nginx-localhost.conf.template > nginx.conf
	make $(configDir)/localhost.pem
else
	uv run python -m template hostname=$(hostname) tld=$(tld) configDir=$(configDir) < conf/nginx.conf.template > nginx.conf
endif
	sudo mv nginx.conf /etc/nginx/sites-available/$(hostname)
	uv run python -m template hostname=$(hostname) tld=$(tld) configDir=$(configDir) < conf/nginx-maintenance.conf.template > maintenance.conf
	sudo mv maintenance.conf /etc/nginx/sites-available/maintenance.conf
	uv run python -m template hostname=$(hostname) tld=$(tld) configDir=$(configDir) < conf/nginx-redirect80.conf.template > redirect80.conf
	sudo mv redirect80.conf /etc/nginx/sites-available/redirect80.conf
	make nginx-enable-redirect80

$(configDir)/localhost.pem: $(configDir)/hostname.txt
	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout $(configDir)/localhost-key.pem -out $(configDir)/localhost.pem -subj "/O=$(tld)/CN=$(localhost)" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

nginx-enable-maintenance:
	sudo rm /etc/nginx/sites-enabled/*  # in case hostname has changed
	sudo ln -s -f /etc/nginx/sites-available/maintenance.conf /etc/nginx/sites-enabled/
	sudo mkdir -p /var/www/html/maintenance
	sudo cp -f $(configDir)/maintenance.html /var/www/html/maintenance/index.html
nginx-disable-maintenance:
	sudo rm /etc/nginx/sites-enabled/*
	sudo ln -s -f /etc/nginx/sites-available/$(hostname) /etc/nginx/sites-enabled/

nginx-enable-redirect80:
	sudo ln -s -f /etc/nginx/sites-available/redirect80.conf /etc/nginx/sites-enabled/
nginx-disable-redirect80:
	sudo rm -f /etc/nginx/sites-enabled/redirect80.conf

nginx-start:
	-sudo systemctl reload nginx || sudo systemctl restart nginx || sudo systemctl start nginx

nginx-stop:
	sudo systemctl stop nginx

nginx-status:
	sudo systemctl status nginx

nginx-restart:
	sudo systemctl restart nginx || sudo systemctl start nginx

nginx-reload:
	sudo systemctl reload nginx

nginx-follow-log:
	sudo tail -F /var/log/nginx/access.log

nginx-log:
	sudo less /var/log/nginx/access.log

fail2ban-install:
	# Make the sample fail2ban jail active.
	sudo ln -s -f $(configDir)/jail.local /etc/fail2ban
	sudo systemctl restart fail2ban


###########################################################################
# Updating everything

update-start:
	make nginx-enable-maintenance nginx-start

update-middle:
	make nginx-configure

update-end:
	make nginx-disable-maintenance nginx-enable-redirect80 nginx-reload
	make nginx-status

update: update-start update-middle update-end
