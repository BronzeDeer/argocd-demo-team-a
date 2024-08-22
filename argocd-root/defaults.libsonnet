// .libsonnet files are not evaluated by argoCD since by convetion they are meant to be executed as part of other jsonnet files
{
  _argoCD: {
    repoURL: 'https://github.com/BronzeDeer/argocd-demo-team-a.git',
    targetRevision: 'HEAD',
    path: './argo-root',
    deployNamespace: 'team-a',
    appNamespace: 'app-team-a',
    appProject: 'team-a',
    # Only one of destinationName or server can be present on an application at the same time
    # If both are present, name takes precedence
    #destinationName: "in-cluster",
    destinationServer: "https://kubernetes.default.svc",
  },
}
