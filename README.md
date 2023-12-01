# learn-k8s-automation

Notes and automated pipelines for various things related to a Kubernetes cluster.

Currently using packer to automate a golden image pipeline and vagrant to automate provisioning and per-instance configuration of all the nodes in the cluster.<br>
The golden image is pretty bare right now. Still figuring out what I should pre-install and what I should do on a per-instance basis.

kubernetes-production-setup-guide.md details all of the steps I took to initialize the cluster with kubeadm (mostly cobbled together several guides). Living document.<br>
kubernetes-notes.md is a bunch of notes on things to consider when operating a cluster in production.<br>
high-availability-topology.png is ripped from this excellent tutorial: https://mvallim.github.io/kubernetes-under-the-hood/documentation/kube-masters-and-workers.html <br>
kubernetes-io-stylus.css is a dark theme for kubernetes.io originally by ivaks but modified by me built for the Stylus browser addon.