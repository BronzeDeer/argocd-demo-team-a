# Demo Repo of an enabled Stream team

This repo shows how a development team can be enabled to fully handle their own development and deployments via GitOps and without clusterAcces thanks to ArgoCD
It also serves as a general introduction to ArgoCD and therefore purposefully mixes the different ways of generating manifests supported by default ArgoCD (Helm, Jsonnet, Kustomize, plain Yaml).


## Apps

### Entry point (argocd-root)

The entry point implements the app of app pattern in jsonnet, it loads the base app manifest from each app in this repo and applies it while passing relevant metadata. It also patches the relevant data like appNamespace, appProject, and source information (repoURL, revision, path). This allows the code to be invoked from diferent branches, forks, and even as a vendored repository without modification.

### Kube Say

A simple cronjob of the docker/whalesay image, it serves as an example of deploying via plain yamls manifests in cases where no changes (beyond setting the namespace on resources with no set namespace) need to be made to the manifests

### HTTP Echo

A simple deployment of `traefik/whoami` which echos back all headers of any http request that reaches it. It demonstrates how the root-app can should use the _clusterInfo input to configure sub-apps
