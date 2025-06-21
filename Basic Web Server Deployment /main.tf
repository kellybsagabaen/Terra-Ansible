# main.tf

# Define required providers and their sources
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0" # Use a compatible version
    }
  }
}

# Configure the Docker provider
provider "docker" {}

# 1. Pull the Ubuntu image
resource "docker_image" "ubuntu" {
  name         = "ubuntu:latest"
  keep_locally = true # Keep the image after destroy for faster re-runs
}

# 2. Create and run an Ubuntu container
resource "docker_container" "web_server_container" {
  name  = "my-local-webserver"
  image = docker_image.ubuntu.name # Use the pulled Ubuntu image
  
  # Expose port 8000 on your host machine to port 80 inside the container
  # You will access Nginx via http://localhost:8000
  ports {
    internal = 80
    external = 8000
  }

  # Ensure the container is restarted if it stops
  restart = "on-failure"

  # Increase the shm_size for some applications; good practice for web servers
  shm_size = 512 # MB

  # === Ansible Integration (local-exec provisioner) ===
  # This provisioner runs commands on the machine where 'terraform apply' is executed.
  # We use it here to trigger our Ansible playbook.
  provisioner "local-exec" {
    # This command executes the Ansible playbook.
    # --inventory: specifies the inventory file.
    # --extra-vars: passes variables to Ansible (container_name here).
    # --ssh-common-args / --ssh-extra-args: This is CRITICAL for Ansible to connect to Docker.
    #    It tells Ansible to use the 'docker exec' command for connection, not SSH.
    #    The 'connection=docker' in inventory is also needed for this.
    command = "ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/playbook.yml --extra-vars \"container_name=${self.name}\" --ssh-common-args='-o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no' --ssh-extra-args='-o UserKnownHostsFile=/dev/null'"
    
    # Wait a few seconds to ensure the container is fully up and network ready
    # before Ansible tries to connect. This helps prevent "connection refused" errors.
    # The 'sleep' command might vary slightly based on your OS (e.g., 'timeout /T 5' on Windows).
    # You might need to adjust this value.
    interpreter = ["/bin/bash", "-c"] # Use bash explicitly for sleep command
    # Windows equivalent: interpreter = ["cmd.exe", "/C"] and use 'timeout /T 5' or 'ping 127.0.0.1 -n 6 > nul'
    
    # This 'sleep' is often needed. Remove if you experience very fast successful runs without it.
    # It's better to be explicit about interpreter if you use features like sleep.
    # For Windows, you'd typically use something like "timeout /t 5 >nul" or "ping -n 6 127.0.0.1 >nul"
    # If running on Linux/macOS
    # The '|| true' allows the 'sleep' command to fail without failing the whole provisioner if there's a weird shell issue.
    # However, it's safer to ensure sleep is correct.
    # Let's simplify and rely on the container being ready shortly.
    # The 'wait-for-it.sh' script or similar external tools are more robust for real dependencies.
    # For a basic project, a simple sleep often suffices.
    
    # Adding a simple sleep for robustness, adapt if issues persist.
    # cmd.exe /C for Windows: command = "timeout /t 5 > nul && ansible-playbook ..."
    # /bin/bash -c for Linux/macOS
    # We will put the sleep in the command itself.
    command = "sleep 5 && ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/playbook.yml --extra-vars \"container_name=${self.name}\" --ssh-common-args='-o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no' --ssh-extra-args='-o UserKnownHostsFile=/dev/null'"
  }
}

# Output the URL to easily access your Nginx web server
output "nginx_url" {
  description = "URL to access the Nginx web server on your local machine."
  value       = "http://localhost:${docker_container.web_server_container.ports[0].external}"
}