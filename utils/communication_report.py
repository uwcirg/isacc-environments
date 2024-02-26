'''
This script is intended to be run from the /dev directory of the deployment that you want to 
report from; it requires no modification to be run from that location.
It accepts no arguments.
'''

import subprocess
import json
import requests
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

def get_patient_isacc_id(patient_reference, patient_cache):
    # Check if we already have the ISACC ID for this patient
    if patient_reference in patient_cache:
        return patient_cache[patient_reference]

    patient_url = f"{base_url}/{patient_reference}"
    patient_data = get_fhir_resource(patient_url)

    # Initialize ISACC ID as empty string
    isacc_id = ""

    # Search for ISACC ID in the patient's identifiers
    for identifier in patient_data.get('identifier', []):
        if identifier.get('system') == "http://isacc.app/user-id":
            isacc_id = identifier.get('value', "")
            break

    # Cache the ISACC ID for future use
    patient_cache[patient_reference] = isacc_id
    return isacc_id

def extract_type(communication):
    for category in communication.get('category', []):
        for coding in category.get('coding', []):
            if coding.get('system') == "https://isacc.app/CodeSystem/communication-type":
                return coding.get('code')
    return None

def main():
    url = f"{base_url}/Communication?_sort=sent"
    patient_cache = {}

    with open('CommunicationReport.csv', 'w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["ID", "Datetime", "Recipient FHIR ID", "Recipient ISACC ID", "Type", "Content", "Sender", "Note"])

        while url:
            data = get_fhir_resource(url)
            for entry in data.get('entry', []):
                communication = entry['resource']
                communication_id = communication.get('id')
                datetime = communication.get('sent')
                type = extract_type(communication)
                if type in ['isacc-comment', 'isacc-non-sms-message']:
                    recipient_reference = communication.get('subject', {}).get('reference')
                else:
                    recipient_reference = communication.get('recipient', [{}])[0].get('reference')
                if recipient_reference == None:
                    recipient_reference = communication.get('sender', {}).get('reference')
                isacc_id = get_patient_isacc_id(recipient_reference, patient_cache)
                content = communication.get('payload', [{}])[0].get('contentString')
                if content:
                    content = content.replace('\n', '\\n')
                sender = communication.get('sender', {}).get('reference')
                if sender == None and type == 'isacc-auto-sent-message':
                    sender = 'system'
                note = communication.get('note', [{}])[0].get('text')
                if note:
                    note = note.replace('\n', '\\n')

                writer.writerow([communication_id, datetime, recipient_reference, isacc_id, type, content, sender, note])

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

