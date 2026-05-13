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
	sudo apt install -y curl toilet
	# UV, only if not already installed
	uv --version || curl -LsSf https://astral.sh/uv/install.sh | sh

# Creates default config files if they don't already exist, in ../config.
config: config-dir config-pem config-tld config-hostname config-email config-instance config-instance-type config-maintenance config-diskalert config-nginx

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
	@toilet -t $(hostname) -f smblock -F border
	-ssh ubuntu@$(hostname) -i $(configDir)/server.pem
	@toilet -f smblock -F border $(shell hostname)

instanceID = $(shell cat $(configDir)/instance.txt)
vm-start:
	@aws ec2 start-instances --instance-ids $(instanceID) --query "StartingInstances[*].CurrentState.Name" --output text

vm-state:
	@aws ec2 describe-instances --instance-ids $(instanceID) --query "Reservations[*].Instances[*].State.Name" --output text


###########################################################################
# First-time server-side setup.
# OK to run again - won't cause harm to existing configuration.

install: depends config https-install certs-install jail-install https-restart set-hostname

confirm:
	@echo -n "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]

set-hostname:
	@echo
ifneq ("$(hostname)", "$(shell hostname)")
	@echo "This will change this machine's hostname from $(shell hostname) to $(hostname)."
	@make confirm
	sudo hostname --file $(configDir)/hostname.txt
endif

https-install:
	sudo apt install -y nginx ufw

	sudo ufw enable
	sudo ufw allow ssh
	sudo ufw allow http
	sudo ufw allow https

	# Generate unique Diffie-Helman parameters.
	sudo mkdir -p /etc/pki/nginx/
	sudo openssl dhparam -out /etc/pki/nginx/dhparams.pem 2048

	make https-configure

# Create and enable the app site with the current configuration.
https-configure:
	@echo
	@echo Setting up Nginx for host $(hostname)...
	sudo cp conf/nginx-slow.conf /etc/nginx/conf.d
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
	make https-enable-redirect80

$(configDir)/localhost.pem: $(configDir)/hostname.txt
	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout $(configDir)/localhost-key.pem -out $(configDir)/localhost.pem -subj "/O=$(tld)/CN=$(localhost)" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

https-enable-maintenance:
	sudo rm /etc/nginx/sites-enabled/*  # in case hostname has changed
	sudo ln -s -f /etc/nginx/sites-available/maintenance.conf /etc/nginx/sites-enabled/
	sudo mkdir -p /var/www/html/maintenance
	sudo cp -f $(configDir)/maintenance.html /var/www/html/maintenance/index.html
https-disable-maintenance:
	sudo rm /etc/nginx/sites-enabled/*
	sudo ln -s -f /etc/nginx/sites-available/$(hostname) /etc/nginx/sites-enabled/

https-enable-redirect80:
	sudo ln -s -f /etc/nginx/sites-available/redirect80.conf /etc/nginx/sites-enabled/
https-disable-redirect80:
	sudo rm -f /etc/nginx/sites-enabled/redirect80.conf

https-start:
	sudo systemctl start nginx

https-stop:
	sudo systemctl stop nginx

https-status:
	sudo systemctl status nginx --no-pager

https-restart:
	@if [ "$(shell systemctl show nginx -P ActiveState)" = "active" ]; then sudo systemctl restart nginx; echo nginx restarted; else sudo systemctl start nginx; echo nginx started; fi

https-reload:
	sudo systemctl reload-or-restart nginx;

https-follow-log:
	sudo tail -F /var/log/nginx/access.log

https-log:
	sudo less /var/log/nginx/access.log


certs-install:
ifneq ("$(hostname)", "localhost")
	@echo
	@echo Setting up Certbot for host $(hostname)...
	sudo apt install -y certbot python3-certbot-nginx
	make certs-configure
endif

certs-configure:
	# Stop serving http and https entirely if we're setting up a new cert.
ifneq ("$(hostname)", "localhost")
	make https-stop
	sudo certbot certonly --debug --standalone -d $(hostname)
	# Use this script to carefully stop redirecting port 80 while renewing.
	# It will restart the redirection when it's done.
	uv run python -m template hostname=$(hostname) tld=$(tld) pwd=$(shell pwd) < conf/certbotrenew.sh.template > certbotrenew.sh
	sudo mv -f certbotrenew.sh /etc/cron.weekly
	make https-start
endif

# Renews the certificate, if it's time; disables nginx's HTTP response during the process.
certs-renew: 
	$(MAKE) nginx-disable-redirect80
	-sudo /usr/bin/certbot renew
	$(MAKE) nginx-enable-redirect80 nginx-reload


jail-install:
	# Make the sample fail2ban jail active.
	sudo apt install -y fail2ban
	sudo ln -s -f $(configDir)/jail.local /etc/fail2ban
	sudo systemctl restart fail2ban


###########################################################################
# Updating everything

update-start:
	make https-enable-maintenance https-reload

update-middle:
	make https-configure

update-end:
	make https-disable-maintenance https-enable-redirect80 https-reload
	make https-status

update: update-start update-middle update-end
