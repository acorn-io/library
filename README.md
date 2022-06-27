# Acorn Library

This repository houses all of the Acorn library image definitions.

## Style / Guidelines for library acorns

1. Use official images from the Docker library if available.
1. Use specific version tags of images, at least to the minor in semver.
1. Use automatically generated secrets, and allow the user to specify values if needed.
1. Prefer to handle the application in cuelang vs. string interpolations.
1. Do not use master - slave terminology.  Use terms like leader / follower, worker / agents, replicas, etc.
1. When adding parameters:
      a. Use `scale` to represent number of containers running of the exact same config.
      b. Use `replicas` to represent multiple instances with the same role.
1. Create a secret `"user-secret-data": type: "opaque"` to allow users to bind in secret data for use inside the acorn.
