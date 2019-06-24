#!/usr/bin/env bash
set -e

REV=`git log -n 1 --pretty=format:%h -- docker/`
IMGNAME="uxbox"

function kill-container {
    echo "Cleaning development container $IMGNAME:$REV..."
    if $(docker ps | grep -q $IMGNAME); then
        docker ps | grep $IMGNAME | awk '{print $1}' | xargs --no-run-if-empty docker kill
    fi
    if $(docker ps -a | grep -q $IMGNAME); then
        docker ps -a | grep $IMGNAME | awk '{print $1}' | xargs --no-run-if-empty docker rm
    fi
}

function remove-image {
    echo "Clean old development image $IMGNAME..."
    docker images | grep $IMGNAME | awk '{print $3}' | xargs --no-run-if-empty docker rmi
}

function build-devenv {
    kill-container
    echo "Building development image $IMGNAME:$REV..."
    docker build --rm=true -t $IMGNAME:$REV --build-arg EXTERNAL_UID=$(id -u)  -t $IMGNAME:latest docker/devenv
}

function run-devenv {
    kill-container

    if ! $(docker images | grep $IMGNAME | grep -q $REV); then
        build-devenv
    fi

    mkdir -p $HOME/.m2
    rm -rf ./frontend/node_modules
    mkdir -p \
        ./frontend/resources/public/css \
        ./frontend/resources/public/view/css

    CONTAINER=$IMGNAME:latest

    echo "Running development image $CONTAINER..."
    docker run --rm -ti \
         -v `pwd`:/home/uxbox/uxbox  \
         -v $HOME/.m2:/home/uxbox/.m2 \
         -v $HOME/.gitconfig:/home/uxbox/.gitconfig \
         -p 3449:3449 -p 6060:6060 -p 9090:9090 \
         $CONTAINER
}

function run-all-tests {
    echo "Testing frontend..."
    run-frontend-tests || exit 1;
    echo "Testing backend..."
    run-backend-tests || exit 1;
}

function run-frontend-tests {
   if ! $(docker images | grep $IMGNAME | grep -q $REV); then
       build-devenv
   fi

   CONTAINER=$IMGNAME:latest

   echo "Running development image $CONTAINER to test backend..."
   docker run -ti --rm \
          -w /home/uxbox/uxbox/frontend \
          -v `pwd`:/home/uxbox/uxbox \
          -v $HOME/.m2:/home/uxbox/.m2 \
          $CONTAINER ./scripts/build-and-run-tests.sh
}

function run-backend-tests {
    if ! $(docker images | grep $IMGNAME | grep -q $REV); then
        build-devenv
    fi

    CONTAINER=$IMGNAME:latest

    docker run -ti --rm \
           -w /home/uxbox/uxbox/backend \
           -v `pwd`:/home/uxbox/uxbox \
           -v $HOME/.m2:/home/uxbox/.m2 \
           $CONTAINER ./scripts/run-tests-in-docker.sh
}

function build-release-frontend-local {
    if ! $(docker images | grep $IMGNAME | grep -q $REV); then
        build-devenv
    fi

    mkdir -p $HOME/.m2
    rm -rf ./frontend/node_modules

    CONTAINER=$IMGNAME:latest

    echo "Running development image $CONTAINER to build frontend release..."
    docker run -ti --rm \
           -w /home/uxbox/uxbox/frontend \
           -v `pwd`:/home/uxbox/uxbox  \
           -v $HOME/.m2:/home/uxbox/.m2 \
           -e UXBOX_API_URL="/api" \
           -e UXBOX_VIEW_URL="/view" \
           $CONTAINER ./scripts/build-release.sh
}

function build-release-frontend {
    build-release-frontend-local || exit 1;
    rm -rf docker/release.frontend/dist || exit 1;
    cp -r frontend/dist docker/release.frontend/ || exit 1;
    docker build --rm=true -t ${IMGNAME}-frontend:$REV -t ${IMGNAME}-frontend:latest docker/release.frontend/
    rm -rf docker/release.frontend/dist || exit 1;
}

function build-release-backend-local {
    echo "Prepare backend release..."

    rsync -avr \
      --exclude="/test" \
      --exclude="/resources/public/media" \
      --exclude="/target" \
      --exclude="/scripts" \
      --exclude="/.*" \
      ./backend/ ./backend/dist/
}

function build-release-backend {
    build-release-backend-local || exit 1;
    rm -rf docker/release.backend/dist || exit 1;
    cp -r backend/dist docker/release.backend/ || exit 1;
    docker build --rm=true -t ${IMGNAME}-backend:$REV -t ${IMGNAME}-backend:latest docker/release.backend/
    rm -rf docker/release.backend/dist || exit 1;
}

function build-release {
    echo "Building frontend release..."
    build-release-frontend || exit 1;
    echo "Building backend release..."
    build-release-backend || exit 1;
}

function run-release {
    kill-container

    if ! $(docker images | grep $IMGNAME-backend | grep -q $REV); then
        build-release
    fi

    echo "Running production images..."
    sudo docker-compose -f ./docker/docker-compose.yml up -d
}

function usage {
    echo "UXBOX build & release manager v$REV"
    echo "USAGE: $0 OPTION"
    echo "Options:"
    echo "- clean                   Stop and clean up docker containers"
    echo "- build-devenv            Build docker container for development with tmux"
    echo "- run-devenv              Run (and build if necessary) development container (frontend at localhost:3449, backend at localhost:6060)"
    echo "- run-all-tests           Execute unit tests for both backend and frontend"
    echo "- run-frontend-tests      Execute unit tests for frontend only"
    echo "- run-backend-tests       Execute unit tests for backend only"
    echo "- build-release           Build 'production ready' docker images for both backend and frontend"
    echo "- build-release-frontend  Build a 'production ready' docker images for frontend only"
    echo "- build-release-backend   Build a 'production ready' docker images for backend only"
    echo "- run-release             Run 'production ready' docker images for both backend and frontend"
}

case $1 in
    clean)
        kill-container
        remove-image
        ;;
    build-devenv)
        build-devenv
        ;;
    run-devenv)
        run-devenv
        ;;
    run-all-tests)
        run-all-tests
        ;;
    run-frontend-tests)
        run-frontend-tests
        ;;
    run-backend-tests)
        run-backend-tests
        ;;
    build-release)
        build-release
        ;;
    build-release-frontend)
        build-release-frontend
        ;;
    build-release-backend)
        build-release-backend
        ;;
    run-release)
        run-release
        ;;
    *)
        usage
        ;;
esac
