import winrm
import ssl

try:
    s = winrm.Session('GaryPC.lan', auth_type='cert', cert_file='/home/gxbrooks/.winrm/ansible_client_cert.pem', cert_key_file='/home/gxbrooks/.winrm/ansible_client_private_key.pem', transport='cert', server_cert_validation='ignore')
    r = s.run_cmd('ipconfig')
    print(r.std_out.decode('utf-8'))
except ssl.SSLError as e:
    print(f"SSL Error: {e}")
except Exception as e:
    print(f"Other Error: {e}")
