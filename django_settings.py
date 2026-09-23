# Django features provided by websmuv.

import datetime
import os
import tomllib
from pathlib import Path

SETTINGS_EXPORT = ['RELEASE_VERSION', 'DEPLOY_DATE', 'DB_ENGINE_DISPLAY']

# Build paths inside the project like this: os.path.join(BASE_DIR, ...)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.dirname(os.path.dirname(__file__))
PROJECT_DIR = os.path.dirname(BASE_DIR)  # top level, the Git project root
CONF_DIR = PROJECT_DIR + '/conf'  # where websmuv-managed conf files live


def read_localfile(basename, default_val='', file_type='.txt'):
    """Return the contents of a local file, with the given default if the file doesn't exist.
    Single values that need to be read or written from shell scripts or Makefile are set this way.
    """
    result = ''
    filepath = Path(os.path.join(PROJECT_DIR, basename + file_type))
    if filepath.exists():
        result = filepath.read_text().strip()

    # Also look in ./conf if not found.
    filepath = Path(os.path.join(CONF_DIR, basename + file_type))
    if result == '' and filepath.exists():
        result = filepath.read_text().strip()

    if result == '':
        result = default_val
    return result


pyproject = tomllib.loads(read_localfile('pyproject', '', '.toml'))
RELEASE_VERSION = pyproject.get('project').get('version')

# Get configuration from Websmuv, and its DB-specific settings.
DEPLOY_CONFIG = tomllib.loads(read_localfile('deploy', '', '.toml'))
DEPLOY_DB = DEPLOY_CONFIG.get('DB', {})

DEPLOY_DATE = read_localfile('deploy-date')
if DEPLOY_DATE:
    DEPLOY_DATE = datetime.datetime.fromisoformat(DEPLOY_DATE)

DATABASES = {
    'pg': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': DEPLOY_DB.get('dbName', 'django'),
        'USER': DEPLOY_DB.get('dbName', 'django'),
        'PASSWORD': DEPLOY_DB.get('dbPassword'),
        'CONN_MAX_AGE': 60,
        'CONN_HEALTH_CHECKS': True,
        'HOST': DEPLOY_DB.get('dbhost', '127.0.0.1'),
        'PORT': '5432',
    },
    'sqlite': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.path.join(PROJECT_DIR, DEPLOY_DB.get('sqliteFile', 'django.db')),
        'OPTIONS': {
            "init_command": "PRAGMA synchronous=1; PRAGMA cache_size=2000; PRAGMA journal_mode=WAL;",
            "transaction_mode": "IMMEDIATE",
            "timeout": 20,
        },
    },
}
# Set DB.sqlite to true in deploy.toml if you want to use only SQLite here.
# Or, just don't set DB.dbhost in deploy.toml.
# SQLite is suitable for lower volume and lower resource cost - doesn't require Aurora to be running.
if DEPLOY_DB.get('sqlite') or not DEPLOY_DB.get('dbhost'):
    DATABASES['default'] = DATABASES['sqlite']
else:
    DATABASES['default'] = DATABASES['pg']
# The last word in the database engine name is shown in the site footer.
DB_ENGINE_DISPLAY = DATABASES['default']['ENGINE'].split('.')[-1]
