---
title: "Tool Time: Ansible and Your Kubernetes Toolbox"
description: |
  How Ansible and the k8s module can help when building applications
  for Kubernetes
tags: ["Ansible", "k8s", "OpenShift", "Kubernetes"]
cover: https://example.com/img/1/image.jpg
date: 2019-03-06T17:23:58Z
draft: true
---

I want to talk to you about the power of the
[Ansible k8s module](https://docs.ansible.com/ansible/latest/modules/k8s_module.html)
and how it can help you when creating developing applications in Kubernetes.

Ansible Roles written using the `k8s` module are an excellent way of packaging
your application

**NOTE**

[Reaching for
the Stars with Ansible Galaxy](https://blog.openshift.com/reaching-for-the-stars-with-ansible-operator/),
my goal was to create a Kubernetes native application leveraging [Ansible
Operator]() and a [`hello_world_k8s` Role](https://galaxy.ansible.com/djzager/hello_world_k8s)
in [Ansible Galaxy]().

# Introduction

Kubernetes objects are predominantly described in YAML files like this one
defining an `nginx-deployment`:

```yaml
# application/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
- containerPort: 80
```

Continuing with the example `nginx-deployment` above, we can add this
deployment to the [cluster's _desired state_](https://kubernetes.io/docs/concepts/#overview)
with `kubectl create -f application/deployment.yaml`. Most of the time these
deployments will be coupled with a service (included below) to provide a means
of communicating with my Nginx deployment.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx
spec:
  ports:
  - name: web
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
app: nginx
```

With Ansible, I can package these up into a Role

# Yet Another Place for my YAML

# Jinja2 to the Rescue

# Lookup Plugin

# Make it Configurable


