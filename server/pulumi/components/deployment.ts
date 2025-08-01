import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

interface DeploymentArgs {
    name: string;
    projectName: string;
    image: string;
    replicas: number;
    containerPort: number;
    resources?: {
        requests?: {
            cpu?: string;
            memory?: string;
        };
        limits?: {
            cpu?: string;
            memory?: string;
        };
    };
    envFromConfigMap?: string;
}

export function createDeployment(args: DeploymentArgs): k8s.apps.v1.Deployment {
    const labels = {
        app: args.name,
        project: args.projectName
    };

    return new k8s.apps.v1.Deployment(`${args.name}-deployment`, {
        metadata: {
            name: args.name,
            labels: labels
        },
        spec: {
            replicas: args.replicas,
            selector: {
                matchLabels: labels
            },
            template: {
                metadata: {
                    labels: labels
                },
                spec: {
                    containers: [{
                        name: args.name,
                        image: args.image,
                        imagePullPolicy: "IfNotPresent",
                        ports: [{
                            containerPort: args.containerPort
                        }],
                        resources: args.resources,
                        envFrom: args.envFromConfigMap ? [{
                            configMapRef: {
                                name: args.envFromConfigMap
                            }
                        }] : undefined,
                        // Health checks disabled temporarily for debugging
                        // livenessProbe: {
                        //     httpGet: {
                        //         path: "/health",
                        //         port: args.containerPort
                        //     },
                        //     initialDelaySeconds: 30,
                        //     periodSeconds: 10,
                        //     failureThreshold: 3
                        // },
                        // readinessProbe: {
                        //     httpGet: {
                        //         path: "/health",
                        //         port: args.containerPort
                        //     },
                        //     initialDelaySeconds: 5,
                        //     periodSeconds: 5,
                        //     failureThreshold: 3
                        // }
                    }],
                    restartPolicy: "Always"
                }
            }
        }
    });
}