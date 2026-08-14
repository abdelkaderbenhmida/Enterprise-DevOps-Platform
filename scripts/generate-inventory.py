#!/usr/bin/env python3
"""Dynamic inventory generator: reads terraform output -json and renders Ansible inventory"""

import json
import sys
import subprocess
from pathlib import Path

VM_ROLE_GROUPS = {
    "bastion": ["bastion"],
    "terraform": ["mgmt", "terraform"],
    "ansible": ["mgmt", "ansible"],
    "git": ["mgmt", "git"],
    "jenkins-master": ["mgmt", "jenkins", "jenkins_master"],
    "jenkins-agent": ["mgmt", "jenkins", "jenkins_agent"],
    "k8s-cp": ["k8s", "k8s_control_plane"],
    "k8s-wk": ["k8s", "k8s_workers"],
    "pg-primary": ["data", "postgresql", "postgresql_primary"],
    "pg-replica": ["data", "postgresql", "postgresql_replica"],
    "prometheus": ["monitoring", "prometheus"],
    "grafana": ["monitoring", "grafana"],
    "nginx-lb": ["infra", "loadbalancers", "nginx_lb"],
    "haproxy-lb": ["infra", "loadbalancers", "haproxy_lb"],
    "backend-standalone": ["apps", "standalone"],
    "frontend-standalone": ["apps", "standalone"],
    "test-staging": ["apps", "standalone", "staging"],
}

def run_terraform_output(terraform_dir):
    """Run terraform output -json and return parsed JSON."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running terraform output: {e.stderr}", file=sys.stderr)
        return {}
    except json.JSONDecodeError as e:
        print(f"Error parsing terraform output: {e}", file=sys.stderr)
        return {}

def build_inventory(tf_output):
    """Build Ansible inventory from terraform output."""
    inventory = {
        "_meta": {"hostvars": {}},
        "all": {"children": ["ungrouped"]}
    }
    
    vm_ips = tf_output.get("vm_ips", {}).get("value", {})
    
    for vm_name, vm_info in vm_ips.items():
        private_ip = vm_info.get("private_ip")
        if not private_ip:
            continue
            
        host_entry = {
            "ansible_host": private_ip,
            "ansible_user": "ubuntu",
            "ansible_ssh_private_key_file": "~/.ssh/id_rsa",
        }
        
        inventory["_meta"]["hostvars"][vm_name] = host_entry
        
        role = None
        for key, groups in VM_ROLE_GROUPS.items():
            if key in vm_name:
                role = key
                for group in groups:
                    if group not in inventory:
                        inventory[group] = {"hosts": []}
                    if "hosts" not in inventory[group]:
                        inventory[group]["hosts"] = []
                    inventory[group]["hosts"].append(vm_name)
                break
        
        if role is None:
            if "ungrouped" not in inventory:
                inventory["ungrouped"] = {"hosts": []}
            inventory["ungrouped"]["hosts"].append(vm_name)
    
    if "all" in inventory and "children" in inventory["all"]:
        all_groups = set(inventory.keys()) - {"_meta", "all", "ungrouped"}
        inventory["all"]["children"] = list(all_groups) + ["ungrouped"]
    
    return inventory

def main():
    terraform_dir = Path(__file__).resolve().parent.parent / "terraform" / "environments" / "dev"
    
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        tf_output = run_terraform_output(terraform_dir)
        inventory = build_inventory(tf_output)
        print(json.dumps(inventory, indent=2))
    elif len(sys.argv) > 1 and sys.argv[1] == "--host":
        print(json.dumps({}))
    else:
        tf_output = run_terraform_output(terraform_dir)
        inventory = build_inventory(tf_output)
        
        lines = []
        for group_name, group_data in inventory.items():
            if group_name in ("_meta", "all"):
                continue
            hosts = group_data.get("hosts", [])
            if hosts:
                lines.append(f"[{group_name}]")
                for host in hosts:
                    hostvars = inventory["_meta"]["hostvars"].get(host, {})
                    ansible_host = hostvars.get("ansible_host", "")
                    lines.append(f"{host} ansible_host={ansible_host}")
                lines.append("")
        
        print("\n".join(lines))

if __name__ == "__main__":
    main()