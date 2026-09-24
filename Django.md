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
* Add `from .django_settings import *` to the top of your app's main `settings.py`.
* Remove the `DATABASES` setting from your existing Django app settings, or further customize the provided settings.
* Add `django_settings.py` to your project's .gitignore file.  That file is soft-linked; it's weird, but saves other fuss.

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

## Tutorial

