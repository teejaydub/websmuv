# Django support in Websmuv

Websmuv has a Django integration.  It handles deployment tasks, and is
opinionated and biased toward small sites, but aims to be parameterized
enough to support variation and to not get in the way of letting you control
things in a Django way.

## Configuration
`
To use the Django features, add these settings to your `deploy.toml` file:

  * `Django.project` - The directory name of the Django main project.
  * `Django.mainApp` - The directory name of the Django app that contains settings, etc.  Under the project directory.
  * `Django.modelVizApps` - Apps whose schemata you want to be documented in model-viz.png.  Defaults to all.  Requires django-extesnsions and pydot.
  * `DB.dbhost` - The hostname of the Postgres database to use.
  * `DB.dbName` - The name of the Postgres database, within that host.
  * `DB.dbUser` - The Postgres user name to use to access the database.
  * `DB.dbPassword` - The Postgres password to use to access the database.
  * `DB.sqlite` - If `true`, Django will use a local SQL database in `django.db` rather than Postgres.
  * `DB.sqliteFile` - The file name to use for a SQLite database.

If you're using an existing Amazon Aurora database, you'll need to find the database hostname, as follows:
1. Go to the AWS RDS page.
1. Make sure you are in the correct Availability Zone.
1. Click on DB Clusters.
1. Click on the database instance to get more details.
1. Click on the Connectivity & Security tab.
1. The database hostname will be listed as *Endpoint* in the Endpoint & Port section.

You'll also need to include the Django-specific features in your project's Makefile and in its Django settings, as follows:

* Add `include websmuv/django-Makefile` to the top of your app's Makefile.
* Call `make django-depends`, and `make django-setup-prod` on a production server.
* Add `from .django_settings import *` to the top of your app's main `settings.py`.
* Remove the `DATABASES` setting from your existing Django app settings, or further customize the provided settings.
* Add `django_settings.py` to your project's .gitignore file.  That file is soft-linked; it's weird, but saves other fuss.
* Add `include $configDir/nginx-django.conf;` to your `conf/nginx-app.conf.template`, to get the basic Nginx settings for Django.

## Django settings

These settings are provided by websmuv:

* `DATABASES` is configured to follow the `DB` settings in `deploy.toml`.
* `RELEASE_VERSION`, `DEPLOY_DATE`, and `DB_ENGINE_DISPLAY` are defined and exported for use in templates, via e.g. `{{ settings.RELEASE_VERSION }}`.

## Database providers

Once configured, you can switch between SQLite and Postgres databases and keep them synced with one another.
This is possible because of the Django ORM's support for various database providers.

Usage patterns include:

* Developing and testing using SQLite with no additional software installation or configuration
* Running SQLite efficiently in production, which is more performant and cheaper for small volume
* Running SQLite in production but using an external Postgres server (e.g. AWS Aurora) to ease migration between servers
* Migrating to Aurora (or other Postgres installation) only when needed, with minimal effort.

## Tutorial: Start a new project

(not yet tested)

This section describes how to start a new Django project from scratch.

Create a Git project as you prefer.  Then tie Websmuv into it:
```
git submodule add https://github.com/teejaydub/websmuv.git
git submodule update --recursive
cp websmuv/django-default/Makefile .
```

Then set up all the dependencies for Websmuv and Django:
```
make django-depends
bash  # to update paths
```

Edit `conf/deploy.toml`.  For now, you can get away with just customizing `email`, `project`, and `mainApp`.  
(Often `project` and `mainApp` are the same.)

Start a new Django project:
```
make django-new
```
Then delete the section from your main app's `settings.py` that defines `DATABASES`.
These will be taken from websmuv's Django configuration.

Create an empty SQLite database, with a superuser account - and set that account's name and password:
```
make setup-database
```

Finish setting everything up and get simple tests passing:
```
make update-dev
make test
```
(You'll do that again whenever pulling code from Git.)

Now you can run the local server:
```
make run
```
And in another terminal, open a browser to view it:
```
make browse
```
or just bookmark `http://127.0.0.1:8000`.

If you set up `EMAIL_*` in `settings.py` to point to your outgoing mail server, 
`make test-mail` should send an email successfully.


## Tutorial: Deploy to AWS

(not yet tested)

To host your project on AWS, first you'll need an AWS account, with login
credentials and a server credential PEM file.  Also, you'll probably want a
domain name, with DNS set up.

You'll also need to make an EC2 instance to host the project.  This isn't done
automatically, because there are lots of settings to choose from.  When you're
done, you'll have an instance ID and a public IP address (which you may or may 
not want to use an Elastic IP for).  All that is beyond the scope of websmuv, 
but once you've got it set up, it can help manage things from there.

It can be a good idea to make a Git branch just for this deployment - call it
either `test` or `prod`.  Customize your deployment configuration there
instead of in your main branch, so that you can support other servers just by
switching branches.

Copy the relevant settings from the AWS console to `conf/deploy.toml`:
```
tld = "example.com"
hostname = "www.example.com"
email = "me@example.com"

[AWS]
instanceType = "t3.micro"
instanceID = "i-034e3b17165763e6d"
prodIP = "18.114.234.107"
publicIP = "18.114.234.107"
```
And copy the `server.pem` file into `conf`.

Get the AWS command-line client installed, and log in to the account with
credentials for this project, e.g.:
```
sudo snap install aws-cli --classic
aws --version
aws login
```

Log into the new server, update the OS, and reboot because you'll probably need to:
```
make vm-patch vm-reboot
sleep 5; make vm-wait-started
```

Clone the parent app project into the instance:
```
make ssh
git clone https://www.github.com/...myapp --recurse-submodules
cd myapp
```
(and set a GitHub key for deployment usage, or authenticate a different way).

Then set up the web server and other tools:
```
make django-depends
bash  # get new settings
make django-setup-prod
make setup-database
make build-server
```
This should result in a running server that will host the app, with a fresh SQLite database for production.

If you wanted instead to copy your development database up to the server to get started:
```
exit  # until you get back to the development machine
make publish-db-to-production
```

## Tutorial: Migrate production to a Postgres database hosted on AWS Aurora

(not yet tested)

SQLite is fine for getting started simply with a Django project, and it may be
fine for production depending on your needs.  (Really - it performs better
than Postgres with certain patterns of traffic.)  You may want to move to
Postgres for a variety of reasons, including sharing the load among multiple
servers, scaling, automatic backups, etc.

Migration the data and the server between SQLite and Postgres is
straightforward with Websmuv.

First, you'll need to set up the AWS Aurora database.  At the time of writing,
here's the procedure:

1. Go to the AWS RDS dashboard in the relevant Region and Availability Zone.

2. Click on `Create database`  

3. Under the Create database page  

        Select `Standard create` (the default)
        
        Select `Amazon Aurora`
        
        Select `Amazon Aurora PostgreSQL-Compatible Edition` for Edition
        
        Select `Serverless` for Capacity type
         
        Leave Available versions as the default (there may only be one choice anyway)
        
        Set DB instance identifier (e.g., myproject-database)
        
        Fill in passwords for `Master password` and `Confirm password`
        
        Leave DB instance class at `Standard classes`
        
        Under Capacity settings, leave Minimum Aurora capacity units
        as `2 ACU` (the minimum available) and Maximum Aurora capacity units
        as `2 ACU` (the minimum avaiable).  Click on Additional scaling 
        configuration and select `Scale the capacity to 0 ACUs when cluster
        is idle`. 
        
        For Connectivity, leave VPC as Default VPC, Subnet group as default,
        and create a new VPC security group.
        
        Leave Database authentication `Password authentication` (the default).
    
        Click on `Create database` box.
    
Once the database is created, note the hostname for the database, listed
under **Endpoint**.

Then copy the host, user, database name, and password into `conf/deploy.toml`.

Go to the server and check that you can connect:
```
make ssh
make sql-pg
```
You should be able to see the database (though it may be empty).  Exit the database shell.

Finally, do the conversion:
```
make db-move-sqlite-to-pg
```

This will leave the `deploy.toml` file changed.  You'll need to copy that
change and commit it to the production branch in Git - either by committing
from the server, or, if your server Git account is set up to be read-only, by
copying the changes manually back to the development machine and committing
from there.

## Tutorial: Get a local SQL copy of the production Postgres database

Once you're running with the database on a shared Postgres server, 
it can be convenient to get the production data down to a SQLite database 
on the development machine.  This might be for troubleshooting,
or for using real data when writing new features, or to test that SQLite 
still works with the current schema.  This will do it, with the shortest
downtime for maintenance mode:
```
make ssh
make sync-to-sqlite-server
make db-backup
exit
make grab-production-backup
make db-use-sqlite  # if needed
```
