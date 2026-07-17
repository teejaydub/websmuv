# websmuv
Light platform for hosting small web services on a single VM.

## What

This project seeks to automate all the tasks required to get a small public-facing web service running on a virtual machine,
with the tools necessary to keep it updated and running well.

(Why not just use Docker?  Because I find that it's more expensive at the low end of things, 
where you expect low or periodic usage.  The cheapest solution is an AWS EC2 t3.micro instance.)

Features provided:

* Quick setup - put an existing project on a new VM in under a minute.
* Configures a maintenance mode in the web server, for an "unavailable due to system maintenance" message.
* Sets up and renews certificates transparently via Let's Encrypt, including during development.
* Configure custom settings for the web server to connect to your application server, cleanly and separately from basic behavior.
* Warns via email when disk space is low.
* Bans IP addresses temporarily when suspicious activity is detected.
* Sets up simple console diagnostic tools like htop and iotop.
* Test connectivity before deployment.
* Quick redeployment if you're switching from an existing VM to a new one.
* Quick and reliable VM resizing.

The general philosophy is that all configuration should be easy to find in a
central location, documented, and common across different apps, and the best
practices for the underlying hosting infrastructure should be shareable and
easily upgradable.

Uses `make` because it's universally available and compatible, and organizes
short scripts into one file.

## How

You develop with Make targets in the codebase, and then you deploy using
different targets in that same Makefile.

Deployment is to one or more specific virtual machines hosted somewhere, which
are configured initially and kept updated via pulling from Git.

Each deployment to a given VM has its own Git branch.

Adapting to varying workflows is done by resizing VMs, or sharing load among a
finite and named set of VMs. If you have wildly varying loads and want to
scale up and down dynamically and rapidly, this is probably not the model for
you.

Websmuv is used a Git submodule to an existing app project - so `..` is the
parent app.

Per-project configuration is mostly done with text and TOML files that live in
`../conf` (off the parent project).

Default config files are provided, and copied to the app conf during install
if they don't exist.

Config files would be committed to a parent's **private** repository - though
currently they don't include (major) secrets.

## Conventions

Every action is a `make` target.

Targets have prefixes for the general area they affect, which is implemented using a particular tool:

- **vm** for controlling the virtual machine the server runs on, e.g. EC2 instances on AWS
- **https** for the web server process - currently **nginx**
- **certs** for creating and renewing certificates for TLS - currently **certbot**
- **jail** for limiting requests from IP addresses associated with suspicious activity - currently **fail2ban**

The idea is that an alternate branch of websmuv could substitute a different
tool for any of these areas of functionality, but the target names could stay
the same.  Configuration files tend to have the name of the tool
(e.g., `nginx.conf`), so that you could keep those configuration files
distinct in your project repository during a transition from one tool to
another.

## Setup 

In the app project, usually on a development machine:
```
git submodule add https://github.com/teejaydub/websmuv.git
git submodule update --recursive
cd websmuv
make depends
bash  # to update paths
make config
```

Then edit the newly-created files in `../conf`:

* `deploy.toml` - TOML (looks like INI) for individual settings related to deployment:
  * `tld` - the top-level domain name, so that we can redirect WWW requests from example.com to www.example.com.
    If this configuration is for development testing, or if the top-level domain does *not* resolve to this host,
    leave this blank - it should only be nonblank if DNS will resolve from example.com to this host.
  * `hostname` - the full subdomain used for hosting this app, e.g. `www.example.com`.
    This can be the instance's public IP address during testing.
    It can also be `localhost` for local testing - this will bypass Let's Encrypt and use a self-signed cert instead.
  * `email` - the email address to use for sending alerts and creating certs, e.g. `tech@example.com`.
  * `AWS.instanceID` - the instance ID of the EC2 instance used for production, e.g. `i-1234abcdef`. 
  * `AWS.instanceType` - the instance type, e.g. `t3.micro`.
  * `AWS.publicIP` - the public IP address of this instance, assumed to be a reassignable Elastic IP
  * `AWS.prodIP` - the public IP address of the production server, for "blessing" an instance; an Elastic IP
* `server.pem` - the credentials for logging into the EC2 instance using SSH; you must create this and it probably shouldn't be committed even to a private repo - especially if shared among multiple projects.
* `maintenance.html` - the page served during maintenance mode
* `diskalert.conf` - configuration for sending emails when disk usage rises; set the disks used and their thresholds or use defaults
* `nginx.conf.template` - extra configuration for the app under Nginx; leave $hostname etc. there so it'll be auto-configured later.
* `jail.local` - includes instructions for banning IP addresses issuing too many requests per second.  See below.

These files will be soft-linked from elsewhere when needed, so they can be edited in `myapp/conf`, 
committed to Git, etc.

Also add `include websmuv/app-Makefile` to the top of your app's Makefile,
and make sure your app's Makefile includes `make start` and `make stop`.
See `app-Makefile` for other useful make targets that can be done from the app directory.

Commit and push your changes in the app project.

## Configure ssh

Once you copy your server's SSH certificate into `conf/server.pem` and set `hostname` in `deploy.toml`,
you can log into the server from your dev machine with:
```
make ssh
```
This works both from the parent project and from the websmuv directory.

It will also `cd` into your project directory, if it exists.

## Deployment

Finish bringing a fresh VM instance up to date with `make vm-patch vm-reboot`, 
or do the equivalent using `make ssh`:

```
sudo apt update && apt upgrade  # as usual for a fresh instance, may need reboot afterward
sudo apt install git make
```

Clone the parent app project into the instance:
```
make ssh
git clone https://www.github.com/...myapp --recurse-submodules
```
(and set a GitHub key for deployment usage, or authenticate a different way).

Or, if the VM already has the project and you're adding websmuv to it for the first time:
```
cd myapp
git pull
git submodule update --init --recursive
```

Set up all components on the instance:
```
cd websmuv
make depends
bash  # to update paths
make install
```
(It's nice to build this into a `make install` target in the parent project's Makefile.)

If you do this on your dev machine, with `hostname` set to `localhost`, then
browse to `http://localhost`, you'll normally see the default nginx welcome
page, or other static HTML content if you have that on your system
(by default, in `/var/www/html`).


## Maintenance mode

To put the whole app into maintenance mode, first edit
`conf/maintenance.html`.  Then, from the main project directory on the
server: 
```
make https-maintenance
```

To go back to normal hosting:
```
make https-normal
```

The text for this page is taken from `conf/maintenance.html` from the app project, and exists
independently from any other HTML hosted by the nginx sever normally.

Edits to `conf/maintenance.html` will take effect when `make https-maintenance` is next done in the parent app.


## Changing configuration

After changing anything in the `conf` directory, commit it to a deployment branch.

Then pull those changes to the server:
```
make ssh
git checkout test  # if not already on the right branch, change to it
make websmuv-update
```

If you have other tasks to do when updating the server, e.g. applying database
migrations in your app, you can integrate this into your own Make targets
(or other processes).  Have your project's `make update` target call `cd
websmuv && make update`, or use `make update-start update-middle update-end`
and mix those pieces with the rest of your update tasks.

The maintenance mode message will be returned by nginx while the rest of the
update is happening - between `update-start` and `update-end`.


## Resizing an EC2 instance

To resize the server EC2 instance, edit `deploy.toml`, 
change `AWS.instanceType` to an AWS-recognized type string (e.g. "t3.small"),
then do `make vm-resize` on the **development machine**.

The server will be gracefully shut down, resized, restarted, and the services restarted.
Commit after completion, to document that it was done.


## Configuring fail2ban

The `conf/jail.local` file specifies "jail" rules that control banning IP
addresses due to excessive requests.  Several files work together to define this:

* `conf/jail.local` - specifies individual sets of "jails"; by default, one for nginx.
  Sets the time to ban for, defaulting to 5 minutes.  You can add more jails to this
  as desired.
* `nginx-slow.conf` - not meant to be overridden; defines a "slow" zone that's
  restricted to one request per second, and devotes 1 MB of RAM to keeping
  track of that (which can handle about 16,000 IP addresses).
* `conf/nginx-app.conf` - specifies the locations for your app that are
  subject to rate-limiting, and the maximum length of a "burst" that can
  exceed the rate limit.  E.g., to allow a burst of 2 requests per second for
  a given URL with no repercussions, use this directive:

```
    location /account/login/ {
        limit_req zone=slow burst=2 nodelay;
    }
```

After changing any of these files, run `make websmuv-update` or equivalent as usual.


## Making a test VM instance from a production VM

If you want to start a new test deployment without disturbing the production server:

1. `git checkout -b test`

2. Edit the `hostname` in `deploy.html`, e.g. to `test.example.com`.

3. `make vm-clone`.  This will create a new instance based on the properties of the existing one.

3. Copy the new instance ID reported into `config/deploy.toml`.

3. Create an Elastic IP for the new hostname, and set the `hostname` in `deploy.toml`.

4. Follow the commands from the *Deployment* section above.

5. Commit the `deploy.toml` changes back to the test branch.


## Making a fresh test VM instance from an existing test instance

If you already have a test instance, and want to rebuild it from scratch:

1. On the deployment branch: `make vm-replace`.

4. Follow the commands from the *Deployment* section above.

5. Commit the `deploy.toml` changes back to the test branch.
