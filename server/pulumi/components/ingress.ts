import * as pulumi from "@pulumi/pulumi";
import * as k8s from "@pulumi/kubernetes";

interface IngressArgs {
    name: string;
    projectName: string;
    hosts: string[];
    serviceName: pulumi.Output<string>;
    servicePort: number;
    enableTls: boolean;
    certEmail?: string;
}

export function createIngress(args: IngressArgs): k8s.networking.v1.Ingress {
    const annotations: { [key: string]: string } = {
        "nginx.ingress.kubernetes.io/backend-protocol": "HTTP",
        // Enable gzip compression for better performance
        "nginx.ingress.kubernetes.io/enable-gzip": "true",
        "nginx.ingress.kubernetes.io/gzip-level": "6",
        "nginx.ingress.kubernetes.io/gzip-types": "text/plain application/json application/javascript text/css application/xml text/xml application/xml+rss text/javascript"
    };

    // Add cert-manager annotations for automatic SSL
    if (args.enableTls && args.certEmail) {
        annotations["cert-manager.io/cluster-issuer"] = "letsencrypt-prod";
        annotations["cert-manager.io/issue-temporary-certificate"] = "true";
        annotations["acme.cert-manager.io/http01-edit-in-place"] = "true";
    }

    // Build ingress rules
    const rules = args.hosts.map(host => ({
        host: host,
        http: {
            paths: [{
                path: "/",
                pathType: "Prefix" as const,
                backend: {
                    service: {
                        name: args.serviceName,
                        port: {
                            number: args.servicePort
                        }
                    }
                }
            }]
        }
    }));

    // Build TLS configuration
    const tls = args.enableTls ? [{
        hosts: args.hosts,
        secretName: `${args.projectName}-tls`
    }] : undefined;

    return new k8s.networking.v1.Ingress(`${args.name}-ingress`, {
        metadata: {
            name: args.name,
            labels: {
                app: args.name,
                project: args.projectName
            },
            annotations: annotations
        },
        spec: {
            ingressClassName: "nginx",
            rules: rules,
            tls: tls
        }
    });
}