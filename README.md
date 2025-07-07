# Infrastructure Deployment

This repository orchestrates the microservices infrastructure for a backend engineering task assigned by Aylo for the 
backend PHP engineer role. The system ingests, processes, and exposes data from a remote pornstar feed via REST APIs, 
handling image caching and efficient resource usage.

## 🔍 Problem Overview

You provided a JSON feed of pornstars that is updated daily:
```
https://ph-c3fuhehkfqh6huc0.z01.azurefd.net/feed_pornstars.json
```

### Objective

- Download and cache the feed items efficiently (only download each image once).
- Expose a RESTful API to interact with the `Pornstar` entity.
- Ensure the application is fully tested and containerized using Docker.

## 🧠 Architectural Approach

Instead of a PHP monolith, I chose a **microservices architecture** for clear separation of concerns, scalability, and 
testability. Each service is built with **PHP (Laravel 12)** and deployed as a Docker container.

This architecture allows services to operate independently and communicate asynchronously via **RabbitMQ**. The use of 
message queues decouples processes, increases reliability, and enhances scalability.

These asynchronous capabilities reduce response time for API consumers and isolate time-consuming processes such as 
downloading and storing images, leading to a more responsive and resilient system overall.

The images for each service are hosted under my GitHub organization using GitHub's package repository service. All 
services have CI/CD through GitHub Actions that run the Laravel tests as well as PHPStan and Laravel Pint (phpcs also 
available). Depending on the tests status (not the code quality checks because I didn't have time to fix them), the 
workflow will also build an image using the Dockerfile and publish it on the GitHub package repository.


### Microservices Overview

| Repository          | Description                                                                                                            |
|---------------------|------------------------------------------------------------------------------------------------------------------------|
| `php-feed-ingestor` | Downloads the JSON feed and publishes feed items to RabbitMQ queues.                                                   |
| `php-image-worker`  | Consumes image download jobs, caches the images locally, and emits updates.                                            |
| `php-api-service`   | REST API to manage `Pornstar` entities and their images. Consumes messages from the other two services for DB updates. |
| `infra-deployment`  | Orchestrates the infrastructure using Docker Compose.                                                                  |

## 🧱 Tech Stack

- **PHP 8.4 + Laravel 12**
- **MySQL** (with split read/write operations and replication-ready setup with failover)
- **RabbitMQ** (for inter-service messaging)
- **Redis** (for Laravel image queue cache)
- **Docker + Docker Compose**

## 🚀 Getting Started

### Prerequisites

- Docker
- Docker Compose
- Git

### Spin Up the Infrastructure

Clone this repo:

```bash
git clone https://github.com/SmokeSoulsOrg/infra-deployment.git
cd infra-deployment
```

Build and start all containers:

```bash
docker-compose up
```

Wait until all services are healthy, this should take about a minute.
You are safe when all you see are repeating logs from rabbitmq about publishing and consuming messages.

You should then see:

- `php-api-service` at http://localhost:8080
- `php-feed-ingestor` running as a command-line worker
- `php-image-worker` consuming image downloads and producing image local path updates
- MySQL at `localhost:3306` and its read replica at `localhost:3307`
- RabbitMQ UI at http://localhost:15672 (user/pass: guest/guest)

### Access the API

You can now interact with the RESTful API at:

```
http://localhost:8080/api/v1
```

You can import the Postman collection at the root of the infra-deployment repository for easy testing of all available
API endpoints.

## 🔁 Resetting the Environment

If something goes wrong, or you want to reset everything:

```bash
docker-compose down -v
docker-compose up
```

This will:

- Restart all containers and volumes
- Initialize fresh MySQL databases, Redis database and RabbitMQ queues

## 📂 Repository Structure

```
infra-deployment/
├── .envs/
│ ├── php-api-service.env
│ ├── php-feed-ingestor.env
│ └── php-image-worker.env
│
├── docker/
│ ├── mysql/
│ │ ├── conf.d/
│ │ │ └── z-replication.cnf
│ │ └── init-replica-user.sql
│ │
│ └── mysql_read/
│ ├── conf.d/
│ │ └── z-replication.cnf
│ ├── init-sail-user.sql
│ ├── init-laravel-user.sql
│ └── init-replication.sh
│
├── scripts/
│ └── post-down.sh
│
├── .gitignore
├── docker-compose.yml
├── php-api-service.postman_collection.json
└── README.md
```

## 🧩 Services Overview

The `docker-compose.yml` file orchestrates the following services:

| Service            | Description                                                                                  |
|--------------------|----------------------------------------------------------------------------------------------|
| `php-api-service`  | Exposes a REST API to interact with `Pornstar` entities, their aliases and their thumbnails. |
| `php-feed-ingestor`| Consumes the daily JSON feed, parses it, and publishes items to RabbitMQ.                    |
| `php-image-worker` | Downloads images from feed items and publishes update messages to RabbitMQ.                  |
| `mysql`            | Primary MySQL instance with replication support.                                             |
| `mysql_read`       | Read-replica MySQL instance for read-heavy operations.                                       |
| `redis`            | In-memory data store for Laravel queues (optional use).                                      |
| `rabbitmq`         | Message broker for asynchronous communication between services.                              |

All services share the same Docker bridge network (`aylo`) and use named volumes for persistent
storage and shared image caching.

## 🛠 Important Artisan Commands

### ⏱ Scheduled Feed Ingestion

The `php-feed-ingestor` service runs the `ingest-pornstar-feed` Artisan command to download
and publish items from the daily pornstar JSON feed.

In `console.php`, the schedule is configured as:

```php
Schedule::command('ingest-pornstar-feed')
//    ->dailyAt('02:00') // this would be a normal value
    ->everyMinute() // for testing purposes during the interview task
    ->appendOutputTo(storage_path('logs/scheduler.log'));
```

This command is currently scheduled to run **every minute** for easier testing. In production,
you would typically run `php artisan schedule:run` every minute via system cron, and adjust the
task to run once daily.

### 💀 Dead Letter Queue Consumer

Due to the asynchronous nature of this infrastructure there is a slight chance an image-update message to reach a
consumer before the pornstar-event message that creates the entities. That's why the image-update queue is set up with
dead-letter-exchange to pass not acknowledged messages to the image-update-dead queue.

The `php-api-service` includes a command called `consume:image-update-dead`, which processes
those messages that failed to apply, because a `PornstarThumbnailUrl` entity did not yet exist when
the image update was received.

This command can be run **manually** or scheduled using Laravel's scheduler to retry failed
image update messages:

```bash
php artisan consume:image-update-dead
```

This ensures image updates are eventually applied once related entities are available without holding back any other 
services.

## ✅ Testing and Validation

All code across the services is covered with unit and feature tests which already run in GitHub Actions.

If you want to run tests manually you can do it inside the containers:

```bash
docker exec -it  infra-deployment-php-api-service-1 php artisan test
docker exec -it  infra-deployment-php-feed-ingestor-1 php artisan test
docker exec -it  infra-deployment-php-image-worker-1 php artisan test
```

or run each repository separately by cloning it and running:
```bash
sail up -d
sail artisan test
```

## 🔗 Related Repositories

- [`php-api-service`](https://github.com/SmokeSoulsOrg/php-api-service)
- [`php-feed-ingestor`](https://github.com/SmokeSoulsOrg/php-feed-ingestor)
- [`php-image-worker`](https://github.com/SmokeSoulsOrg/php-image-worker)

## 📌 Notes for Reviewer

This repository is the entry point. You only need to run this one to see the full system in action. Each service can be 
inspected individually via GitHub or `git clone` if you'd like to explore the code.

If anything breaks, `docker-compose down -v` and `docker-compose up` will ensure a clean state.

---

Made with ❤️ for the Aylo backend interview.
