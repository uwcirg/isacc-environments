# ISACC Environments
ISACC environments, generates a full stack functional
project conforming to the SMART on FHIR (SoF) protocol.

Please also see the following component projects:
- [ISACC Messaging Service](https://github.com/uwcirg/isacc-messaging-service). The server app managing SMS communications
- [ISACC Messaging Client](https://github.com/uwcirg/isacc-messaging-client-sof). The SMART-on-FHIR web client

## Product Elements
- fEMR
  - [fEMR web service](https://github.com/uwcirg/cosri-patientsearch)
  - [HAPI FHIR](https://hapifhir.io/)
  - [JWTProxy](https://github.com/uwcirg/jwt-proxy)
  - [KeyCloak](https://www.keycloak.org/)
  - [PostgreSQL](https://postgrest.org/en/stable/)
  - [Redis](https://redis.io/)
- [Log Server](https://github.com/uwcirg/logserver)
- [Enrollment Client](https://github.com/uwcirg/isacc-enrollment-client-sof)
- [Messaging Client](https://github.com/uwcirg/isacc-messaging-client-sof)

## Setup
Clone this repo to your desired location and follow Setup steps in [`dev`](./dev/README.md), to setup a development deploy.
