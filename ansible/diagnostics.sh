# ansible GaryPC -m win_ping -i inventory.yml --extra-vars \
# "cert_pem=/home/gxbrooks/.winrm/ansible_client_cert.pem cert_key_pem=/home/gxbrooks/.winrm/ansible_client_private_key.pem ansible_winrm_transport=certificate"



 
# ansible GaryPC -m win_ping -i inventory.yml --extra-vars "wincert_pem=/home/gxbrooks/.winrm/ansible_client_cert.pem cert_key_pem=/home/gxbrooks/.winrm/ansible_client_private_key.pem ansible_winrm_transport=certificate"

# ansible-playbook -i inventory.yml playbooks/win_ping.yml -vvvv

curl -v --cert ~/.winrm/ansible_client_cert.pem --key ~/.winrm/ansible_client_private_key.pem --cacert ~/.winrm/WinRM_SSL_Cert@GaryPC.local.pem  https://GaryPC.local:5986/wsman

curl -v \
	--cert ~/.winrm/ansible_client_cert.pem \
	--key ~/.winrm/ansible_client_private_key.pem \
	--cacert ~/.winrm/WinRM_SSL_Cert@GaryPC.local.pem \
	-X POST \
	-H "Content-Type: application/xml" \
	--data "@status.xml" \
	https://GaryPC.local:5986/wsman

curl -v \
	--cert ~/.winrm/ansible_client_cert.pem \
	--key ~/.winrm/ansible_client_private_key.pem \
	--cacert ~/.winrm/WinRM_SSL_Cert@GaryPC.local.pem \
	-X POST \
	-H "Content-Type: application/xml" \
	--data "@status2.xml" \
	https://GaryPC.local:5986/wsman
  

# Simpler payload
curl -v \
	--cert ~/.winrm/ansible_client_cert.pem \
	--key ~/.winrm/ansible_client_private_key.pem \
	--cacert ~/.winrm/WinRM_SSL_Cert@GaryPC.local.pem \
	-H "Content-Type: application/xml" \
	--data "<status/>" \
	https://GaryPC.local:5986/wsman


