mod_web_register_web_plus - an extended version of mod_register_web
===================================================================

* Author: Stefan Strigler <stefan@strigler.de>

This is a copy of the original
[`mod_register_web`](https://docs.ejabberd.im/admin/configuration/modules/#mod_register_web)
and then extended to suite our needs.

Example Configuration
---------------------

Setup a listener for and request handler for mod_register_web_plus. Configure mod_register and mod_register_web_plus. Make email
verification mandatory and store registration data in sql.

```yaml
listen:
  -
    port: 5443
    ip: "::"
    module: ejabberd_http
    tls: true
    request_handlers:
      /register: mod_register_web_plus

modules:
  mod_register:
    captcha_protected: true
    redirect_url: "http://<your_host>:5280/register/"
    allow_modules: [mod_register_web_plus]
    password_strength: 32

  mod_register_web_plus:
    db_type: sql
    email: mandatory
```
