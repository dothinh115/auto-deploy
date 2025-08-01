import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

interface ConfigMapArgs {
    name: string;
    projectName: string;
    data: { [key: string]: string };
}

export function createConfigMap(args: ConfigMapArgs): k8s.core.v1.ConfigMap {
    return new k8s.core.v1.ConfigMap(`${args.name}-env`, {
        metadata: {
            name: `${args.name}-env`,
            labels: {
                app: args.name,
                project: args.projectName
            }
        },
        data: args.data
    });
}