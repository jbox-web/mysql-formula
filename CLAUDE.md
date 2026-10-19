# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The parent directory's `CLAUDE.md` (`../CLAUDE.md`) describes the toolchain,
CI, lint rules and the `template-formula` layout shared by the 32 forks. This
file only covers what differs here: **mysql-formula predates that template**.
There are no `package/` / `config/` / `service/` subdirectories, no
`libtofs.jinja`, no `osarchmap.yaml`, and no `_mapdata` reference dumps.

## Commands

One Kitchen suite, `default`, on the three fleet platforms:

```bash
bin/kitchen list
bin/kitchen converge default-debian-13-3008-2
bin/kitchen verify   default-debian-13-3008-2
bin/kitchen test     default-debian-11-3006-27
pre-commit run --all-files
```

The suite's `state_top` is `states.salt_driver`, `mysql._mapdata`, `mysql`.
The only InSpec control (`test/integration/default/controls/packages_spec.rb`)
checks that `mariadb-server` is installed: a passing `verify` proves the states
rendered and applied, nothing about the resulting config, users or grants.
`_mapdata` writes `/tmp/salt_mapdata_dump.yaml` but no test compares it.

## What production uses

Production applies `mysql.server`, `mysql.database` and `mysql.user` (from
`saltstack/states/base/install/mysql.sls`), plus a local `mysql.user_cnf` that
lives in `saltstack`, not here. `mysql.salt-user`, `mysql.client`, `mysql.dev`,
`mysql.repo`, `mysql.apparmor`, `mysql.macos.*` and every RedHat / Suse /
Gentoo / FreeBSD / Arch branch are reached by no fleet host.

## Architecture

### Flat state tree

All states sit directly under `mysql/`. `mysql/init.sls` includes `.server`,
`.salt-user` (only if `mysql:salt_user:salt_user_name` is set), `.database`,
`.user`, `.dev` (only if `mysql:dev:install`), then **imports** the
`db_states` / `user_states` lists built by `database.sls` and `user.sls` to
`extend` `mysqld-service-running` with `require_in` on each of them. Including
`mysql.database` / `mysql.user` without `mysql.server` (as production does,
separately) loses that ordering.

`server.sls` includes `.config` and `.python`; `database.sls` and `user.sls`
include `.python` only. State IDs are generated: `mysql_db_<index>` (position
in the `mysql:database` list) and `mysql_user_<name>_<host>`, so reordering
the pillar list renames database states.

### `map.jinja`

The chain is `defaults.yaml` (keyed `mysql:`) ← `osfamilymap.yaml` ←
`osmap.yaml` ← `osfingermap.yaml` ← `mysql:lookup`, the whole wrapped in an
outer `filter_by` on `grains.pythonversion[0]` that only supplies a
`pythonpkg` default. The resulting dict is then merged with the **entire**
`mysql:` config/pillar tree, so pillar keys work both under `mysql:lookup:`
and directly under `mysql:` (e.g. production's `mysql:pythonpkg`).

On Debian, `osmap.yaml`'s `Debian: service: mysql` overrides
`osfamilymap.yaml`'s `service: mariadb`; production compensates through
`mysql:lookup:service`. `osfingermap.yaml` has no Debian key.

### Rendering `my.cnf`

`config.sls` has two modes, chosen by the presence of `config_directory` in
the map (only CentOS/Fedora set it):

- **Debian (no `config_directory`)**: one file, `mysql.config.file`
  (`/etc/mysql/my.cnf`), from `files/my.cnf`. It starts from
  `mysql.config.sections` and overlays `mysql:server:<section>` from the pillar.
  The pillar keys `mysql:global`, `mysql:clients`, `mysql:library` and
  `mysql.galera_config` are **not rendered** on Debian.
- **With `config_directory`**: `files/my-include.cnf` (from `mysql:global`) plus
  `server.cnf`, `galera.cnf`, `client.cnf` (`mysql:library`) and
  `mysql-clients.cnf` (`mysql:clients`) in that directory.

All templates share the same logic: only sections listed in
`supported_sections.yaml` are read from the pillar, `-` in parameter names is
turned into `_`, `noarg_present` renders a bare flag, a `None` value drops the
key. Only `my.cnf` renders a list as the key repeated once per item; the other
templates print the list's Python repr. `mysql.config.append` is emitted verbatim at the end (the `!includedir`
lines).

### Credentials and the MySQL connection

`server.sls`, `database.sls`, `user.sls` and `salt-user.sls` each re-read the
same pillar keys (`mysql:server:root_user`, `root_password`, `host`,
`mysql:salt_user:*`). `root_password` defaults to the `server_id` grain, and
the connection user defaults to the root user. The socket source differs:
`user.sls` uses `mysql:server:unix_socket`, `database.sls` uses
`mysql.config.sections.mysqld.socket`.

On Debian ≥ 9 the formula never sets the root password (`debconf_root_password`
is `False`); the password is only used as `connection_pass`. The RedHat /
Suse / FreeBSD path sets it with `mysqladmin`.

### Salt's MySQL driver

`mysql_user`, `mysql_grants` and `mysql_database` only load if the Python
**running Salt** imports a MySQL driver; `python.sls` installs
`python3-mysqldb` for the system Python, which the onedir does not use. On
Salt 3008 these state modules also left core for `saltext-mysql`.
`test/salt/states/salt_driver.sls` is a test-only copy of the production state
(`salt_driver.sls` in the `saltstack` repository) that pip-installs
`PyMySQL`, plus `saltext.mysql` on ≥ 3008; keep the two in sync.

### Test pillar quirks

`test/salt/pillar/mysql.sls` is derived from `pillar.example`. It overrides
`mysql:config:file` to `~/.my.cnf` with non-default ports and datadir, so in
Kitchen the formula's main config is not `/etc/mysql/my.cnf`. Its
`schema` entries (`baz`, `qux`, `quux`) point to `.schema.tmpl` files that do
not exist; no database in `mysql:database` matches them, so they are never
rendered.

### Other files

- `scripts/import_users.py` dumps users and grants of an existing server as
  pillar data; the root `import_users.py` is an older, differing copy.
- `mysql/macos/` installs MySQL products from `.dmg` archives (`mysql.macos`
  key in `defaults.yaml`); unrelated to the rest of the formula.
