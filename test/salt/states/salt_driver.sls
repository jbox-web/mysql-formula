# -*- coding: utf-8 -*-
# vim: ft=sls
---
# Test-only copy of the production state (saltstack:
# formulas/vigilience/mysql/salt_driver.sls).
# mysql-formula's mysql_user, mysql_grants and mysql_database states only load
# when Salt's own Python can import a MySQL driver. The onedir ships none (the
# formula's python3-mysqldb goes to the system Python), so these states were
# missing on every mysql host. Salt 3008 also moved them out of core, into
# saltext-mysql. Without bin_env, pip.installed uses the onedir's salt-pip.
vigilience/mysql/salt_driver/pymysql:
  pip.installed:
    - name: PyMySQL == 1.2.3
    - reload_modules: True

{%- if grains['saltversioninfo'][0] >= 3008 %}

vigilience/mysql/salt_driver/saltext-mysql:
  pip.installed:
    - name: saltext.mysql == 1.1.0
    - reload_modules: True
    - require:
      - pip: vigilience/mysql/salt_driver/pymysql
{%- endif %}
