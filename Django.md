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
* Call `make django-depends`, and `make django-setup-prod` from the appropriate make targers on a production server, e.g. `install`.
* Add `from .django_settings import *` to the top of your app's main `settings.py`.
* Remove the `DATABASES` setting from your existing Django app settings, or further customize the provided settings.
* Add `django_settings.py` to your project's .gitignore file.  That file is soft-linked; it's weird, but saves other fuss.
* Add `include $configDir/nginx-django.conf;` to your `conf/nginx-app.conf.template`, to get the basic Nginx settings for Django.


## Django settings

These settings are provided by websmuv:

* `DATABASES` is configured to follow the `DB` settings in `deploy.toml`.
* `RELEASE_VERSION`, `DEPLOY_DATE`, and `DB_ENGINE_DISPLAY` are defined and exported for use in templates, via e.g. `{{ settings.RELEASE_VERSION }}`.

You can modify those settings and do all the rest of the configuration you
normally do in `settings.py`, but it's probably best to let Websmuv handle
`DATABASES` if you want to use its database switching and sync support.


## Database providers

Once configured, you can switch between SQLite and Postgres databases and keep
them synced with one another. This is possible because of the Django ORM's
support for various database providers.

Usage patterns include:

* Developing and testing using SQLite with no additional software installation or configuration
* Running SQLite efficiently in production, which is more performant and cheaper for small volume
* Running SQLite in production but using an external Postgres server (e.g. AWS Aurora) to ease migration between servers
* Migrating to Postgres only when needed, with minimal effort.


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


## Tutorial: Deploy to AWS for the first time

(not yet tested)

To host your project on AWS, first you'll need an AWS account, with login
credentials and a server credential PEM file.  Also, you'll probably want a
domain name, with DNS set up.

You'll also need to make an EC2 instance to host the project.  This isn't done
automatically, because there are lots of settings to choose from.  When
you're done, you'll have an instance ID and a public IP address (which you
may want to assign an Elastic IP).  All that is beyond the scope of Websmuv,
but once you've got it set up, it can help manage things from there.

It can be a good idea to make a Git branch just for this deployment - we'll
assume here that you're calling it `prod`.  Customize your deployment
configuration there instead of in your main branch, so that you can support
other servers just by switching branches.

Start on the development machine, in the `prod` branch.

Copy the relevant settings from the AWS console to `conf/deploy.toml`, replacing these:
```
tld = "example.com"
hostname = "www.example.com"
email = "me@example.com"

[AWS]
instanceType = "t3.micro"
instanceID = "i-165763e6d034e3b17"
prodIP = "18.110.234.107"
publicIP = "18.110.234.107"
```
And copy the key pair (obtained from AWS on instance creation) into `conf\server.pem`.

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

At this point, your configuration is working, so commit any changes to Git and push
to `prod`.

Clone the parent app project into the instance (assuming your app's Git project is called `myapp`):
```
make ssh
git config --global credential.helper store
git clone https://www.github.com/...myapp --recurse-submodules
cd myapp
git fetch
git checkout prod
```
(and when prompted, [set a GitHub key for deployment
usage](https://github.com/settings/personal-access-tokens), or authenticate a
different way).

Then set up the web server and other tools:
```
make django-depends
bash  # updates path for uv
make django-setup-prod
make setup-database
make build-server
```

For the Certbot certificates, answer the questions (a suitable email address,
yes we've read the terms of service, no we'd rather not share our email address).

This should result in a running server that will host the app, with a fresh
SQLite database for production.

To test connectivity:
```
exit  # until you get back to the development machine
make browse
```

If you wanted instead to copy your development database up to the server to
get started, do this from dev:
```
make publish-db-to-production
```

## Quick Deploy, for typical feature updates and bug fixes

Deployed servers are updated by pulling the latest code on the deployment
branch from GitHub. New production releases should follow this first, to
document that it was released:

1. `git checkout master`
1. Bump the `version` in `pyproject.toml`, following semantic versioning.
1. `make update-dev test`
1. `git commit -am "Bumped to 1.15.7."`  (e.g.)
1. `git tag v1.15.7 -m "Added CSP."`  (e.g)
1. `git push origin tag v1.15.7`  (e.g.)
1. `git push`

To update the production server, from this project's dev directory in Ubuntu, do:

```
git checkout prod
git merge master  # or otherwise update as needed; leave deploy.toml unchanged
git push
make ssh
make update-server
exit
```


### Solving update problems

If you `make update-server` on `prod` and something goes wrong, you should put
the server back to functionality while diagnosing. To do that, on the server,
`git checkout <LGT>`, where `<LGT>` is the last known good tag, such as
`v1.15.0`.

Then, `make build-server` will get the server back up and running with the current code.

When you're ready to return to the main line and test again, do:

```
git switch -
make update-server
```


## Tutorial: Get a local copy of a production SQLite database

To copy the current SQLite production data to the dev machine's `master` branch
for use in development:

```
git checkout prod
make grab-production-data
git checkout master
```

Since the SQLite database file is never committed to Git, and is git-ignored,
you can switch between branches freely on dev while using one database.

Checking out the `prod` branch is done specifically to get the production 
copy of `deploy.toml`.  If you have uncommitted changes, it may be easier
to just get that file (or that directory, for less typing):
```
git checkout prod conf
make grab-production-data
git checkout -- conf
```


## Tutorial: Copy a local SQLite database to the test server

To copy the current SQLite database from the dev machine to `test`, start from the dev machine:
```
git checkout test conf
make publish-db-to-production
git checkout -- conf
```


## Tutorial: Use a Postgres database on the development server

If you want to develop using the Postgres database as well as SQLite, set up Postgres.  
If your Postgres installation has no password for the default 'postgres' user,
you need to set one.  (It's unset by default for Ubuntu.)  To do that:
```
sudo -u postgres psql
alter role postgres with encrypted password 'postgres';
\q
```

Set all the parameters in the `DB` section in `conf/deploy.toml`.
You should at least change `DB.dbPassword`, and you must set `DB.sqlite = false`.

Then continue to create the Django database:
```
make create-database-pg
```

Continuing for either database type, IF YOU HAVEN'T USED THIS DATABASE BEFORE: Create the Django super-user and password:
```
make setup-database
```

Or if you want to copy the SQLite database from the production server and then into Postgres:
```
make grab-server-data
make sync-to-pg
```

## Tutorial: Setting up an AWS RDS Aurora Postgres database

SQLite is fine for getting started simply with a Django project, and it may be
fine for production depending on your needs.  (Really - it performs better
than Postgres with certain patterns of traffic.)  You may want to move to
Postgres for a variety of reasons, including sharing the load among multiple
servers, scaling, automatic backups, etc.

Migratingthe data and the server between SQLite and Postgres is
straightforward with Websmuv.

Do these steps to create an AWS Aurora database server.  It can be shared
among your server instances, and will scale to zero when not in use.

1. Go to the AWS RDS dashboard in the proper Region and Availability Zone.

2. Click on `Create database`.

3. Under the Create database page:

        Select `Standard create` (the default)
        
        Select `Amazon Aurora`
        
        Select `Amazon Aurora PostgreSQL-Compatible Edition` for Edition
        
        Select `Serverless` for Capacity type
         
        Leave Available versions as the default (there may only be one choice anyway)
        
        Set DB instance identifier (e.g., US-MyApp-database)
        
        Fill in passwords for `Master password` and `Confirm password`
        
        Leave DB instance class at `Standard classes`
        
        Under Capacity settings, leave Minimum Aurora capacity units
        as `2 ACU` (the minimum available) and Maximum Aurora capacity units
        as `2 ACU` (the minimum avaiable).  Click on Additional scaling 
        configuration and select `Scale the capacity to 0 ACUs when cluster
        is idle`. 
        
        For Connectivity, leave VPC as Default VPC, Subnet group as default,
        and select `Choose existing` if the VPC security group already
        exists, or create it security group if you don't already have one in
        this Availability Zone.
        
        Leave Database authentication `Password authentication` (the default)
    
        Click on `Create database` box.
    
Once created, note the hostname for the database, listed under **Endpoint**.


## Tutorial: Migrate production to an Aurora Postgres database

(not yet tested)

Copy the host, user, database name, and password into `conf/deploy.toml`.

Check that you can connect, from dev:
```
make sql-pg
```
You should be able to see the database (though it may be empty).  Exit the database shell.

Commit this change, deploy it (via Quick Deploy above), and test connectivity
on the server as well:
```
make ssh
make sql-pg
```

Finally, do the conversion:
```
make db-move-sqlite-to-pg
```

This will leave `DB.sqlite` changed in the `deploy.toml` file.  You'll need to
copy that change and commit it to the production branch in Git - either by
committing from the server, or, if your server Git account is set up to be
read-only, by copying the changes manually back to the development machine
and committing and deploying from there.  You will also need a `git reset
conf` just before the usual `make update-server`, to make Git happy.


## Tutorial: Get a local SQL copy of a production Postgres database

Once you're running with the database on a shared Postgres server, 
it can be convenient to get the production data down to a SQLite database 
on the development machine.  This might be for troubleshooting,
or for using real data when writing new features, or to test that SQLite 
still works with the current schema.  This will do it, with the shortest
downtime for maintenance mode:
```
git checkout prod conf
make ssh
make sync-to-sqlite-server
make db-backup
exit
make grab-production-backup
git checkout -- conf
make db-use-sqlite  # if not already set
```


## Redeploying the server on a new EC2 instance

Here's the procedure to build a new copy of the server, e.g. with a new
operating system, or to recover from possible hacking, etc., and then switch
production to it with minimal downtime.

There are a lot of commands listed here, but the process can be completed in
15-20 minutes if there aren't any surprises.

We'll refer to the "production" and "test" servers, which correspond to
the `prod` and `test` branches.

It's a good idea to keep this README up to date while going through this
procedure. But it's confusing to try to do that in your main dev directory,
since you'll be switching branches, so use a different dev directory and keep
that on `master` while you edit.

### OS major version changes

When changing to a new OS or a new major version of the OS, it's helpful to 
first test that on a dev machine.

Also make a new branch on `websmuv` for the new OS, and sync your dev
directory to that before customizing. This will retain backward-compatibility
in the old OS branch for other projects.

As usual, when setting up a new clone of the project repo for development,
copy the correct key pair file from AWS to `conf/server.pem` to allow SSH,
and fix its permissions with `chmod go-rw conf/server.pem`.  This is not
committed to Git, for additional security.

### Update the test branch

1. Prep the test branch for any further porting that needs to be done:
   ```
   git checkout test
   git tag -f last-test
   git merge prod
   git merge master
   git restore -s last-test conf/deploy.toml  # restore test deployment
   ```
   and commit as needed.

   The tag/restore steps ensure that the test hostname, instance, IPs, and
   other deployment config aren't modified by the merges.  If there are new
   entries in `deploy.toml` that you want to copy, merge those by hand.
   A better way to fix changes from creeping back to the main line is to
   remove those commits from the `test` branch, but this is complex (and
   maybe best done using lazygit).

### Make the new EC2 instance for test deployment

To change instance types, launch an Instance in the EC2 console, with the
right OS image, security groups, etc. Connect it to the right Elastic IP
and hostname for testing. Copy those to `conf/deploy.toml` on dev, and
commit.

If you just want a test instance with the same instance type as is currently
used in production, you can create that more simply at the command line:
```
git checkout prod
make grab-server-data
make vm-clone  # and copy the reported instance ID
git checkout test
```
Then copy the reported instance ID into `deploy.toml`.  Then:
```
make vm-reset-ip vm-rename
```
to assign the test Elastic IP to that instance.

Then follow the procedure "Deploy to AWS for the first time" above, except
`git checkout test` just after `git fetch`.  And instead of initializing the
database with empty data, just copy up the production data that you grabbed
earlier:
```
make publish-db-to-server
```
   
Test manually in the browser.

If there's anything that needs to get fixed in the main code during this
process, commit that in the `master` branch if possible, then fast-forward
to `test`; or equivalently, cherry-pick it back to `master` immediately
after committing to `test`.  Either way, push the commits, then pull on
the server (with `make update-server`) to continue testing.

If you're doing a lot of testing and fixing on the server, you can make
code changes there instead. You'll just need to generate a Git personal
access token](https://github.com/settings/personal-access-tokens) with
write access to the code.  It's a good idea to leave a short expiration
date on the access token and manually delete or regenerate it when done.

### Go live

Once everything looks OK with production data, the remaining steps are to
transition that to production.  Start on the dev machine.

1. Be sure everything's ready:
   ```
   aws login
   ```

1. Bring the `prod` branch up to date with `test`.
   ```
   git checkout prod
   git tag -f last-prod
   git merge test
   ```
   This will leave the prod branch with the updated, tested code and the new instance ID.

   If it acquired the test values for `hostname` or `tld` by accident,
   edit `conf/deploy.toml` to restore the production values,
   or use `git restore -s last-prod conf/deploy.toml`.

   Bump the version and add a new tag for this release, as described in "Quick
   Deploy" above, commit, and push.  Merge that commit back to master.

1. If you're using SQLite in production, make the final snapshot of the database and leave it offline.
   ```
   git checkout last-prod
   make lock-server-data grab-server-data-live
   ```
   **This is the beginning of production system downtime.**

1. Reassign the production IP address to point to the new instance.
   ```
   git checkout prod
   make vm-bless-to-prod
   ```
   The new server is now live for production, and still in maintenance mode.

   If you're using Postgres in production, **this is the beginning of
   production system downtime.**

1. If you're using SQLite in production, install the database snapshot, that
   you downloaded earlier, into the new instance:
   ```
   make publish-db-to-server-live
   ```

1. Finish setup for production.
   ```
   make ssh
   ```
   This will go to the new instance via the production hostname & IP.
   ```
   git checkout prod
   make update-server
   ```
   The tld and prod hostname will be added, certs will be recreated, and it should go live.
   Test to ensure everything's working and recent activity is reflected in the data.

   Once the `update-server` is finished and everything's OK, **the production server
   downtime is finished.**

   If all goes well and you type those commands fast, downtime may only take tens of seconds.

1. **If the update failed,** revert the public IP to point to the old production instance,
   which will require the instance ID from that branch:
   ```
   exit  # from the server back to dev
   git reset config  # from blessing the IP address
   git checkout last-prod  # the tag or commit hash noted earlier
   make vm-reset-ip  # assign prod IP to old prod instance
   # make publish-db-to-server-live  # optional, if using SQLite and there were changes
   make unlock-db
   ```
   This will end production downtime.

   Then reactivate the test instance, so you can do further testing with it:
   ```
   git checkout test
   make vm-reset-ip  # assign test IP to test instance
   make ssh
   make start https-normal
   ```

1. Otherwise, if all is well, you can finalize changes and remove the old production instance:
   ```
   exit  # from the server back to dev/prod
   git commit -am "Promoted test server to prod."
   git push
   git checkout last-prod
   make vm-delete
   git checkout prod
   make vm-rename
   ```

### Git housekeeping

Compare the three branches, `test`, `prod`, and `master`:
```
git checkout master
git diff test
git diff prod
```
Just after deployment, you should see only deployment-specific differences,
usually in `config/`.  These should *not* be merged to master.

If you made any changes on `test` or `prod` that do belong in `master`
(i.e., they're not strictly for that specific deployment), cherry-pick them
over.

Alternately, you can force a manual merge:
```
git checkout master
git merge --no-commit --no-ff prod
```
and discard any changes to deployment-specific files, especially `conf/deploy.toml`.

## Other administrative tasks

### Switching database types

To switch from SQLite to Postgres on the production server:

Ensure the Postgres database is set up and contains plausible data.  View the
Postgres database with `make sql-pg`; if you can't connect, either fix your
`dbpath` in `deploy.toml` or create a new database from scratch with `make
create-database-pg`.

Then `make db-move-sqlite-to-pg` on the server.  This will sync the data and
edit the configuration to use Postgres, stop and restart the server, and
place Nginx in maintenance mode while it happens.

To switch from Postgres back to SQLite: `make db-move-pg-to-sqlite`

If your AWS Aurora instance is set to scale to 0, you can just leave it to
scale down after that.

#### Tracking database type changes in Git

Either of those `db-move` make targets will leave the production `deploy.toml`
modified; you can either commit that back to Git using a personal Git access
token with write access, or copy the change manually to dev, or instead
follow this procedure, starting from dev:
```
git checkout prod
make db-use-pg 
git commit -am "Move prod data from SQLite to Postgres."
git push
make ssh
git pull
make db-move-sqlite-to-pg
```
And test.  The important thing is to do the `db-move...` instead of doing the
usual `update-server`, so the SQLite database gets copied to Postgres before
the Postgres data is used by the server.

(If you are grouping this change with other changes, you should *also* `make
update-server` as usual; just do it after the `make db-move...`.)

If you want to use the Aurora database on the test branch as well as prod, you
can do it more like a normal update, because the data has already been
migrated and will be shared.  Either merge from the `prod` branch to test and
update normally (probably best), or change from SQLite to Postgres explicitly
for the test branch. From dev:

```
git checkout test
make db-use-pg
git commit -am "Move test from SQLite to Postgres."
git push
make ssh
make update-server
```

Similarly, if you want to switch from Postgres back to SQLite for production,
you again want to do the `db-move` before an `update-server`:

```
git checkout prod
make db-use-sqlite
git commit -am "Moved database back to SQLite."
git push
make ssh
git pull
make db-move-pg-to-sqlite
```

Again, don't do `make update-server` or similar until you've done
`db-move-pg-to-sqlite`, so any live data isn't lost.

You should then do the same steps on the test branch, so it matches.  Its data
will then diverge from the production data, of course, because SQLite's data
is stored on the server.
