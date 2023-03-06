# Code Server

---
This is an Acorn with code-server, Acorn CLI, and Acorn VSCode extension preinstalled.

## Quickstart

To quickly deploy a code-server environment run the Acorn:

```bash
acorn run ghcr.io/acorn-io/library/code-server
```

A password will be automatically generated for you, to obtain it, run:

```bash
acorn secrets
# ...
#code-server-password-XXXXX
```

Look for the secret named code-server-password-[5 letter string] then run:

```bash
acorn secret reveal code-server-password-[5 letter string]
```

Copy the Value and open the URL to the running instance. Paste the password when prompted and start using code-server environment.

## Advanced Usage

You can check out a public source repository over http(s) on launch by passing in `--git-repo`.
