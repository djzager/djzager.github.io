---
title: "Reaching for the Stars with Ansible Operator"
description: "Using Ansible Galaxy to create Kubernetes native applications"
tags: ["Ansible", "Ansible Galaxy", "Ansible Operator", "OpenShift", "Kubernetes"]
cover: https://example.com/img/1/image.jpg
date: 2019-03-02T21:50:22Z
---

My copy of the post on the [Red Hat OpenShift Blog](https://blog.openshift.com/reaching-for-the-stars-with-ansible-operator/).

In this post I will show you how to use Roles published to [Ansible Galaxy](https://galaxy.ansible.com) as an Operator to manage an application in Kubernetes. Reusing a Role in this way provides an example of how to create an Operator that simply installs an application with the flexibility to expand and customize the behavior organically as requirements dictate.

I will leverage both the [Ansible Operator](https://github.com/operator-framework/operator-sdk/blob/master/doc/ansible/user-guide.md) and the [`k8s` module](https://docs.ansible.com/ansible/latest/modules/k8s_module.html) to demonstrate how you can use Ansible to create Kubernetes native applications. Ansible Operator, included in the [Operator SDK](https://github.com/operator-framework/operator-sdk), allows you to package your operational knowledge (how you install and maintain your application) in the form of Ansible Roles and Playbooks. Your ability to manage objects in Kubernetes when writing these Roles and Playbooks can be improved by the new `k8s` module.

**Spoiler Alert** Yes. It can be this easy to create an operator.

```
FROM quay.io/operator-framework/ansible-operator

RUN ansible-galaxy install djzager.hello_world_k8s

RUN echo $'--- \n\
- version: v1alpha1\n\
  group: examples.djzager.io\n\
  kind: HelloWorld\n\
  role: /opt/ansible/roles/djzager.hello_world_k8s' > ${HOME}/watches.yaml
```

# Introduction

First, if you are reading this and are not aware of the `k8s` [Ansible Module](https://docs.ansible.com/ansible/latest/modules/k8s_module.html) you should take a look. Introduced in Ansible 2.6, this module is designed to improve your ability to work with Kubernetes objects in Ansible in any Kubernetes distribution, including Red Hat OpenShift. [This post on the Ansible blog](https://www.ansible.com/blog/dynamic-kubernetes-client-for-ansible) introduces the `k8s` module and the [Red Hat OpenShift dynamic python client](https://github.com/openshift/openshift-restclient-python). The dynamic client simply put, in my opinion, if you are interacting with Kubernetes objects in Ansible and are not using the `k8s` module, you are doing it wrong.

Operators are purpose built to run a Kubernetes application, and the Operator SDK provides the tools to build, test, and package them. Ansible Operator exists to help you encode the operational knowledge of your application in Ansible. The workflow is designed to be simple; use `operator-sdk new --type=Ansible` to generate the necessary bits for an Ansible based Operator, add Ansible, and `operator-sdk build` you have an application built to run in Kubernetes. But if you already have a Role in Galaxy that manages your application in Kubernetes, it can be easier.

In this post I will:

1. Build an Ansible Role for managing a Hello World application in Kubernetes. This role will highlight what I believe makes the Ansible `k8s` module powerful.
1. Publish my Role to Ansible Galaxy.
1. Build an Ansible Operator using my Role published to Galaxy.

Why would you use an Ansible Role from Galaxy to make an Operator? There are two reasons:

1. [Don't repeat yourself](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself). Once I have written an Ansible Role for managing the Hello World application and published it to Ansible Galaxy, I would consume this with Ansible Operator when creating an Operator.
1. [Separation of Concerns](https://en.wikipedia.org/wiki/Separation_of_concerns). I want the Hello World Ansible Role to manage the application in Kubernetes and the operational logic to stay with the Operator. The operational logic in this example is designed to be simple, whenever a `HelloWorld` custom resource is created or modified, call the `djzager.hello_world_k8s` Role. However, [in the future](#next-steps) this separation becomes more important. For example, adding validation for my Hello World application would be a solid addition to the Ansible Role, while managing the status of the `HelloWorld` custom resource would be operational logic specific to my Operator.

# Hello Kubernetes, Meet Ansible

**Pre-Requisites**

1. Ansible - See the [installation guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) if you do not already have Ansible installed.
1. [Optional] OpenShift python client. Only need this if you want to run locally. The installation instructions can be found [here](https://github.com/openshift/openshift-restclient-python#installation).

Let's get started. The first thing I will do is use `ansible-galaxy` to create the Role skeleton:

```
# I like clear names on projects.
# In meta/main.yml I will make role_name: hello-world-k8s
$ ansible-galaxy init ansible-role-hello-world-k8s
```

The first thing I like to do when creating a new Ansible Role is define all of my default values. This also serves as a way of documenting the possible configuration options for the Role, fortunately our Hello World example is not particularly complex. Here is my `defaults/main.yml`:

```yaml
---
# NOTE: meta.name(space) comes from CR metadata when run with Ansible Operator
# deploy/crds has an example CR for reference
name: "{{ meta.name | default('hello-world') }}"
namespace: "{{ meta.namespace | default('hello-world') }}"
image: docker.io/ansibleplaybookbundle/hello-world:latest

# To uninstall from the cluster
# state: absent
state: present

# The size of the hello-world deployment
size: 1
```

Once I have defined my default values I want to answer what this Role is going to do. My Hello World application needs:

1. To get information about the available APIs in the cluster.
1. Render a few templates and make sure they are either `present` or `absent` in the cluster.

My `tasks/main.yml` looks like:

```yaml
---

- name: "Get information about the cluster"
  set_fact:
    api_groups: "{{ lookup('k8s', cluster_info='api_groups') }}"

- name: 'Set hello-world objects state={{ state }}'
  k8s:
    state: '{{ state }}'
    definition: "{{ lookup('template', item.name) | from_yaml }}"
  when: item.api_exists | default(True)
  loop:
    - name: deployment.yml.j2
    - name: service.yml.j2
    - name: route.yml.j2
      api_exists: "{{ True if 'route.openshift.io' in api_groups else False }}"
```

Before I show off the templates, I want to call attention to one line from my tasks file:

```yaml
api_exists: "{{ True if 'route.openshift.io' in api_groups else False }}"
```

I use a `set_fact` to collect all of the available APIs in the cluster and this allows me to selectively render the template if a particular API is available, in this case `route.openshift.io`. Routes in OpenShift are not available by default in a Kubernetes cluster and I don't _need_ them, so I only manage the Route object when the `route.openshift.io` API is present.

Not only am I able to conditionally manage objects in the cluster based on available APIs, using Jinja2 templates, in my Deployment template I can use OpenShift's DeploymentConfig if the `apps.openshift.io` API is present in the cluster. Here is my `templates/deployment.yml.j2`:

```yaml
---

{% if 'apps.openshift.io' in api_groups %}
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
{% else %}
apiVersion: apps/v1
kind: Deployment
{% endif %}
metadata:
  name: {{ name }}
  namespace: {{ namespace }}
  labels:
    app: {{ name }}
    service: {{ name }}
spec:
  replicas: {{ size }}
{% if 'apps.openshift.io' in api_groups %}
  selector:
    app: {{ name }}
    service: {{ name }}
{% else %}
  selector:
    matchLabels:
      app: {{ name }}
      service: {{ name }}
{% endif %}
  template:
    metadata:
      labels:
        app: {{ name }}
        service: {{ name }}
    spec:
      containers:
      - image: {{ image }}
        name: hello-world
        ports:
        - containerPort: 8080
          protocol: TCP
```

My `templates/service.yml.j2`:

```yaml
---

apiVersion: v1
kind: Service
metadata:
  name: {{ name }}
  namespace: {{ namespace }}
  labels:
    app: {{ name }}
    service: {{ name }}
spec:
  ports:
  - name: web
    port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    app: {{ name }}
    service: {{ name }}
```

And finally, my `templates/route.yml.j2`:

```yaml
---

apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {{ name }}
  namespace: {{ namespace }}
  labels:
    app: {{ name }}
    service: {{ name }}
spec:
  port:
    targetPort: web
  to:
    kind: Service
    name: {{ name }}
```

I skipped over the creation of `meta/main.yml`, but you can find mine [here](https://github.com/djzager/ansible-role-hello-world-k8s/blob/ao-galaxy-blog/meta/main.yml).

Now I have an Ansible Role that manages my Hello World application in Kubernetes and can take advantage of APIs if available in the cluster. Using the `k8s` module with the dynamic client simplifies managing objects in Kubernetes. I hope that this Role helps to showcase the power of Ansible when working with Kubernetes.

# Hello Galaxy, Meet Kubernetes

Many of the Ansible Roles published to Galaxy are for server configuration and application management. My wish is for Galaxy to be inundated with Roles managing Kubernetes applications.

Once I have pushed my [Role to GitHub](https://github.com/djzager/ansible-role-hello-world-k8s/), all I need to do is:

1. Log into Ansible Galaxy, giving it access to my GitHub repositories.
1. Import my role

My `hello_world_k8s` role is now publicly available in Galaxy [here](https://galaxy.ansible.com/djzager/hello_world_k8s).

# Hello Ansible Operator, Meet Galaxy

If you have a look at my [Hello World project in GitHub](https://github.com/djzager/ansible-role-hello-world-k8s/) you may notice that I added the necessary pieces to make an Ansible Operator. These are:

1. The [watches file](https://github.com/djzager/ansible-role-hello-world-k8s/blob/ao-galaxy-blog/watches.yaml) that provides a mapping of Kubernetes [Custom Resources](https://kubernetes.io/docs/concepts/api-extension/custom-resources/) to Ansible Roles or Playbooks.
1. The [Dockerfile](https://github.com/djzager/ansible-role-hello-world-k8s/blob/ao-galaxy-blog/build/Dockerfile) for building my Operator.
1. The [deploy directory](https://github.com/djzager/ansible-role-hello-world-k8s/tree/ao-galaxy-blog/deploy) with the Kubernetes specific objects necessary to run my Operator.

Want to know more about building your own Ansible Operator? Check out the [User Guide](https://github.com/operator-framework/operator-sdk/blob/master/doc/ansible/user-guide.md). But I promised to build an Ansible Operator using my Role published to Galaxy, all I __really__ need is a Dockerfile:

```
FROM quay.io/operator-framework/ansible-operator

RUN ansible-galaxy install djzager.hello_world_k8s

RUN echo $'--- \n\
- version: v1alpha1\n\
  group: examples.djzager.io\n\
  kind: HelloWorld\n\
  role: /opt/ansible/roles/djzager.hello_world_k8s' > ${HOME}/watches.yaml
```

Then building an Operator is:

```
$ docker build -t hello-world-operator -f Dockerfile .
Sending build context to Docker daemon 157.2 kB
Step 1/3 : FROM quay.io/operator-framework/ansible-operator
latest: Pulling from operator-framework/ansible-operator
Digest: sha256:1156066a05fb1e1dd5d4286085518e5ce15acabfff10a8145eef8da088475db3
Status: Downloaded newer image for quay.io/water-hole/ansible-operator:latest
 ---> 39cc1d19649d
Step 2/3 : RUN ansible-galaxy install djzager.hello_world_k8s
 ---> Running in 83ba8c21f233
- downloading role 'hello_world_k8s', owned by djzager
- downloading role from https://github.com/djzager/ansible-role-hello-world-k8s/archive/master.tar.gz
- extracting djzager.hello_world_k8s to /opt/ansible/roles/djzager.hello_world_k8s
- djzager.hello_world_k8s (master) was installed successfully
Removing intermediate container 83ba8c21f233
 ---> 2f303b45576c
Step 3/3 : RUN echo $'--- \n- version: v1alpha1\n  group: examples.djzager.io\n    kind: HelloWorld\n      role: /opt/ansible/roles/djzager.hello_world_k8s' > ${HOME}/watches.yaml
 ---> Running in cced495a9cb4
Removing intermediate container cced495a9cb4
 ---> 5827bc3c1ca3
Successfully built 5827bc3c1ca3
Successfully tagged hello-world-operator:latest
```

Admittedly, in order to __use__ this Operator you will want to use the [deploy bits](https://github.com/djzager/ansible-role-hello-world-k8s/tree/ao-galaxy-blog/deploy) from my project to create the Service Account, Role and Role Binding, Custom Resource Definition, as well as deploy the Operator. Once the Operator is deployed, create the Custom Resource to get an instance of the Hello World application:

```yaml
apiVersion: examples.djzager.io/v1alpha1
kind: HelloWorld
metadata:
  name: example-helloworld
  namespace: default
spec:
  size: 3
```

## Namespace Scoped vs Cluster Scoped Operators

I previously suggested that you look at my [deploy directory](https://github.com/djzager/ansible-role-hello-world-k8s/tree/ao-galaxy-blog/deploy) to find the Kubernetes specific objects necessary to run an Operator. If you look closely you will see 3 things that will constrain this Operator to only manage Custom Resources in the namespace where it is deployed:

1. `WATCH_NAMESPACE` environment variable in [operator.yaml](https://github.com/djzager/ansible-role-hello-world-k8s/blob/ao-galaxy-blog/deploy/operator.yaml#L25-L28) tells the operator where to watch Custom Resources.
1. [role.yaml](https://github.com/djzager/ansible-role-hello-world-k8s/blob/ao-galaxy-blog/deploy/role.yaml#L2)
1. [role_binding](https://github.com/djzager/ansible-role-hello-world-k8s/blob/ao-galaxy-blog/deploy/role_binding.yaml#L1)

This is helpful for developing an operator. If I wanted to make my application available to all users of the cluster, though, I would need the help of a cluster admin. I would need to:

1. Create a `ClusterRole` instead of a `Role`.
1. Create the operator `ServiceAccount` in the namespace where the operator will be deployed.
1. Create a `ClusterRoleBinding` that binds the namespaced `ServiceAccount` to the `ClusterRole`
1. Deploy the operator with the `WATCH_NAMESPACE` environment variable unset (or `""`).

Doing so would allow other users of the cluster to deploy instances of my Hello World Application. If this sounds interesting, you should check out the [Operator Lifecycle Manager](https://github.com/operator-framework/operator-lifecycle-manager/) (also a part of the Operator Framework).

# Next Steps

The Hello World application in this post was designed to be intentionally simple but there are still things I could do to make it more robust.

1. Use [Operator SDK](https://github.com/operator-framework/operator-sdk/) - I skipped this piece in this post to highlight how easy it can be to go from an Ansible Role to an Operator. Using this role with the SDK (think `operator-sdk new`) would be something I would suggest to do, and most likely necessary, for subsequent steps.
1. Validation - right now if a user were to create a CR with `size: abc` the deployment creation step would simply fail. It would be better for us to catch errors in the spec before attempting to do work.
1. Lifecycle - in more complex examples this could be handling version upgrades. In a scenario like this one, where there is only one version of the Hello World application, we could detect when the running container image is out of date when compared to what is available in the corresponding container registry and update the running instances.
1. Testing - [Molecule](https://github.com/ansible/molecule) helps with the development and testing of Ansible Roles.
1. [Operator Lifecycle Manager](https://github.com/operator-framework/operator-lifecycle-manager/) - is a toolkit for managing Operators. Integration with OLM would allow us to handle installation and upgrades to our Operator.
1. Status - we could enable the status subresource on our Hello World CRD and use `k8s_status` module, provided in the Ansible Operator image, to include status information to the Custom Resource.

# Conclusion

Now that I have shown you how to build an Ansible Role to manage an application in Kubernetes, publish to Ansible Galaxy, and use that role with Ansible Operator, I hope that you will:

1. Use the [Ansible `k8s` module](https://docs.ansible.com/ansible/latest/modules/k8s_module.html).
1. Start flooding [Ansible Galaxy](https://galaxy.ansible.com) with roles managing Kubernetes applications.
1. Check out [Operator SDK](https://github.com/operator-framework/operator-sdk) and join us on the [Operator Framework mailing list](https://groups.google.com/forum/#!forum/operator-framework).
