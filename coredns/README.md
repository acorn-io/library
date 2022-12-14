# CoreDNS Acorn

This Acorn provides a CoreDNS instance. It will serve UDP DNS traffic over port 53.

## Quick start

`acorn run [COREDNS_IMAGE]`

This will create a standalone CoreDNS instance using the default Corefile. If you would like to overwrite the default Corefile, its a quick two step process.

1. Create a YAML file and write it in such a way where there are only keys and values. Each key will be a config's filename and each value will be its content.

    ```yaml
    # configs.yaml
    Corefile: |
        {
            whoami
            log
        }
    foo-config: |
        bar-data
    ```

2. Now just run the CoreDNS Acorn and reference that config file with the `--configs` flag. The configs we created will each be written to individual files in the same directory that CoreDNS runs. In this example, we will get both a `Corefile` and a `foo-config` created.

    `acorn run [COREDNS_IMAGE] --configs @configs.yaml`

    > **Note**: Everything after @ should be an absolute path to your configs file. For more information, see [the documentation](https://docs.acorn.io/running/args-and-secrets#passing-complex-arguments) for this Acorn feature.

This process will work for any configs that you could need for CoreDNS or its plugins. 

### Available options

```
--scale     int     Number of replicas to run                                                         Default (1)
--version   string  Version of CoreDNS to use.                                                        Default ("1.10.0")
--configs   object  YAML file where each key is a filename and its value is the content of that file. Default ({})
```
