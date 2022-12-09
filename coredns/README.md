# CoreDNS Acorn

This Acorn provides a CoreDNS instance. It will serve UDP DNS trafic over port 53.

## Quick start

`acorn run [COREDNS_IMAGE]`

This will create a standalone CoreDNS instance using the default Corefile. If you would like to overwrite the default Corefile, you can do so easily.

`acorn run [COREDNS_IMAGE] --corefile @Corefile`

> **Note**: Everything after @ should be an absolute path to your Corefile. For more information, see [the documentation](https://docs.acorn.io/running/args-and-secrets#passing-complex-arguments) for this Acorn feature.

## Available options

```shell
--corefile string  String of a Corefile to run with.  Default ("")
--scale int        Number of replicas to run
--version  string  Version of CoreDNS to use.         Default ("1.10.0")
```
