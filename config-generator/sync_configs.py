import os
import json
import yaml
import requests
from jinja2 import Environment, FileSystemLoader
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# --- Configuration ---
PANEL_URL = os.getenv("PANEL_URL")
USERNAME = os.getenv("PANEL_USERNAME")
PASSWORD = os.getenv("PANEL_PASSWORD")
# Default to inbound ID 1 if not set
INBOUND_ID = int(os.getenv("INBOUND_ID", 1))
GIST_ID = os.getenv("GIST_ID")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
# Host is optional in .env, defaults to parsed value or empty
SERVER_HOST = os.getenv("SERVER_HOST") 

# --- Helper Functions ---

def to_yaml_filter(value):
    """
    Custom Jinja2 filter to convert a Python dictionary 
    into a YAML formatted string.
    """
    return yaml.dump(value, default_flow_style=False, allow_unicode=True, sort_keys=False).strip()

def get_panel_session():
    """
    Authenticates with the 3x-ui panel and returns a session object 
    containing the authentication cookies.
    """
    session = requests.Session()
    login_url = f"{PANEL_URL}/login"
    payload = {'username': USERNAME, 'password': PASSWORD}
    
    try:
        print(f"🔌 Connecting to panel at: {PANEL_URL}")
        res = session.post(login_url, data=payload)
        res.raise_for_status()
        
        response_json = res.json()
        if response_json.get('success'):
            print("✅ Login successful")
            return session
        else:
            print(f"❌ Login failed: {response_json.get('msg')}")
            return None
    except Exception as e:
        print(f"❌ Connection error: {e}")
        return None

def get_inbound_data(session):
    """
    Retrieves the list of inbounds via MHSanaei API and finds the specific one by ID.
    """
    try:
        # MHSanaei API uses GET request
        res = session.get(f"{PANEL_URL}/panel/api/inbounds/list")
        res.raise_for_status()
        
        data = res.json()
        if not data.get('success'):
            print(f"❌ API failure: {data.get('msg')}")
            return None
            
        # Find the inbound with the matching ID
        inbound_list = data.get('obj', [])
        target = next((i for i in inbound_list if i['id'] == INBOUND_ID), None)
        
        if not target:
            print(f"❌ Inbound ID {INBOUND_ID} not found")
            return None
            
        return target
    except Exception as e:
        print(f"❌ API error: {e}")
        return None

def parse_vless_settings(inbound):
    """
    Parses the raw JSON settings from 3x-ui (MHSanaei version with camelCase keys).
    Returns: (base_proxy_dict, clients_list)
    """
    try:
        # 1. Parse nested JSON strings using camelCase keys
        stream_settings = json.loads(inbound['streamSettings'])
        settings = json.loads(inbound['settings'])
    except Exception as e:
        print(f"❌ Failed to parse inbound JSON settings: {e}")
        return None, []

    # 2. Determine server address
    address = SERVER_HOST if SERVER_HOST else "YOUR_SERVER_IP"

    # 3. Construct base proxy object
    base_proxy = {
        'type': inbound['protocol'],
        'server': address,
        'port': inbound['port'],
        'network': stream_settings.get('network', 'tcp'),
        'tls': False,
        'udp': True,
    }

    # 4. Handle Security Settings (Reality)
    security = stream_settings.get('security', 'none')
    
    if security == 'reality':
        base_proxy['tls'] = True
        base_proxy['flow'] = 'xtls-rprx-vision'
        base_proxy['client-fingerprint'] = 'chrome'
        
        # Extract Reality specific settings
        reality = stream_settings.get('realitySettings', {})
        base_proxy['servername'] = reality.get('serverNames', [''])[0]
        
        base_proxy['reality-opts'] = {
            'public-key': reality.get('settings', {}).get('publicKey'),
            'short-id': reality.get('shortIds', [''])[0]
        }
        
    elif security == 'tls':
        base_proxy['tls'] = True
        tls = stream_settings.get('tlsSettings', {})
        base_proxy['servername'] = tls.get('serverNames', [''])[0]

    # 5. Extract clients list
    clients = settings.get('clients', [])
    return base_proxy, clients

def load_extra_servers():
    """
    Loads additional servers from the local YAML file.
    """
    file_path = 'extra_servers.yaml'
    if os.path.exists(file_path):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)
                if isinstance(data, list):
                    return data
                return []
        except Exception as e:
            print(f"⚠️ Error loading extra servers: {e}")
            return []
    return []

def update_gist(files_payload):
    """
    Uploads the generated files to GitHub Gist.
    """
    if not GITHUB_TOKEN or not GIST_ID:
        print("⚠️ GITHUB_TOKEN or GIST_ID is missing. Skipping upload.")
        return

    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json',
    }
    
    # Prepare payload for the API
    payload = {'files': files_payload}
    
    try:
        print(f"🚀 Uploading {len(files_payload)} files to Gist...")
        res = requests.patch(f"https://api.github.com/gists/{GIST_ID}", headers=headers, json=payload)
        res.raise_for_status()
        print("✅ Gist updated successfully!")
    except Exception as e:
        print(f"❌ Failed to upload Gist: {e}")
        # Print detailed response for debugging
        if 'res' in locals():
            print(res.text)

# --- Main Execution ---

def main():
    # 1. Authenticate
    session = get_panel_session()
    if not session: return

    # 2. Get Inbound Information
    inbound = get_inbound_data(session)
    if not inbound: return
    
    print(f"ℹ️ Found inbound: {inbound['remark']} (Port: {inbound['port']})")

    # 3. Parse Settings
    base_proxy_config, clients = parse_vless_settings(inbound)
    if not base_proxy_config: return
    
    print(f"ℹ️ Extracted {len(clients)} clients")

    # 4. Load Extra Servers
    extra_proxies = load_extra_servers()

    # 5. Prepare Jinja2 Template
    # Construct absolute path to the templates directory
    base_dir = os.path.dirname(os.path.abspath(__file__))
    template_dir = os.path.join(base_dir, 'templates')
    
    env = Environment(loader=FileSystemLoader(template_dir))
    env.filters['to_yaml'] = to_yaml_filter
    
    try:
        template = env.get_template('clash_client_template.yaml.j2')
    except Exception as e:
        print(f"❌ Template error: {e}")
        return

    # 6. Generate Configs
    generated_files_content = {}
    output_dir = os.path.join(base_dir, 'generated_configs')
    os.makedirs(output_dir, exist_ok=True)
    
    for client in clients:
        if not client.get('email') or not client.get('id'): continue

        client_email = client['email']
        
        # Create client specific proxy
        client_proxy = base_proxy_config.copy()
        client_proxy['name'] = f"MY-SERVER-{client_email}" 
        client_proxy['uuid'] = client['id']
        
        # Combine proxies
        all_proxies = [client_proxy] + extra_proxies
        
        # Render and save
        config_content = template.render(all_proxies=all_proxies)
        
        filename = f"{client_email}.yaml"
        with open(os.path.join(output_dir, filename), 'w', encoding='utf-8') as f:
            f.write(config_content)
            
        generated_files_content[filename] = {'content': config_content}
        print(f"📄 Generated: {filename}")

    # 7. Upload to Gist
    if generated_files_content:
        update_gist(generated_files_content)
    else:
        print("⚠️ No configs generated")

if __name__ == "__main__":
    main()