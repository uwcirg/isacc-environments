# Development Configuration
Sets up a development copy of ISACC environments


## Setup
Copy the default env files:

    for file in *.default; do
        cp "$file" "${file%%.default}"
    done
Copy the `.env` file default:

    cp default.env .env

Modify the `.env` file as necessary. Lines that are not commented-out are required, commented lines are optional.


## Deploy
To pull the latest configured docker images, and re-deploy services as necessary, run the following command:

    docker-compose pull && docker-compose up --detach
