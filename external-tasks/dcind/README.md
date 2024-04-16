# Docker-Compose-in-Docker CI image

So you want to run Docker in Concourse on `arm64`? Well this is the image for you!

This image implements the ability to run `docker-compose` inside a task in Concourse to bring up our application along side some other services (i.e. Redis, Postgres, MySQL, etc.).

## Privileged Tasks

Running Docker inside Concourse requires the task step to be privileged because Docker needs access to the hosts cgroup filesystem in order to create containers.

## Externalize All Images

You should avoid having Docker fetch any images from inside your task step where you are running docker-compose. You should externalize these as image resources if they're a dependency of your application (e.g. Postgres, MySQL).

For the container image that contains your application you should have that built in a previous step or job. You can build and publish an image using the oci-build task.

To ensure Docker doesn't try to fetch the images itself you can use docker load and docker tag to load your externalized images into Docker.

### Usage

Use this `Dockerfile` to build a base image for your integration tests in [Concourse CI](http://concourse.ci/). Alternatively, you can use a ready-to-use image from the Docker Hub: [rdclda/concourse-dcind-task](https://hub.docker.com/rdclda/concourse-dcind-task). The image is Alpine based.

Here is an example of a Concourse [job](https://concourse-ci.org/jobs.html) that uses `rdclda/concourse-dcind-task` image to run a bunch of containers in a task, and then runs the integration test suite. You can find a full version of this example in the [`example`](./example) directory.

Note that `docker-lib.sh` has `bash` dependencies, so it is important to use `bash` in your task.

~~~yaml
  - name: integration
    plan:
      - get: code
        params: {depth: 1}
        passed: [unit-tests]
        trigger: true
      - get: redis
        params: {format: oci}
      - get: busybox
        params: {format: oci}
      - task: run-integration-tests
        privileged: true
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: rdclda/concourse-dcind-task
          inputs:
            - name: code
            - name: redis
          run:
            path: bash
            args:
              - -ec
              - |
                source /docker-lib.sh
                start_docker

                # Strictly speaking, preloading of Docker images is not required.
                # However, you might want to do this for a couple of reasons:
                # - If the image comes from a private repository, it is much easier to let Concourse pull it,
                #   and then pass it through to the task.
                # - When the image is passed to the task, Concourse can often get the image from its cache.
                docker load -i redis/image.tar

                # This is just to visually check in the log that images have been loaded successfully.
                docker images

                # Run the container with tests and its dependencies.
                docker-compose -f code/external-tasks/dcind/example/integration.yaml run tests
~~~
