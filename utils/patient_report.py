#!/usr/bin/env python3
'''
This script generates a CSV file of all Patient resources in the system.
To run: 
  docker-compose run --volume=${PWD}/utils:/opt/utils femr \
    python3 /opt/utils/patient_report.py
It accepts no arguments.
'''

import subprocess
import json
import csv
import urllib.parse

base_url = "http://fhir-internal:8080/fhir"

def get_fhir_resource(url):

    print(f"get_fhir_resource({url}), just entered.")

    command = f"docker-compose exec femr curl -X GET {url}"
    result = subprocess.run(command, shell=True, capture_output=True, text=True)

    print(f"get_fhir_resource({url}), subprocess has been run.")

    if result.returncode != 0:
        raise Exception(f"get_fhir_resource({url}), command failed with exit code {result.returncode}: {result.stderr}")

    #print(f"get_fhir_resource({url}), result.stdout:{result.stdout}")

    # Assuming the output is JSON, parse it
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        raise Exception(f"get_fhir_resource({url}), failed to parse JSON from command output")

#    response = requests.get(url)
#    response.raise_for_status()  # Ensure we stop on HTTP errors
#    return response.json()

def construct_next_url(next_url):
    # Parse the query parameters from the next URL
    next_query_params = urllib.parse.urlparse(next_url).query
    #print(f"construct_next_url({next_url}), here's next_query_params:{next_query_params}")
    next_params = urllib.parse.parse_qs(next_query_params)

    # Extract needed parameters
    getpages = next_params.get('_getpages', [''])[0]
    getpagesoffset = next_params.get('_getpagesoffset', [''])[0]
    count = next_params.get('_count', [''])[0]
    bundletype = next_params.get('_bundletype', [''])[0]

    # Construct the new URL
    new_url = f"{base_url}\?_getpages={getpages}\&_getpagesoffset={getpagesoffset}\&_count={count}\&_bundletype={bundletype}"
    return new_url

def main():
    url = f"{base_url}/Patient"

    with open('PatientReport.csv', 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["FHIR ID", "ISACC ID", "Last Name", "First Name", "Preferred Name"])

        while url:
            data = get_fhir_resource(url)
            for entry in data.get('entry', []):
                patient = entry['resource']
                patient_id = patient.get('id')

                # Initialize ISACC ID as empty string
                isacc_id = ""
                # Search for ISACC ID in the patient's identifiers
                for identifier in patient.get('identifier', []):
                    if identifier.get('system') == "http://isacc.app/user-id":
                        isacc_id = identifier.get('value', "")
                        break

                family = ""
                givens = []
                preferred_given = ""
                for name in patient.get("name", []):
                    # Append the family name if it exists.
                    if "family" in name:
                        family = name["family"]
                        if "given" in name:
                            # Join given names with a space.
                            given_str = " ".join(name["given"])
                            givens.append(given_str)
                    # If the name's use is "usual", capture its given names.
                    if name.get("use") == "usual" and "given" in name:
                        preferred_given = " ".join(name["given"])

                writer.writerow([patient_id, isacc_id, family, ''.join(givens), preferred_given])

            # Check for 'next' link for pagination
            next_link = None
            for link in data.get('link', []):
                if link.get('relation') == 'next':
                    next_link = link.get('url')
                    break

            # Update URL for the next request or break loop if no next page
            if next_link:
                url = construct_next_url(next_link)
            else:
                url = None

if __name__ == "__main__":
    main()

