import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";
import { createDeployment } from "./components/deployment";
import { createService } from "./components/service";
import { createIngress } from "./components/ingress";
import { createConfigMap } from "./components/configmap";

// Get configuration
const config = new pulumi.Config("auto-deploy");
const projectName = config.require("projectName");
const appName = config.require("appName");
const image = config.require("image");
const replicas = config.getNumber("replicas") || 2;
const containerPort = config.getNumber("containerPort") || 3000;
const servicePort = config.getNumber("servicePort") || 80;
const ingressHosts = config.requireObject<string[]>("ingressHosts");
const enableTls = config.getBoolean("enableTls") ?? true;
const certEmail = config.get("certEmail");
const enableResourceLimits = config.getBoolean("enableResourceLimits") ?? false;
const envConfigMapName = config.get("envConfigMap");

// Resource limits configuration
const resourceLimits = enableResourceLimits ? {
    requests: {
        cpu: config.get("cpuRequest") || "250m",
        memory: config.get("memoryRequest") || "256Mi"
    },
    limits: {
        cpu: config.get("cpuLimit") || "500m",
        memory: config.get("memoryLimit") || "512Mi"
    }
} : undefined;

// Create ConfigMap if environment variables are provided
let configMap: k8s.core.v1.ConfigMap | undefined;
if (envConfigMapName) {
    // This assumes the ConfigMap already exists or will be created separately
    pulumi.log.info(`Using existing ConfigMap: ${envConfigMapName}`);
}

// Create Deployment
const deployment = createDeployment({
    name: appName,
    projectName: projectName,
    image: image,
    replicas: replicas,
    containerPort: containerPort,
    resources: resourceLimits,
    envFromConfigMap: envConfigMapName
});

// Create Service
const service = createService({
    name: appName,
    projectName: projectName,
    targetPort: containerPort,
    servicePort: servicePort,
    selector: {
        app: appName,
        project: projectName
    }
});

// Create Ingress
const ingress = createIngress({
    name: appName,
    projectName: projectName,
    hosts: ingressHosts,
    serviceName: service.metadata.name,
    servicePort: servicePort,
    enableTls: enableTls,
    certEmail: certEmail
});

// Export important values
export const deploymentName = deployment.metadata.name;
export const serviceName = service.metadata.name;
export const ingressName = ingress.metadata.name;
export const appUrl = pulumi.interpolate`http${enableTls ? 's' : ''}://${ingressHosts[0]}`;
export const podReplicas = replicas;