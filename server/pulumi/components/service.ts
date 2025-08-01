import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

interface ServiceArgs {
    name: string;
    projectName: string;
    targetPort: number;
    servicePort: number;
    selector: { [key: string]: string };
}

export function createService(args: ServiceArgs): k8s.core.v1.Service {
    return new k8s.core.v1.Service(`${args.name}-service`, {
        metadata: {
            name: args.name,
            labels: {
                app: args.name,
                project: args.projectName
            }
        },
        spec: {
            type: "ClusterIP",
            selector: args.selector,
            ports: [{
                port: args.servicePort,
                targetPort: args.targetPort,
                protocol: "TCP"
            }]
        }
    });
}