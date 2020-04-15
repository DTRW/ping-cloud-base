#!/usr/bin/env sh

########################################################################################################################
# Makes curl request to PingAccess API using the INITIAL_ADMIN_PASSWORD environment variable.
#
########################################################################################################################
function make_api_request() {
    http_code=$(curl -k -o ${OUT_DIR}/api_response.txt -w "%{http_code}" \
         --retry ${API_RETRY_LIMIT} \
         --max-time ${API_TIMEOUT_WAIT} \
         --retry-delay 1 \
         --retry-connrefused \
         -u ${PA_ADMIN_USER_USERNAME}:${PA_ADMIN_USER_PASSWORD} \
         -H "X-Xsrf-Header: PingAccess " "$@")

    if test ! $? -eq 0; then
        echo "Admin API connection refused"
        exit 1
    fi

    if test ${http_code} -ge "300"; then
        echo "API call returned HTTP status code: ${http_code}"
        cat ${OUT_DIR}/api_response.txt && rm -f ${OUT_DIR}/api_response.txt
        exit 1
    fi

    cat ${OUT_DIR}/api_response.txt && rm -f ${OUT_DIR}/api_response.txt
}

########################################################################################################################
# Makes curl request to PingAccess API using the '2Access' password.
#
########################################################################################################################
function make_initial_api_request() {
    http_code=$(curl -k -o ${OUT_DIR}/api_response.txt -w "%{http_code}" \
         --retry ${API_RETRY_LIMIT} \
         --max-time ${API_TIMEOUT_WAIT} \
         --retry-delay 1 \
         --retry-connrefused \
         -u ${PA_ADMIN_USER_USERNAME}:${OLD_PA_ADMIN_USER_PASSWORD} \
         -H "X-Xsrf-Header: PingAccess " "$@")

    if test ! $? -eq 0; then
        echo "Admin API connection refused"
        exit 1
    fi

    if test ${http_code} -ge "300"; then
        echo "API call returned HTTP status code: ${http_code}"
        cat ${OUT_DIR}/api_response.txt && rm -f ${OUT_DIR}/api_response.txt
        exit 1
    fi

    cat ${OUT_DIR}/api_response.txt && rm -f ${OUT_DIR}/api_response.txt
}

########################################################################################################################
# Used for API calls that specify an output file.
# When using this function the existence of the output file
# should be used to verify this function succeeded.
#
########################################################################################################################
function make_api_request_download() {
    curl -k \
         --retry ${API_RETRY_LIMIT} \
         --max-time ${API_TIMEOUT_WAIT} \
         --retry-delay 1 \
         --retry-connrefused \
         -u ${PA_ADMIN_USER_USERNAME}:${PA_ADMIN_USER_PASSWORD} \
         -H "X-Xsrf-Header: PingAccess " "$@"

    if test ! $? -eq 0; then
        echo "Admin API connection refused"
        exit 1
    fi
}

########################################################################################################################
# Makes curl request to localhost PingAccess admin Console heartbeat page.
# If request fails, wait for 3 seconds and try again.
#
########################################################################################################################
function pingaccess_admin_wait() {
    while true; do
        curl -ss --silent -o /dev/null -k https://localhost:9000/pa/heartbeat.ping 
        if ! test $? -eq 0; then
            echo "Import Config: Server not started, waiting.."
            sleep 3
        else
            echo "PA started, begin import"
            break
        fi
    done
}

########################################################################################################################
# Function to install AWS command line tools
#
########################################################################################################################
function installAwsCliTools() {
  if test -z "$(which aws)"; then
    #   
    #  Install AWS platform specific tools
    #
    echo "Installing AWS CLI tools for S3 support"
    #
    # TODO: apk needs to move to the Docker file as the package manager is plaform specific
    #
    apk --update add python3
    pip3 install --no-cache-dir --upgrade pip
    pip3 install --no-cache-dir --upgrade awscli
  fi
}

########################################################################################################################
# Function calls installAwsCliTools() and sets required environment variables for AWS S3 bucket
#
########################################################################################################################
function initializeS3Configuration() {
  unset BUCKET_URL_NO_PROTOCOL
  unset BUCKET_NAME
  unset DIRECTORY_NAME
  unset TARGET_URL

  # Allow overriding the backup URL with an arg
  test ! -z "${1}" && BACKUP_URL="${1}"

  # Install AWS CLI if the upload location is S3
  if test "${BACKUP_URL#s3}" == "${BACKUP_URL}"; then
    echo "Upload location is not S3"
    exit 1
  else
    installAwsCliTools
  fi

  export BUCKET_URL_NO_PROTOCOL=${BACKUP_URL#s3://}
  export BUCKET_NAME=$(echo "${BUCKET_URL_NO_PROTOCOL}" | cut -d/ -f1)
  export DIRECTORY_NAME=$(echo "${PING_PRODUCT}" | tr '[:upper:]' '[:lower:]')

  if test "${BACKUP_URL}" == */"${DIRECTORY_NAME}"; then
    export TARGET_URL="${BACKUP_URL}"
  else
    export TARGET_URL="${BACKUP_URL}/${DIRECTORY_NAME}"
  fi
}

########################################################################################################################
# Function to change password.
#
########################################################################################################################
function changePassword() {
  # Validate before attempting to change password
  if test -z "${OLD_PA_ADMIN_USER_PASSWORD}" || test -z "${PA_ADMIN_USER_PASSWORD}"; then
    echo "The old and new passwords cannot be blank"
    return 1
  elif test "${OLD_PA_ADMIN_USER_PASSWORD}" = "${PA_ADMIN_USER_PASSWORD}"; then
    echo "old passsword and new password are the same, therefore cannot update passsword"
    return 1
  else
    set +x
    # Change the default password.
    # Using set +x to suppress shell debugging
    # because it reveals the new admin password
    change_password_payload=$(envsubst < ${STAGING_DIR}/templates/81/change_password.json)
    make_initial_api_request -s -X PUT \
        -d "${change_password_payload}" \
        "https://localhost:9000/pa-admin-api/v3/users/1/password" > /dev/null
    CHANGE_PASWORD_STATUS=${?}
    set -x

    echo "password change status: ${CHANGE_PASWORD_STATUS}"

    # If no error, write password to disk
    if test ${CHANGE_PASWORD_STATUS} -eq 0; then
      createSecretFile
      return 0
    fi

    echo "error changing password"
    return ${CHANGE_PASWORD_STATUS}
  fi
}

########################################################################################################################
# Function to read password within ${OUT_DIR}/secrets/pa-admin-password.
#
########################################################################################################################
function readPasswordFromDisk() {
  set +x
  # if file doesn't exist return empty string
  if ! test -f ${OUT_DIR}/secrets/pa-admin-password; then
    echo ""
  else 
    password=$( cat ${OUT_DIR}/secrets/pa-admin-password )
    echo ${password}
  fi
  set -x
}

########################################################################################################################
# Function to write admin password to disk.
#
########################################################################################################################
function createSecretFile() {
  # make directory if it doesn't exist
  mkdir -p ${OUT_DIR}/secrets
  echo "${PA_ADMIN_USER_PASSWORD}" > ${OUT_DIR}/secrets/pa-admin-password
}