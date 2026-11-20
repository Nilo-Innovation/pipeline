# Plantilla ECS de `web-loms` (front de LOMS)

Copia de la plantilla genérica `s3://lineup-terraform-<stage>/ecs/` con un solo cambio:
la regla del listener del ALB interno también exige el dominio (`listener_host_headers`),
igual que `crm-web-service` (que se ajustó a mano en el ALB). Sin esa condición,
la regla `/*` se llevaría el tráfico de los demás servicios del ALB.

El contenedor escucha en 8080, como la plantilla genérica.

`terraform-aws-ecs.yml` descarga esta carpeta de S3 cuando `SERVICE_NAME` es `web-loms`.
Para publicarla (una vez, o cada vez que cambie):

```bash
aws s3 sync --profile prod terraform-templates/ecs/web-loms/ s3://lineup-terraform-prod/ecs/web-loms/ --exclude README.md
```
