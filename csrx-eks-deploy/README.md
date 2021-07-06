The scripts in these directories will help you:

1. Create a EKS cluster in your AWS account
2. Set up a cSRX to address primarily two different use cases in a EKS environment:
       a. North/ South Application Protection
       b. Microsegmentation a.k.a East/ West Firewall 
       

# Pre-requisites

1. Install the following essential tools: 
       aws cli - https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html 
       kubectl - https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html 
       eksctl - https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html 
 
 
2. Create iam policy for flannel. 
 
#iam-policy.json 
{ 
  "Version": "2012-10-17", 
  "Statement": [ 
    { 
      "Action": [ 
        "ec2:ModifyInstanceAttribute" 
      ], 
      "Resource": "*", 
      "Effect": "Allow" 
    } 
  ] 
} 
 
**#iam policy creation **

aws iam create-policy --policy-name EKSFlannelCNI --policy-document file://iam-policy.json
 
***

## Create EKS Cluster 

### eksctl create cluster with 0 nodes
```eksctl create cluster -f eks-csrx-demo-cluster.yaml --without-nodegroup --profile saml```

### remove aws-node (to remove the AWS CNI. The cSRX will use the multus CNI, which allows the creation of multiple interfaces attached to a single container)
```kubectl delete ds aws-node -n kube-system ```

### create nodegroup
```eksctl create nodegroup --config-file eks-csrx-demo-cluster.yaml --profile saml```

### install etcd pod (etcd is for resource management/ networking CIDR in Kubernetes. Needed for Flannel CNI)
```kubectl apply -f etcd.yaml```

### set network in etcd pod (18.16.0.0/16 is for the Kubernetes network pods (Management IP for pods comes from this network))
```
kubectl exec -it etcd -n kube-system -- sh
ETCDCTL_API=2 etcdctl set /coreos.com/network/config '{"Network":"18.16.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan", "VNI": 1}}'
```

### install multus cni 

git clone https://github.com/intel/multus-cni
```kubectl apply -f ./multus-cni/images/multus-daemonset.yml```

### modify ETCD_IP and install flannel cni (Flannel gets the IP addresses from the 192.168 network to assign to the container pods)

### get etcd POD IP
```
kubectl get pod -A -o wide | grep etcd  
--etcd-endpoints=http://etcd-pod-ip:2379   
```
### replace in this line in kube-flannel.yaml
```
sed -i '' -e 's/192.168.87.24/192.168.87.23/g' kube-flannel.yml
kubectl apply -f kube-flannel.yaml
```

### associate iam role with current eks cluster (create service account for cSRX Pods)
```eksctl utils associate-iam-oidc-provider --cluster=csrx-eks-demo --approve --profile saml```

## Preparation for Use Cases deployment

### Install everything in the folder preparation/ 
```kubectl apply -f preparation/```

#### to create serviceaccount for csrxpod
```kubectl apply -f preparation/00-serviceaccount-csrxpod.yaml```

#### to create nginx-ingress-controller roles and rolebindings
```
kubectl apply -f preparation/06-nginx-ingress-roles-rolebindings.yaml
kubectl apply -f preparation/07-nginx-ingress-controller-deploy.yaml
```

#### to create AWS-ALB alb-ingress-controller role and rolebindings
```
kubectl apply -f preparation/09-alb-rbac-role.yaml
kubectl apply -f preparation/10-alb-ingress-controller.yaml
```


### create iamservcieaccount and attach policy arn for serviceaccount csrxpod
```
eksctl create iamserviceaccount \
       --cluster csrx-eks-demo \
       --name csrxpod \
       --attach-policy-arn=arn:aws:iam::aws:policy/AdministratorAccess \
       --override-existing-serviceaccounts \
       --approve \
       --profile saml
```

### create iamservcieaccount and attach policy arn for ALB serviceaccount alb-ingress-controller

```
eksctl create iamserviceaccount \
       --cluster=csrx-eks-demo \
       --namespace=kube-system \
       --name=alb-ingress-controller \
       --attach-policy-arn=arn:aws:iam::<AWS-Account-number>:policy/ALBIngressControllerIAMPolicy \
       --override-existing-serviceaccounts \
       --approve \
       --profile saml
```

```
eksctl create iamserviceaccount \
       --cluster=csrx-eks-demo \
       --namespace=kube-system \
       --name=alb-ingress-controller \
       --attach-policy-arn=arn:aws:iam::<AWS-Account-number>:policy/ALBIngressControllerIAMPolicy \
       --override-existing-serviceaccounts \
       --approve \
       --profile saml
```

### install metrics-server
```kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.6/components.yaml```

### edit deployment metrics-server in namespace kuby-system
```
kubectl edit deployment metrics-server -n kube-system 
hostNetwork: true          ## under spec:template:spec (the same level with containers)
```
### create backend web service
```kubectl apply -f preparation/01-websrv.yaml```

### replace web1 service ip in all configMaps yaml file
```grep -rli 10.100. * | xargs sed -i '' -e 's/10.100.207.61/new-web-svc-ip/g'```


***

## 1 - North/South Deployment with Nginx-IngressController in EKS
### deploy North-South Use Case
```kubectl apply -f 1-north-south-Nginx-IngressController/```

### Config bridge on worker node -- okay to skip if done. 
#### login each worker node and run the following command. This is needed for the packet to be forwarded to the destination web application service from the cSRX
```ifconfig br-51 51.0.0.1/24```

### get ingress access url (look for the URL in the output here and use in the following command)
```kubectl get ingress```

### access web via ingress url
```curl http://ingress-address-url```


***

## 2 - ALB: North/South Deployment with ALB IngressController in EKS
### deploy North-South Use Case
```kubectl apply -f 2-north-south-ALB-IngressController/```

### Config bridge on worker node -- skip if done
#### login each worker node and run the following command. This is needed for the packet to be forwarded to the destination web application service from the cSRX
```ifconfig br-51 51.0.0.1/24```

### get ingress access url
```kubectl get ingress```

### access web via ingress url
```curl http://ingress-address-url```

***

## 3 - NLB: North/South Deployment with service type LoadBalancer
### deploy NLB with serivce type LoadBalancer
```kubectl apply -f 3-north-south-NLB/```

### Config bridge on worker node -- skip if done
#### login each worker node and run the following command. This is needed for the packet to be forwarded to the destination web application service from the cSRX
```ifconfig br-51 51.0.0.1/24```

### access backend web via csrx service
```curl service_csrx3_external-ip```

### SSH access one csrxvia csrx-ssh service
```ssh root@service_csrx3-ssh_external-ip```


***

## 4 - East-West Deployment
### deploy East-West Use Case
```kubectl apply -f 4-east-west-service-chain/```

### Config bridge on worker node -- skip if done
```ifconfig br-51 51.0.0.1/24```

### access backend web via csrx-byol service
```frontend# curl http://csrx-svc-ip:port```

### SSH access cSRX for management via csrx-ssh service
```ssh root@csrx-ssh service LoadBalancer external ip address```

***





