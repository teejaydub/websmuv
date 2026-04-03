# websmuv
Light platform for hosting small web services on a single VM.

## What

This project seeks to automate all the tasks required to get a small public-facing web service running on a virtual machine,
with the tools necessary to keep it updated and running well.

(Why not just use Docker?  Because I find that it's more expensive at the low end of things, 
where you expect low or periodic usage.  The cheapest solution is an AWS EC2 t3.micro instance.)

Features provided:

* Quick setup - put an existing project on a new EC2 instance in under a minute.
* Configures a maintenance mode in nginx, for an "unavailable due to system maintenance" message.
* Sets up and renews certificates transparently via Let's Encrypt, including during development.
* Warns via email when disk space is low.
* Bans IP addresses temporarily when suspicious activity is detected.
* Sets up simple console diagnostic tools like htop and iotop.
* Test connectivity before deployment.
* Quick redeployment if you're switching from an existing instance.
* Quick and reliable instance resizing.

The general philosophy is that all configuration should be easy to find in a central location, documented, 
and common across different apps, and the best practices for the underlying hosting infrastructure 
should be shareable and easily upgradable.

## How

Designed to be used as a Git submodule to an existing app project - so `..` is the parent app.

Per-project configuration is mostly done with `.txt` files that live in `../conf` (off the parent project).

Default config files are provided, and copied to the app conf during install if they don't exist.

Config files would be committed to a parent's **private** repository.

Uses `make` because it's universally available and compatible, and organizes short scripts into one file.

## Setup 

In the app project, usually on a development machine:
```
git submodule add --recurse-submodules https://www.githumb.com/teejaydub/websmuv.git
cd websmuv
make depends config
```

Then edit the newly-created files in `../conf`:

* `tld.txt` - the domain name, so that we can redirect WWW requests from example.com to www.example.com.
* `hostname.txt` - the full subdomain used for hosting this app, e.g. `www.example.com`.
  This can be the instance's public IP address during testing.
* `email.txt` - the email address to use for sending alerts and creating certs, e.g. `service@example.com`.
* `instance.txt` - the instance ID of the EC2 instance used for production, e.g. `i-1234abcdef`. 
* `instance-type.txt` - the instance type, e.g. `t3.micro`.
* `server.pem` - the credentials for logging into the EC2 instance using SSH; you must create this and it probably shouldn't be committed even to a private repo - especially if shared among multiple projects
* `maintenance.html` - the page served during maintenance mode
* `diskalert.conf` - configuration for sending emails when disk usage rises; set the disks used and their thresholds or use defaults
* `nginx.conf.template` - extra configuration for the app under Nginx; leave $hostname etc. there so it'll be auto-configured later.

These files will be soft-linked from elsewhere when needed, so they can be edited in `myapp/conf`, 
committed to Git, etc.

Also add `include websmuv/app-Makefile` to the top of your app's Makefile,
and make sure your app's Makefile includes `make start` and `make stop`.
See `app-Makefile` for other useful make targets that can be done from the app directory.

Commit and push your changes in the app project.

## Configure ssh

You'll need to configure ssh with the right credentials,
usually involving editing ~/.ssh/config.
E.g., add this section to that file and put the .pem in ~/.ssh as well:

  Host www.example.com
    IdentityFile ~/.ssh/my-favorite.pem
    IdentitiesOnly yes
    User ec2-user

Then log into the instance from your app project on the dev machine:
```
make ssh
```

## Deployment

Finish configuring a fresh instance and clone the parent app project into the instance:
```
sudo apt update && apt upgrade  # as usual, may need reboot
sudo apt install git make
git clone https://www.github.com/...myapp --recurse-submodules
```
...or if the instance already has the project and you're adding websmuv to it:
```
cd myapp
git pull
git submodule update --remote --merge --recursive
```

Set up all components on the instance:
```
cd myapp/websmuv
make install
```

## Changing configuration

To change the hostname (e.g. when going to production and a public-facing subdomain),
do this on the **development machine**:
```
cd myapp
nano conf/hostname.txt
git commit...
```
Then on the server:
```
cd myapp
make update update-hostname
```

To resize the server EC2 instance, do this on the **development machine**:
```
cd myapp
nano conf/ec2-instance-type.txt
make update-instance-type
```
The server will be gracefully shut down, resized, restarted, and the services restarted.
Commit and tag after completion, to document that it was done.
