#!/bin/bash
# =============================================================================
# Install Docker on Oracle Linux 9
# Run with: sudo ./docker/scripts/install-docker.sh
# =============================================================================

set -e

echo "=== Installing Docker on Oracle Linux 9 ==="

# 1. Remove old versions (if any)
sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

# 2. Install dnf-plugins-core (for config-manager)
sudo dnf install -y dnf-plugins-core

# 3. Add Docker repository (CentOS repo works for Oracle Linux/RHEL)
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 4. Install Docker CE
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# 6. Add current user to docker group (for non-root access)
if [ -n "$SUDO_USER" ]; then
  sudo usermod -aG docker "$SUDO_USER"
  echo "Added $SUDO_USER to docker group. Log out and back in for it to take effect."
fi

# 7. Verify
echo ""
echo "=== Docker installed ==="
sudo docker --version
echo ""
echo "Run 'docker run hello-world' to verify. If using opc user, you may need to log out and back in first."
echo "Or run: sudo docker run hello-world"
