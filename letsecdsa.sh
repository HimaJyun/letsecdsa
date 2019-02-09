#!/bin/bash -u

if [ -z "${1-}" ];then
	echo "Usage: $0 letsecdsa.conf"
	exit 1
fi
source "$1"

# Check config
REQUIRED_CONFIG=(
	"CERTBOT_PATH" "DEST_PATH" "COMMON_NAME"
)
for var_name in "${REQUIRED_CONFIG[@]}";do
	if [ ! -v "${var_name}" ];then
		echo "Error: Variable \$${var_name} is not found"
		exit 1
	fi
done
if [ -z "${DOMAINS[*]-}" ];then
	echo "Error: Variable \$DOMAINS is not found"
	exit 1
fi

# Check commands.
if [ "$(whoami)" != "root" ];then
	echo "require root"
	exit 1
fi
if [ -z "$(command -v openssl)" ];then
	echo "require OpenSSL"
	exit 1
fi
if [ ! -x "${CERTBOT_PATH}" ];then
	echo "${CERTBOT_PATH} is not executable"
	exit 1
fi

echo "${0}: $(date)"

# Move to tmp directory.
tmp=$(mktemp -d)
cd "${tmp}"
if [ "${DEBUG-}" = "true" ];then
	echo "Debug: ${tmp}"
	set -x
else
	trap "rm -rv ${tmp}" EXIT
fi

: "Check expire" && test "${FORCE_RENEW-}" != "true" && test -f "${DEST_PATH}/live/cert.pem" && {
	if openssl x509 -in "${DEST_PATH}/live/cert.pem" -checkend "$((${RENEW_DAYS-30}*24*60*60))" > /dev/null;then
		echo "There is no need to renew."
		exit 0
	fi
}

: "Issue new certificate" && {
	# Create new private key
	openssl ecparam -out ./privkey.pem -name prime256v1 -genkey

	#SANs
	san=""
	for domain in "${!DOMAINS[@]}";do
		san="${san}, DNS:${domain}"
	done
	# ", DNS:example.com, DNS:www.example.com" -> "DNS:example.com, DNS:www.example.com"
	san="${san:2}"
	# Create CSR config
	cat <<- __EOL__ > ./csr.cnf
		[req]
		prompt = no
		default_md = sha256
		distinguished_name = req_dn
		req_extensions = req_ext

		[req_dn]
		CN = ${COMMON_NAME}

		[req_ext]
		subjectAltName = ${san}
	__EOL__
	# Create CSR
	openssl req -new -key ./privkey.pem -outform der -out ./csr.der -config ./csr.cnf

	# Building certbot command arguments.
	COMMAND=("${CERTBOT_PATH}" "certonly" "--webroot")
	COMMAND+=("--csr" "./csr.der")
	COMMAND+=("--redirect")
	COMMAND+=("--text" "--non-interactive")
	COMMAND+=("--force-renewal")
	# Sans
	for domain in "${!DOMAINS[@]}";do
		COMMAND+=("--webroot-path" "${DOMAINS[${domain}]}" "--domain" "${domain}")
	done
	# agree-tos
	if [ "${AGREE_TOS-}" = "true" ];then
		COMMAND+=("--agree-tos")
	fi
	# email
	if [ -v EMAIL ];then
		COMMAND+=("--email" "${EMAIL}")
	fi
	# Issue new certificate.
	"${COMMAND[@]}"

	if [ ! -e 0000_cert.pem ];then
		echo "Error: Certificate not found."
		exit 1
	fi
}

: "Move keys and Symlink update" && {
	mkdir -pv "${DEST_PATH}/archive"
	mkdir -pv "${DEST_PATH}/live"
	# get generation
	generation=$(find "${DEST_PATH}/archive/" -mindepth 1 -maxdepth 1 -type f -print0 | xargs -0 -n1 basename | grep -o "[0-9]*" | sort -nr | head -1)
	echo "Current generation: ${generation}"
	generation=$((${generation-0}+1))

	# Move keys.
	mv -v ./0000_cert.pem "${DEST_PATH}/archive/cert${generation}.pem"
	mv -v ./0000_chain.pem "${DEST_PATH}/archive/chain${generation}.pem"
	mv -v ./0001_chain.pem "${DEST_PATH}/archive/fullchain${generation}.pem"
	mv -v ./privkey.pem "${DEST_PATH}/archive/privkey${generation}.pem"
	chmod -v 600 "${DEST_PATH}/archive/cert${generation}.pem"
	chmod -v 600 "${DEST_PATH}/archive/chain${generation}.pem"
	chmod -v 600 "${DEST_PATH}/archive/fullchain${generation}.pem"
	chmod -v 600 "${DEST_PATH}/archive/privkey${generation}.pem"

	# Update symlink
	find "${DEST_PATH}/live" -mindepth 1 -maxdepth 1 -type l -print0 | xargs -0 -n1 unlink
	ln -vs "${DEST_PATH}/archive/cert${generation}.pem" "${DEST_PATH}/live/cert.pem"
	ln -vs "${DEST_PATH}/archive/chain${generation}.pem" "${DEST_PATH}/live/chain.pem"
	ln -vs "${DEST_PATH}/archive/fullchain${generation}.pem" "${DEST_PATH}/live/fullchain.pem"
	ln -vs "${DEST_PATH}/archive/privkey${generation}.pem" "${DEST_PATH}/live/privkey.pem"
}

: "Reload web server" && test -n "${RELOAD_COMMAND[*]-}" && {
	if "${RELOAD_COMMAND[@]}";then
		echo "Successful reloading."
	else
		echo "Reload failed."
	fi
}
