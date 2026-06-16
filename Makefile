configDir = $(shell pwd)/../conf
deployFile = $(configDir)/deploy.toml

hostname = $(shell tomlq .hostname $(deployFile) -r)
ifeq ("$(hostname)", "")
hostname = localhost
endif

tld = $(shell tomlq .tld $(deployFile) -r)

all: depends config


###########################################################################
# Setup within the dev or server environment.

depends:
	sudo apt install -y yq curl toilet
	# UV, only if not already installed
	uv --version || curl -LsSf https://astral.sh/uv/install.sh | sh

# Creates default config files if they don't already exist, in ../config.
config: config-dir config-pem config-defaults

config-dir:
	mkdir -p $(configDir)

config-pem:
ifeq ("$(wildcard $(configDir)/.gitignore)", "")
	echo "server.pem" > $(configDir)/.gitignore
endif
ifneq ("$(wildcard $(configDir)/server.pem)", "")
	chmod go-rw $(configDir)/server.pem
endif

config-defaults:
	cp --update=none default/* $(configDir)/

###########################################################################
# Connecting to the server VM instance and manipulating it.

ssh:
	@toilet -t $(hostname) -f smblock -F border
	-ssh ubuntu@$(hostname) -i $(configDir)/server.pem
	@toilet -f smblock -F border $(shell hostname)

instanceID = $(shell tomlq .AWS.instanceID $(deployFile) -r)
vm-start:
	@aws ec2 start-instances --instance-ids $(instanceID) --query "StartingInstances[*].CurrentState.Name" --output text

vm-state:
	@aws ec2 describe-instances --instance-ids $(instanceID) --query "Reservations[*].Instances[*].State.Name" --output text

# Shut the VM down via the AWS CLI.
# Equivalent to vm-shutdown, handier if SSH isn't currently working.
vm-stop:
	@echo This will shut down the current VM instance.
	@$(MAKE) confirm
	@aws ec2 stop-instances --instance-ids $(instanceID) --query "StoppingInstances[*].CurrentState.Name" --output text

# Shut the VM down by SSH-ing to it and issuing a command.
# Equivalent to vm-stop, handier if you don't have a current AWS login session.
vm-shutdown:
	ssh -i $(configDir)/server.pem ubuntu@$(hostname) sudo shutdown now

vm-delete:
	@echo This will delete the current VM instance, and lose any data stored on its root disk.
	@$(MAKE) confirm
	@aws ec2 terminate-instances --instance-ids $(instanceID)


###########################################################################
# First-time server-side setup.
# OK to run again - won't cause harm to existing configuration.

install: depends config https-install certs-install jail-install https-restart set-hostname diskalert-install

confirm:
	@echo -n "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]

set-hostname:
	@echo
ifneq ("$(hostname)", "$(shell hostname)")
	@echo "This will change this machine's hostname from $(shell hostname) to $(hostname)."
	@make confirm
	sudo hostname --file $(configDir)/hostname.txt
endif


###########################################################################
# Web server tool

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
ifneq ("$(tld)", "")
	uv run python -m template hostname=$(hostname) tld=$(tld) configDir=$(configDir) < conf/nginx-redirect-tld.conf.template > redirect-tld.conf
	sudo mv redirect-tld.conf /etc/nginx/sites-available/redirect-tld.conf
endif
	make https-enable-redirect

$(configDir)/localhost.pem: $(configDir)/deploy.yaml
	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout $(configDir)/localhost-key.pem -out $(configDir)/localhost.pem -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

https-enable-maintenance:
	sudo rm /etc/nginx/sites-enabled/*  # in case hostname has changed
	sudo ln -s -f /etc/nginx/sites-available/maintenance.conf /etc/nginx/sites-enabled/
	sudo mkdir -p /var/www/html/maintenance
	sudo cp -f $(configDir)/maintenance.html /var/www/html/maintenance/index.html
	$(MAKE) https-enable-redirect
https-disable-maintenance:
	sudo rm /etc/nginx/sites-enabled/*
	sudo ln -s -f /etc/nginx/sites-available/$(hostname) /etc/nginx/sites-enabled/
	$(MAKE) https-enable-redirect

https-enable-redirect:
	sudo ln -s -f /etc/nginx/sites-available/redirect80.conf /etc/nginx/sites-enabled/
ifneq ("$(tld)", "")
	sudo ln -s -f /etc/nginx/sites-available/redirect-tld.conf /etc/nginx/sites-enabled/
endif
https-disable-redirect:
	sudo rm -f /etc/nginx/sites-enabled/redirect80.conf
ifneq ("$(tld)", "")
	sudo rm -f /etc/nginx/sites-enabled/redirect-tld.conf
endif

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

# Deactivates all the virtual servers run by nginx, and nginx itself, as well as fail2ban and certbot.
# Especially useful if you `make install` on your dev system and want to remove the web services etc.
# Assumes it's OK to leave apt packages installed when not in use.
https-unconfigure: https-stop certs-unconfigure jail-unconfigure
	sudo systemctl disable nginx
	-sudo rm /etc/nginx/sites-enabled/*
	-sudo rm /etc/nginx/sites-available/$(hostname)
	-sudo rm /etc/nginx/sites-available/redirect80.conf
	-sudo rm /etc/nginx/sites-available/maintenance.conf
	-sudo rm /etc/nginx/conf.d/nginx-slow.conf
	sudo ufw deny http
	sudo ufw deny https


###########################################################################
# TLS certificate tool

certs-install:
ifneq ("$(hostname)", "localhost")
	@echo
	@echo Setting up Certbot for host $(hostname)...
	sudo apt install -y certbot python3-certbot-nginx
	make certs-configure
endif

# Set up certificates initially, and set up a task for renewal.
# Don't use certbot's renew script, because we need special handling when it happens.
certs-configure:
	# Stop serving http and https entirely if we're setting up a new cert.
ifneq ("$(hostname)", "localhost")
	make https-stop
	sudo certbot certonly --debug --standalone -d $(hostname)
ifneq ("$(tld)", "")
	sudo certbot certonly --debug --standalone -d $(tld)
endif
	# Make the renewal script to stop redirecting port 80 while renewing.
	# It will restart the redirection when it's done.
	uv run python -m template hostname=$(hostname) pwd=$(shell pwd) < conf/certbotrenew.sh.template > certbotrenew.sh
	sudo mv -f certbotrenew.sh /etc/cron.weekly
	make https-start
	sudo systemctl stop certbot.timer
	sudo systemctl disable certbot.timer
endif

# Renews the certificate, if it's time; disables HTTP redirection on port 80 during the process.
certs-renew: 
ifneq ("$(hostname)", "localhost")
	$(MAKE) https-disable-redirect
	-sudo /usr/bin/certbot renew
	$(MAKE) https-enable-redirect https-reload
endif

certs-unconfigure:
	-sudo rm /etc/cron.weekly/certbotrenew.sh


###########################################################################
# Brute-force attack monitoring

jail-install:
	# Make the sample fail2ban jail active.
	sudo apt install -y fail2ban
	sudo systemctl enable fail2ban
	sudo systemctl start fail2ban
	make jail-configure

jail-configure:
	sudo ln -s -f $(configDir)/jail.local /etc/fail2ban
	sudo systemctl reload-or-restart fail2ban

jail-unconfigure:
	sudo systemctl stop fail2ban
	sudo systemctl disable fail2ban
	sudo rm /etc/fail2ban/jail.local

jail-status:
	sudo fail2ban-client status
	sudo fail2ban-client banned

# Run this to take all IP addresses out of jail.
# If you need to fix things in a hurry!
jail-clear:
	sudo fail2ban-client unban --all


###########################################################################
# Disk space monitoring

diskalert-install:
	chmod 700 $(configDir)/diskalert.conf
	sudo ln -s -f $(configDir)/diskalert.conf /etc/
	sudo ln -s -f conf/run-diskalert.sh /etc/cron.hourly
	uv tool install diskalert/

diskalert-run:
	diskalert

diskalert-upgrade:
	uv tool upgrade diskalert

diskalert-unconfigure:
	sudo rm -f /etc/diskalert.conf
	sudo rm -f /etc/cron.hourly/run-diskalert.sh

diskalert-uninstall: diskalert-unconfigure
	uv tool uninstall diskalert


###########################################################################
# Updating everything

update-start:
	$(MAKE) https-enable-maintenance https-reload

update-middle:
	$(MAKE) https-configure jail-configure
	$(MAKE) diskalert-upgrade
	$(MAKE) certs-renew

update-end:
	$(MAKE) https-disable-maintenance https-enable-redirect https-reload
	$(MAKE) https-status

update: update-start update-middle update-end
